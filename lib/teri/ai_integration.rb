module Teri
  # Handles AI integration with OpenAI
  class AIIntegration
    attr_reader :openai_client, :previous_codings, :counterparty_hints

    def initialize(options, logger, log_file)
      @options = options
      @logger = logger
      @log_file = log_file
      @previous_codings = {}
      @counterparty_hints = {}

      # Initialize OpenAI client if API key is provided
      if @options[:use_ai_suggestions] && (@options[:openai_api_key] || ENV.fetch('OPENAI_API_KEY', nil))
        begin
          @openai_client = OpenAIClient.new(api_key: @options[:openai_api_key], log_file: @log_file)
          @logger&.info('OpenAI client initialized')
        rescue StandardError => e
          @logger&.error("Failed to initialize OpenAI client: #{e.message}")
          puts "Warning: Failed to initialize OpenAI client: #{e.message}"
          @openai_client = nil
        end
      end
    end

    # Delegate suggest_category to OpenAI client
    def suggest_category(transaction, available_categories)
      return nil unless @openai_client

      # Make self respond to previous_codings and counterparty_hints
      @openai_client.suggest_category(transaction, self)
    end

    # Update previous codings with a new transaction
    def update_previous_codings(description, category, counterparty, hints)
      # Store by description for backward compatibility with tests
      @previous_codings[description] = {
        category: category,
        counterparty: counterparty,
        hints: hints,
      }

      # Also store by counterparty for the new functionality
      return unless counterparty

      @previous_codings[:by_counterparty] ||= {}
      @previous_codings[:by_counterparty][counterparty] ||= {
        transactions: [],
        hints: @counterparty_hints[counterparty] || [],
      }

      @previous_codings[:by_counterparty][counterparty][:transactions] << {
        description: description,
        category: category,
      }

      # Store hints by counterparty
      if counterparty && !hints.empty?
        @counterparty_hints[counterparty] ||= []
        @counterparty_hints[counterparty].concat(hints)
      end
    end

    # Load previous codings from coding.ledger for AI suggestions
    def load_previous_codings(file_adapter)
      @previous_codings = {}
      @counterparty_hints = {}

      # Check if coding.ledger exists
      return unless file_adapter.exist?('coding.ledger')

      # Parse coding.ledger to extract transaction descriptions and categories
      begin
        ledger = Ledger.parse('coding.ledger', file_adapter)

        # Process each transaction
        ledger.transactions.each do |transaction|
          next unless transaction[:description] && transaction[:entries] && !transaction[:entries].empty?

          # Find entries that are not Assets or Liabilities (likely the categorization)
          categorization_entries = transaction[:entries].reject do |entry|
            entry[:account].start_with?('Assets:', 'Liabilities:')
          end

          # Use the first categorization entry as the category
          next if categorization_entries.empty?

          counterparty = transaction[:counterparty]

          # Get hints if available
          hints = transaction[:metadata]&.select { |m| m[:key] == 'Hint' }&.map { |m| m[:value] } || []

          # Update previous codings with this transaction
          update_previous_codings(
            transaction[:description],
            categorization_entries.first[:account],
            counterparty,
            hints
          )
        end

        @logger&.info("Loaded #{@previous_codings.size - (@previous_codings[:by_counterparty] ? 1 : 0)} previous codings with hints for #{@counterparty_hints.size} counterparties")
      rescue StandardError => e
        @logger&.error("Failed to load previous codings: #{e.message}")
        file_adapter.warning("Failed to load previous codings: #{e.message}") if file_adapter.respond_to?(:warning)
      end
    end
  end
end 