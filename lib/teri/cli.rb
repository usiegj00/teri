require 'thor'
require 'date'

module Teri
  class CLI < Thor
    class_option :verbose, type: :boolean, aliases: '-v', desc: 'Enable verbose output'

    desc 'code', 'Process new transactions and code them'
    option :reconcile_file, type: :string, aliases: '-f', desc: 'Read reconciliation instructions from FILE'
    option :response_file, type: :string, aliases: '-r', desc: 'Read interactive coding responses from FILE'
    option :save_responses_file, type: :string, aliases: '-s', desc: 'Save interactive coding responses to FILE'
    option :openai_api_key, type: :string, aliases: '-k', desc: 'OpenAI API key (defaults to OPENAI_API_KEY env var)'
    option :disable_ai, type: :boolean, aliases: '-d', desc: 'Disable AI suggestions'
    option :auto_apply_ai, type: :boolean, aliases: '-a', desc: 'Auto-apply AI suggestions'
    def code
      # Process options
      options_hash = options.dup

      # Convert disable_ai to use_ai_suggestions
      options_hash[:use_ai_suggestions] = !options_hash.delete(:disable_ai) if options_hash.key?(:disable_ai)

      accounting = Accounting.new(options_hash)
      accounting.code_transactions
    end

    desc 'check-uncoded', 'Check for uncoded transactions'
    def check_uncoded
      accounting = Accounting.new(options)
      accounting.check_uncoded_transactions
    end

    desc 'balance-sheet', 'Generate a balance sheet report'
    option :year, type: :numeric, aliases: '-y', desc: 'Year for reports (default: current year)'
    option :month, type: :numeric, aliases: '-m', desc: 'Month for reports (1-12)'
    option :periods, type: :numeric, aliases: '-p',
                     desc: 'Number of previous periods (years) to include in reports (default: 2)'
    def balance_sheet
      accounting = Accounting.new(options)
      accounting.generate_balance_sheet
    end

    desc 'income-statement', 'Generate an income statement report'
    option :year, type: :numeric, aliases: '-y', desc: 'Year for reports (default: current year)'
    option :month, type: :numeric, aliases: '-m', desc: 'Month for reports (1-12)'
    option :periods, type: :numeric, aliases: '-p',
                     desc: 'Number of previous periods (years) to include in reports (default: 2)'
    def income_statement
      accounting = Accounting.new(options)
      accounting.generate_income_statement
    end

    desc 'close-year', 'Close the books for a specific year'
    option :year, type: :numeric, aliases: '-y', desc: 'Year to close (default: previous year)'
    def close_year
      year = options[:year] || (Date.today.year - 1)
      accounting = Accounting.new(options)
      accounting.close_year(year)
    end

    desc 'fix-balance', 'Fix the balance sheet'
    def fix_balance
      accounting = Accounting.new(options)
      accounting.fix_balance
    end

    desc 'version', 'Display version information'
    def version
      puts "Teri version #{Teri::VERSION}"
    end
  end
end
