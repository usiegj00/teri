require 'English'
require 'date'

module Teri
  # Handles report generation for balance sheets and income statements
  class ReportGenerator
    def initialize(options, logger)
      @options = options
      @logger = logger
    end

    def generate_balance_sheet(options = {})
      # Merge provided options with default options
      opts = @options.merge(options)

      # Get the specified year from options, defaulting to current year
      specified_year = opts[:year] || Date.today.year

      # Get the number of periods from options, defaulting to 2 if not specified
      periods = opts[:periods] || 2

      puts "Balance Sheet for #{specified_year}"
      if opts[:month]
        puts "Month: #{opts[:month]}"
      else
        puts "Including previous #{periods} years"
      end
      puts '=' * 50
      puts ''

      # Check if coding.ledger exists
      unless File.exist?('coding.ledger')
        puts "Warning: coding.ledger file does not exist. Please run 'teri code' first to process and code your transactions."
        puts 'Without coding, the balance sheet cannot be generated correctly.'
        return
      end

      # Common ledger options for consistent formatting
      ledger_options = '--exchange USD --no-total --collapse'

      # If a specific month is provided, show just that month
      if opts[:month]
        month = opts[:month].to_i
        end_date = Date.new(specified_year, month, -1) # Last day of the month

        puts "Balance Sheet as of #{end_date.strftime('%Y-%m-%d')}"
        puts '-' * 50

        cmd = 'ledger -f coding.ledger'
        Dir.glob('transactions/*.ledger').each do |file|
          cmd += " -f #{file}"
        end
        cmd += " balance #{ledger_options} --end #{end_date.strftime('%Y/%m/%d')} ^Assets ^Liabilities ^Equity"

        output = `#{cmd}`
        if $?.success?
          puts output

          # Check if the balance sheet is balanced
          if balance_sheet_unbalanced?(output)
            puts "Note: The balance sheet is not balanced. You may want to run 'teri fix-balance' to create adjustment entries."
          end
        else
          puts "Error generating balance sheet (exit code: #{$?.exitstatus})"
          puts "Command was: #{cmd}"
        end

        return
      end

      # Generate balance sheet for the specified year and previous periods
      start_year = specified_year - periods
      end_year = specified_year - 1

      # Show previous years
      (start_year..end_year).each do |year|
        puts "Balance Sheet as of #{year}-12-31"
        puts '-' * 50

        # Use the --file option to specify files instead of a glob pattern
        cmd = 'ledger -f coding.ledger'
        Dir.glob('transactions/*.ledger').each do |file|
          cmd += " -f #{file}"
        end
        cmd += " balance #{ledger_options} --end #{year}/12/31 ^Assets ^Liabilities ^Equity"

        output = `#{cmd}`
        if $?.success?
          puts output

          # Check if the balance sheet is balanced
          if balance_sheet_unbalanced?(output)
            puts "Note: The balance sheet is not balanced. You may want to run 'teri fix-balance' to create adjustment entries."
          end
        else
          puts "Error generating balance sheet (exit code: #{$?.exitstatus})"
          puts "Command was: #{cmd}"
        end
      end

      # Show current balance sheet for specified year
      current_date = Date.today
      if specified_year == current_date.year
        # If specified year is current year, show as of today
        puts "Balance Sheet as of #{current_date.strftime('%Y-%m-%d')}"
        end_date = current_date
      else
        # If specified year is not current year, show as of year end
        puts "Balance Sheet as of #{specified_year}-12-31"
        end_date = Date.new(specified_year, 12, 31)
      end
      puts '-' * 50

      cmd = 'ledger -f coding.ledger'
      Dir.glob('transactions/*.ledger').each do |file|
        cmd += " -f #{file}"
      end
      cmd += " balance #{ledger_options} --end #{end_date.strftime('%Y/%m/%d')} ^Assets ^Liabilities ^Equity"

      output = `#{cmd}`
      if $?.success?
        puts output

        # Check if the balance sheet is balanced
        if balance_sheet_unbalanced?(output)
          puts "Note: The balance sheet is not balanced. You may want to run 'teri fix-balance' to create adjustment entries."
        end
      else
        puts "Error generating balance sheet (exit code: #{$?.exitstatus})"
        puts "Command was: #{cmd}"
      end
    end

    # Helper method to check if a balance sheet is unbalanced
    def balance_sheet_unbalanced?(output)
      # With --no-total option, we need to calculate the total ourselves
      assets = 0.0
      liabilities = 0.0
      equity = 0.0

      # Extract amounts for each section
      output.each_line do |line|
        case line
        when /^\s*([\-\$\d,\.]+)\s+USD\s+Assets/
          assets_str = ::Regexp.last_match(1).gsub(/[\$,]/, '')
          assets = assets_str.to_f
        when /^\s*([\-\$\d,\.]+)\s+USD\s+Liabilities/
          liabilities_str = ::Regexp.last_match(1).gsub(/[\$,]/, '')
          liabilities = liabilities_str.to_f
        when /^\s*([\-\$\d,\.]+)\s+USD\s+Equity/
          equity_str = ::Regexp.last_match(1).gsub(/[\$,]/, '')
          equity = equity_str.to_f
        end
      end

      # Calculate the balance (Assets = Liabilities + Equity)
      balance = assets - (liabilities + equity)

      # Consider it balanced if the difference is less than 1 cent
      balance.abs > 0.01
    end

    def generate_income_statement(options = {})
      # Merge provided options with default options
      opts = @options.merge(options)

      # Get the specified year from options, defaulting to current year
      specified_year = opts[:year] || Date.today.year

      # Get the number of periods from options, defaulting to 2 if not specified
      periods = opts[:periods] || 2

      puts "Income Statement for #{specified_year}"
      if opts[:month]
        puts "Month: #{opts[:month]}"
      else
        puts "Including previous #{periods} years"
      end
      puts '=' * 50
      puts ''

      # Check if coding.ledger exists
      unless File.exist?('coding.ledger')
        puts "Warning: coding.ledger file does not exist. Please run 'teri code' first to process and code your transactions."
        puts 'Without coding, the income statement cannot be generated correctly.'
        return
      end

      # Common ledger options for consistent formatting
      ledger_options = '--exchange USD --no-total --collapse'

      # If a specific month is provided, show just that month
      if opts[:month]
        month = opts[:month].to_i
        start_date = Date.new(specified_year, month, 1)
        end_date = Date.new(specified_year, month, -1) # Last day of the month

        puts "Income Statement for #{start_date.strftime('%B %Y')}"
        puts '-' * 50

        cmd = 'ledger -f coding.ledger'
        Dir.glob('transactions/*.ledger').each do |file|
          cmd += " -f #{file}"
        end
        cmd += " balance #{ledger_options} --begin #{start_date.strftime('%Y/%m/%d')} --end #{end_date.strftime('%Y/%m/%d')} ^Income ^Expenses"

      else
        # Generate income statement for the specified year and previous periods
        start_year = specified_year - periods
        end_year = specified_year - 1

        # Show previous years
        (start_year..end_year).each do |year|
          puts "Income Statement for #{year}"
          puts '-' * 50

          cmd = 'ledger -f coding.ledger'
          Dir.glob('transactions/*.ledger').each do |file|
            cmd += " -f #{file}"
          end
          cmd += " balance #{ledger_options} --begin #{year}/01/01 --end #{year}/12/31 ^Income ^Expenses"

          output = `#{cmd}`
          if $?.success?
            puts output
          else
            puts "Error generating income statement (exit code: #{$?.exitstatus})"
            puts "Command was: #{cmd}"
          end
        end

        # Show current year income statement
        current_date = Date.today
        if specified_year == current_date.year
          # If specified year is current year, show as of today
          puts "Income Statement as of #{current_date.strftime('%Y-%m-%d')}"
        else
          # If specified year is not current year, show as of year end
          puts "Income Statement as of #{specified_year}-12-31"
        end

        cmd = 'ledger -f coding.ledger'
        Dir.glob('transactions/*.ledger').each do |file|
          cmd += " -f #{file}"
        end
        cmd += " balance #{ledger_options} --begin #{specified_year}/01/01 --end #{specified_year}/12/31 ^Income ^Expenses"
      end
      
      output = `#{cmd}`
      if $?.success?
        puts output
      else
        puts "Error generating income statement (exit code: #{$?.exitstatus})"
        puts "Command was: #{cmd}"
      end
    end
  end
end 