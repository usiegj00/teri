require 'English'
require 'date'
require 'fileutils'
require 'securerandom'
require 'logger'
require_relative 'openai_client'
require_relative 'category_manager'
require_relative 'transaction_coder'
require_relative 'report_generator'
require_relative 'ai_integration'

module Teri
  # IO adapter for handling input/output operations
  # This allows for better testing by injecting a test adapter
  class IOAdapter
    def puts(message)
      Kernel.puts message
    end

    def print(message)
      Kernel.print message
    end

    def gets
      $stdin.gets
    end
  end

  # File adapter for handling file operations
  # This allows for better testing by injecting a test adapter
  class FileAdapter
    def exist?(path)
      File.exist?(path)
    end

    def read(path)
      File.read(path)
    end

    def readlines(path)
      File.readlines(path)
    end

    def open(path, mode, &)
      File.open(path, mode, &)
    end

    def warning(message)
      puts "Warning: #{message}"
    end
  end

  class Accounting
    attr_reader :transactions, :coded_transactions, :options, :logger, :previous_codings, :counterparty_hints

    def initialize(options = {})
      @transactions = []
      @coded_transactions = {}
      
      # Convert string keys to symbol keys
      symbolized_options = {}
      options.each do |key, value|
        symbolized_options[key.to_sym] = value
      end
      
      @options = {
        year: Date.today.year,
        month: nil,
        periods: 2, # Default to 2 previous periods
        response_file: nil, # Add option for response file
        save_responses_file: nil, # Add option for saving responses
        adjustment_asset_account: nil, # Add option for adjustment asset account
        adjustment_equity_account: nil, # Add option for adjustment equity account
        openai_api_key: ENV.fetch('OPENAI_API_KEY', nil), # Add option for OpenAI API key
        use_ai_suggestions: true, # Add option to enable/disable AI suggestions
        auto_apply_ai: false, # Add option to auto-apply AI suggestions
        log_file: nil,
      }.merge(symbolized_options)
      
      # Set up logging
      setup_logger

      # Initialize IO and File adapters
      @io = IOAdapter.new
      @file = FileAdapter.new

      # Initialize category manager
      @category_manager = CategoryManager.new

      # Initialize AI integration
      @ai_integration = AIIntegration.new(@options, @logger, @log_file)
      @openai_client = @ai_integration.openai_client

      # Initialize transaction coder
      @transaction_coder = TransactionCoder.new(@category_manager, @ai_integration, @options, @logger)

      # Initialize report generator
      @report_generator = ReportGenerator.new(@options, @logger)

      # Initialize previous codings cache
      @previous_codings = {}
      @counterparty_hints = {}

      # Load previous codings if we have an OpenAI client and a file
      load_previous_codings(@file) if @openai_client && @file
    end

    # Set up the logger
    def setup_logger
      # Skip logger setup if we're in a test environment
      if defined?(RSpec)
        @logger = nil
        return
      end

      begin
        # Create logs directory if it doesn't exist
        FileUtils.mkdir_p('logs')

        # Create a log file with timestamp
        @log_file = "logs/coding_session_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log"

        @logger = Logger.new(@log_file)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, _progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
        end

        @logger.info('Coding session started')
        @logger.info("Options: #{@options.inspect}")
      rescue StandardError => e
        puts "Warning: Failed to set up logging: #{e.message}"
        @logger = nil
      end
    end

    def load_transactions(filelist: Dir.glob('transactions/*.ledger'))
      # Clear existing transactions
      @transactions = []
      
      # Load all transactions from ledger files
      filelist.each do |file|
        ledger = Ledger.parse(file)
        file_transactions = ledger.transactions.map { |hash| Transaction.from_ledger_hash(hash) }
        @transactions.concat(file_transactions)
      end
    end

    def load_coded_transactions
      # Initialize the coded transactions hash
      @coded_transactions = {}
      
      # Check if coding.ledger exists
      return unless File.exist?('coding.ledger')
      
      # Use Ledger.parse to read the coding.ledger file
      Ledger.parse('coding.ledger').transactions.each do |transaction|
        @coded_transactions[transaction[:transaction_id]] = true
      end

      # Also check for transaction IDs directly in the file content
      # This is a fallback in case the Ledger.parse method doesn't capture all transaction IDs
      begin
        coding_ledger_content = File.read('coding.ledger')
        # Look for transaction IDs in comments (e.g., "; Original Transaction ID: 1234-5678")
        coding_ledger_content.scan(/;\s*(?:Original\s+)?Transaction\s+ID:?\s*([a-zA-Z0-9-]+)/).each do |match|
          @coded_transactions[match[0]] = true
        end

        # Also look for transaction IDs in the transaction headers
        # Format: YYYY-MM-DD * Transaction Description ; Transaction ID: 1234-5678
        coding_ledger_content.scan(/\d{4}-\d{2}-\d{2}.*?;\s*(?:Transaction\s+ID:?\s*|ID:?\s*)([a-zA-Z0-9-]+)/).each do |match|
          @coded_transactions[match[0]] = true
        end
      rescue StandardError => e
        @logger&.error("Error reading coding.ledger file: #{e.message}")
        puts "Warning: Error reading coding.ledger file: #{e.message}"
      end

      @logger&.info("Loaded #{@coded_transactions.size} coded transactions")
      @coded_transactions
    end

    def code_transactions
      load_transactions

      # Get uncoded transactions
      uncoded_transactions = @transactions.select do |transaction|
        transaction.entries.any? { |entry| entry.account.include?('Unknown') }
      end

      if uncoded_transactions.empty?
        puts 'No uncoded transactions found.'
        return
      end

      # Check if we should use a reconciliation file
      return process_reconcile_file(uncoded_transactions) if @options[:reconcile_file]

      # Initialize variables for responses
      responses = nil
        saved_responses = nil
        
      # Check if we should use saved responses
      if @options[:responses_file]
        if File.exist?(@options[:responses_file])
          @logger&.info("Using responses from file: #{@options[:responses_file]}")
          puts "Using responses from file: #{@options[:responses_file]}"
          responses = File.readlines(@options[:responses_file]).map(&:strip)
        else
          @logger&.error("Responses file not found: #{@options[:responses_file]}")
          puts "Error: Responses file not found: #{@options[:responses_file]}"
          return
        end
      end
      
      # Check if we should save responses
      if @options[:save_responses_file]
        @logger&.info("Saving responses to file: #{@options[:save_responses_file]}")
        puts "Saving responses to file: #{@options[:save_responses_file]}"
        saved_responses = []
      end

      # Load previous codings for AI suggestions
      load_previous_codings(@file) if @openai_client

      # Code each transaction
      uncoded_transactions.each do |transaction|
        @logger&.info("Coding transaction: #{transaction.transaction_id} - #{transaction.description}")

        # Code the transaction interactively
        result = @transaction_coder.code_transaction_interactively(
          transaction, 
          responses, 
          saved_responses, 
          @options[:auto_apply_ai],
          @io
        )

        # Check if the user wants to auto-apply AI suggestions
        if result == 'A'
          @logger&.info('User selected auto-apply AI suggestions')
          @options[:auto_apply_ai] = true
        end
      end
      
      # Save responses if requested
      return unless @options[:save_responses_file] && saved_responses

      @logger&.info("Writing #{saved_responses.size} responses to file: #{@options[:save_responses_file]}")
      File.write(@options[:save_responses_file], saved_responses.join("\n"))
      puts "Responses saved to: #{@options[:save_responses_file]}"
    end

    def process_reconcile_file(uncoded_transactions)
      @transaction_coder.process_reconcile_file(uncoded_transactions, @options[:reconcile_file])
    end

    def check_uncoded_transactions
      # Load transactions from ledger files
      load_transactions
      
      # Load previously coded transactions
      load_coded_transactions
      
      # Find uncoded transactions
      @transactions.reject { |t| @coded_transactions[t.transaction_id] }
    end

    def generate_balance_sheet(options = {})
      @report_generator.generate_balance_sheet(options)
    end

    def generate_income_statement(options = {})
      @report_generator.generate_income_statement(options)
    end

    def all_categories
      @category_manager.all_categories
    end

    # Load previous codings from coding.ledger for AI suggestions
    def load_previous_codings(file_adapter = @file)
      # Delegate to AI integration
      @ai_integration.load_previous_codings(file_adapter)
      
      # Update our local references to the data
      @previous_codings = @ai_integration.previous_codings
      @counterparty_hints = @ai_integration.counterparty_hints
    end

    # Expose previous codings for OpenAI client
    def previous_codings
      @previous_codings
    end

    # Expose counterparty hints for OpenAI client
    def counterparty_hints
      @counterparty_hints
    end

    def code_transaction(transaction, selected_option, split_input = nil, new_category = nil)
      @transaction_coder.code_transaction(transaction, selected_option, split_input, new_category)
    end

    def code_transaction_interactively(transaction, responses = nil, saved_responses = nil, auto_apply_ai = false, io = @io)
      @transaction_coder.code_transaction_interactively(transaction, responses, saved_responses, auto_apply_ai, io)
    end
  end
end 
