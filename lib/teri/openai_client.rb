require 'openai'
require 'logger'
require 'fileutils'

module Teri
  class OpenAIClient
    attr_reader :client, :logger, :model

    def initialize(options = {})
      @api_key = options[:api_key] || ENV.fetch('OPENAI_API_KEY', nil)
      unless @api_key
        raise 'OpenAI API key not found. Please set OPENAI_API_KEY environment variable or provide it as an argument.'
      end

      @model = options[:model] || 'gpt-3.5-turbo'
      @client = OpenAI::Client.new(access_token: @api_key)

      # Set up logging
      setup_logger(options[:log_file])
    end

    # Get a suggested category for a transaction based on its details and previous codings
    # @param transaction [Teri::Transaction] The transaction to get a suggestion for
    # @param accounting [Teri::Accounting] The accounting instance with previous codings
    # @return [Hash] A hash containing the suggested category and confidence score
    def suggest_category(transaction, accounting)
      previous_codings = accounting.respond_to?(:previous_codings) ? accounting.previous_codings : {}
      counterparty_hints = accounting.respond_to?(:counterparty_hints) ? accounting.counterparty_hints : {}
      available_categories = []

      # Prepare the prompt with transaction details
      prompt = build_prompt(transaction, accounting)

      # Log the previous_codings for debugging
      if @logger
        @logger.info("PREVIOUS_CODINGS: #{previous_codings.inspect}")
        @logger.info("COUNTERPARTY_HINTS: #{counterparty_hints.inspect}")
      end

      # Log the prompt
      @logger&.info("PROMPT: #{prompt}")

      # Call the OpenAI API
      response = @client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: 'user', content: prompt },
          ],
        }
      )

      # Log the response
      @logger&.info("RESPONSE: #{response.dig('choices', 0, 'message', 'content')}")

      # Parse the response
      parse_suggestion(response, available_categories)
    end

    # Build a prompt for the OpenAI API
    # @param transaction [Teri::Transaction] The transaction to get a suggestion for
    # @param accounting [Teri::Accounting] The accounting instance with previous codings
    # @return [String] The prompt for the OpenAI API
    def build_prompt(transaction, accounting)
      prompt = "Transaction details:\n"
      prompt += "Date: #{transaction.date}\n"
      prompt += "Description: #{transaction.description}\n"

      prompt += "Memo: #{transaction.memo}\n" if transaction.respond_to?(:memo) && transaction.memo

      prompt += "Amount: #{transaction.amount}\n" if transaction.respond_to?(:amount)

      if transaction.respond_to?(:counterparty) && transaction.counterparty
        prompt += "Counterparty: #{transaction.counterparty}\n"
      end

      if transaction.respond_to?(:hints) && transaction.hints && !transaction.hints.empty?
        prompt += "\nHints from previous categorizations:\n"
        transaction.hints.each do |hint|
          prompt += "- #{hint}\n"
        end
      end

      # Add previous codings section if available
      if accounting.respond_to?(:previous_codings) && accounting.previous_codings && !accounting.previous_codings.empty?
        prompt += "\nPrevious codings:\n"
        accounting.previous_codings.each do |desc, info|
          next unless info.is_a?(Hash)

          prompt += if info[:hints] && !info[:hints].empty?
                      "- \"#{desc}\" => #{info[:category]} (hints: #{info[:hints].join(', ')})\n"
                    else
                      "- \"#{desc}\" => #{info[:category]}\n"
                    end
        end
      end

      # Add counterparty hints if available
      if accounting.respond_to?(:counterparty_hints) &&
         transaction.respond_to?(:counterparty) &&
         transaction.counterparty &&
         accounting.counterparty_hints[transaction.counterparty]
        prompt += "\nCounterparty information:\n"
        accounting.counterparty_hints[transaction.counterparty].each do |hint|
          prompt += "- #{hint}\n"
        end
      end

      prompt += "\nPlease respond with a JSON object containing:\n"
      prompt += "- category: The suggested category (e.g., 'Expenses:Office')\n"
      prompt += "- confidence: A number between 0-100 indicating your confidence\n"
      prompt += "- explanation: A brief explanation of your suggestion\n"

      prompt
    end

    private

    # Set up the logger
    # @param log_file [String] The path to the log file
    def setup_logger(log_file = nil)
      # Skip logger setup if we're in a test environment
      if defined?(RSpec)
        @logger = nil
        return
      end

      begin
        # Create logs directory if it doesn't exist
        FileUtils.mkdir_p('logs')

        # Use the provided log file or create a default one with timestamp
        log_file ||= "logs/openai_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log"

        @logger = Logger.new(log_file)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, _progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
        end

        @logger.info('OpenAI client initialized')
      rescue StandardError => e
        puts "Warning: Failed to set up OpenAI logging: #{e.message}"
        @logger = nil
      end
    end

    # Parse the suggestion from the OpenAI API response
    # @param response [Hash] The response from the OpenAI API
    # @param available_categories [Array<String>] A list of available categories
    # @return [Hash] A hash containing the suggested category and confidence score
    def parse_suggestion(response, available_categories = [])
      content = response.dig('choices', 0, 'message', 'content')
      return { category: 'Expenses:Unknown', confidence: 0, explanation: 'Failed to parse AI response' } unless content

      begin
        # Parse the JSON response
        suggestion = JSON.parse(content, symbolize_names: true)

        # Set default values if missing
        suggestion[:category] ||= 'Expenses:Unknown'
        suggestion[:confidence] ||= 0
        suggestion[:explanation] ||= 'No explanation provided'

        # Convert confidence to a float between 0 and 1 if it's a percentage
        if suggestion[:confidence].is_a?(Numeric) && suggestion[:confidence] > 1
          suggestion[:confidence] = suggestion[:confidence].to_f / 100.0
        end

        # Find the closest match if the category is not in the available categories
        if !available_categories.empty? && !available_categories.include?(suggestion[:category])
          original_category = suggestion[:category]
          suggestion[:category] = find_closest_match(original_category, available_categories)
          suggestion[:explanation] += " (Adjusted from '#{original_category}' to closest match '#{suggestion[:category]}')"
        end

        suggestion
      rescue JSON::ParserError
        { category: 'Expenses:Unknown', confidence: 0, explanation: 'Failed to parse AI response' }
      end
    end

    # Find the closest match for a category in the available categories
    # @param category [String] The category to find a match for
    # @param available_categories [Array<String>] A list of available categories
    # @return [String] The closest matching category
    def find_closest_match(category, available_categories)
      return category if available_categories.empty?

      # Find the category with the smallest Levenshtein distance
      closest_match = available_categories.min_by do |available_category|
        levenshtein_distance(category, available_category)
      end

      closest_match || category
    end

    # Calculate the Levenshtein distance between two strings
    # @param str1 [String] The first string
    # @param str2 [String] The second string
    # @return [Integer] The Levenshtein distance
    def levenshtein_distance(str1, str2)
      m = str1.length
      n = str2.length

      # Create a matrix of size (m+1) x (n+1)
      d = Array.new(m + 1) { Array.new(n + 1, 0) }

      # Initialize the first row and column
      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }

      # Fill in the rest of the matrix
      (1..m).each do |i|
        (1..n).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,      # deletion
            d[i][j - 1] + 1,      # insertion
            d[i - 1][j - 1] + cost, # substitution
          ].min
        end
      end

      # Return the distance
      d[m][n]
    end
  end
end
