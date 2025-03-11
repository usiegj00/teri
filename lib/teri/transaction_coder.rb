module Teri
  # Handles transaction coding logic
  class TransactionCoder
    def initialize(category_manager, ai_integration, options, logger)
      @category_manager = category_manager
      @ai_integration = ai_integration
      @openai_client = ai_integration.openai_client
      @options = options
      @logger = logger
    end

    # Core transaction coding logic without I/O operations
    def code_transaction(transaction, selected_option, split_input = nil, new_category = nil)
      # Check if the transaction has an unknown category
      unknown_categories = ['Income:Unknown', 'Expenses:Unknown']

      # Find entries with unknown categories
      unknown_entry = transaction.entries.find do |entry|
        unknown_categories.include?(entry.account)
      end

      raise "Transaction has no unknown category: #{transaction}" unless unknown_entry

      # Initialize new_categories
      new_categories = {}

      # Process the selected option
      case selected_option.to_i
      when 1
        # Split transaction between multiple categories
        if split_input && !split_input.empty?
          # Parse the split input
          split_input.split(',').each do |part|
            # Handle the format "Category:Amount" or just "Category"
            if part.include?(':')
              parts = part.split(':')
              if parts.length >= 3
                # Format is Category:Subcategory:Amount
                category = "#{parts[0]}:#{parts[1]}"
                amount = parts[2].to_f
              else
                # Format is Category:Amount
                category = parts[0]
                amount = parts[1].to_f
              end
              new_categories[category] = amount
            else
              # Just a category with no amount specified
              new_categories[part] = unknown_entry.amount
            end
          end
        else
          puts 'Please enter the split categories and amounts (e.g. Expenses:Rent:500,Expenses:Utilities:250):'
          split_input = gets.chomp
          return code_transaction(transaction, selected_option, split_input)
        end
      when 2
        # Enter a custom category
        if new_category && !new_category.empty?
          new_categories[new_category] = unknown_entry.amount
        else
          puts 'Please enter the new category:'
          new_category = gets.chomp
          return code_transaction(transaction, selected_option, nil, new_category)
        end
      when 3..999
        # Use a predefined category
        category_index = selected_option.to_i - 3
        all_cats = @category_manager.all_categories
        if category_index < all_cats.size
          category = all_cats[category_index]
          new_categories[category] = unknown_entry.amount
        else
          puts 'Invalid category index. Please try again.'
          return nil
        end
      else
        puts 'Invalid option. Please try again.'
        return nil
      end

      # Create a reverse transaction with the new categories
      transaction.create_reverse_transaction(new_categories)
    end

    # Get AI suggestion for a transaction
    def get_ai_suggestion(transaction, io = nil)
      return nil unless @openai_client && @options[:use_ai_suggestions]

      begin
        io&.puts 'Getting AI suggestion...'
        @logger&.info('Requesting AI suggestion')

        ai_suggestion = @ai_integration.suggest_category(
          transaction,
          @category_manager.all_categories
        )

        if ai_suggestion[:category]
          # Find the option number for the AI suggested category
          all_cats = @category_manager.all_categories
          ai_option_index = all_cats.find_index(ai_suggestion[:category])
          ai_option_number = ai_option_index ? ai_option_index + 3 : nil

          @logger&.info("AI suggestion: #{ai_suggestion[:category]} (Confidence: #{(ai_suggestion[:confidence] * 100).round(1)}%)")
          @logger&.info("AI explanation: #{ai_suggestion[:explanation]}")

          io&.puts "AI Suggestion: #{ai_suggestion[:category]} (Confidence: #{(ai_suggestion[:confidence] * 100).round(1)}%)"
          io&.puts "Explanation: #{ai_suggestion[:explanation]}"
          io&.puts ''

          return {
            suggestion: ai_suggestion,
            option_number: ai_option_number
          }
        else
          @logger&.warn('AI did not provide a category suggestion')
          return nil
        end
      rescue StandardError => e
        @logger&.error("Error getting AI suggestion: #{e.message}")
        io&.puts "Error getting AI suggestion: #{e.message}"
        return nil
      end
    end

    # Save a transaction to coding.ledger
    def save_transaction(reverse_transaction, transaction, selected_option, feedback = nil)
      return false unless reverse_transaction

      # Add the feedback as a comment to the reverse transaction
      if feedback && !feedback.empty? && reverse_transaction.respond_to?(:add_comment)
        reverse_transaction.add_comment("Hint: #{feedback}")
      end

      # Append to coding.ledger
      File.open('coding.ledger', 'a') do |file|
        file.puts reverse_transaction.to_ledger
      end

      @logger&.info('Transaction coded and saved to coding.ledger')

      # Update previous codings cache with this transaction
      if @openai_client && selected_option.to_i >= 3
        category_index = selected_option.to_i - 3
        all_cats = @category_manager.all_categories
        if category_index < all_cats.size
          selected_category = all_cats[category_index]
          # Store more information about the transaction
          @ai_integration.update_previous_codings(
            transaction.description,
            selected_category,
            transaction.counterparty,
            feedback ? [feedback] : transaction.hints
          )
          @logger&.info("Updated previous codings cache with: #{transaction.description} => #{selected_category} (Counterparty: #{transaction.counterparty})")
        end
      end

      true
    end

    def code_transaction_interactively(transaction, responses = nil, saved_responses = nil, auto_apply_ai = false, io)
      # Display the transaction information to the user
      io.puts transaction.to_s
      io.puts ''

      @logger&.info("Transaction details: #{transaction.to_s.gsub("\n", ' | ')}")

      # Get AI suggestion if available
      ai_result = get_ai_suggestion(transaction, io)
      ai_suggestion = ai_result&.dig(:suggestion)
      ai_option_number = ai_result&.dig(:option_number)

      # Display the available options to the user
      all_cats = @category_manager.all_categories

      io.puts 'Available options:'
      io.puts '1. Split transaction between multiple categories'
      io.puts '2. Create new category'

      all_cats.each_with_index do |category, index|
        option_number = index + 3
        ai_indicator = option_number == ai_option_number ? ' (AI Suggested)' : ''
        io.puts "#{option_number}. #{category}#{ai_indicator}"
      end

      if @options[:use_ai_suggestions] && !auto_apply_ai
        io.puts 'A. Auto-apply AI suggestions for all remaining transactions'
      end

      # Get the user's selection
      selected_option = nil

      if auto_apply_ai && ai_option_number
        selected_option = ai_option_number
        io.puts "Auto-applying AI suggestion: #{ai_suggestion[:category]}"
      elsif responses && !responses.empty?
        # Use the next saved response
        selected_option = responses.shift
        io.puts "Using saved response: #{selected_option}"
      else
        # Prompt the user for input
        io.print "Select option (1-#{all_cats.size + 2})"
        io.print "[#{ai_option_number}]" if @options[:use_ai_suggestions] && !auto_apply_ai && ai_option_number
        io.print ': '

        user_input = io.gets.chomp

        # Save the response if requested
        saved_responses << user_input if saved_responses

        # Check if the user wants to auto-apply AI suggestions
        if user_input.downcase == 'a' && @options[:use_ai_suggestions] && !auto_apply_ai
          return 'A' # Return 'A' for backward compatibility with tests
        end

        selected_option = user_input.to_i
      end

      # Process the user's selection
      if selected_option == 1
        # Split transaction between multiple categories
        io.print 'Enter categories and amounts (category1:amount1,category2:amount2,...): '
        split_input = nil

        if responses && !responses.empty?
          split_input = responses.shift
          io.puts "Using saved response: #{split_input}"
        else
          split_input = io.gets.chomp
          saved_responses << split_input if saved_responses
        end

        reverse_transaction = code_transaction(transaction, selected_option, split_input)
      elsif selected_option == 2
        # Create new category
        io.print 'Enter new category: '
        new_category = nil

        if responses && !responses.empty?
          new_category = responses.shift
          io.puts "Using saved response: #{new_category}"
        else
          new_category = io.gets.chomp
          saved_responses << new_category if saved_responses
        end

        reverse_transaction = code_transaction(transaction, selected_option, nil, new_category)
      elsif selected_option >= 3 && selected_option <= all_cats.size + 2
        # Select an existing category
        category = all_cats[selected_option - 3]

        # If this was an AI suggestion and the user selected it, ask for feedback if it was wrong
        feedback = nil
        if ai_suggestion && selected_option != ai_option_number
          io.print 'Provide a reason why the AI was wrong: '

          if responses && !responses.empty?
            feedback = responses.shift
            io.puts "Using saved response: #{feedback}"
          else
            feedback = io.gets.chomp
            saved_responses << feedback if saved_responses
          end

          # Add the feedback as a hint to the transaction
          transaction.add_hint(feedback) if feedback && !feedback.empty?
        end

        reverse_transaction = code_transaction(transaction, selected_option, nil, nil)

        # Save the transaction
        save_transaction(reverse_transaction, transaction, selected_option, feedback)
      else
        io.puts 'Invalid option. Please try again.'
        return code_transaction_interactively(transaction, responses, saved_responses, auto_apply_ai, io)
      end

      # Append to coding.ledger
      if reverse_transaction
        save_transaction(reverse_transaction, transaction, selected_option)
        io.puts 'Transaction coded and saved to coding.ledger.'
      else
        @logger&.error('Failed to code transaction')
        io.puts 'Failed to code transaction.'
      end

      io.puts ''

      # Return the selected option for backward compatibility with tests
      selected_option.is_a?(Integer) ? selected_option.to_s : selected_option
    end

    def process_reconcile_file(uncoded_transactions, reconcile_file)
      # Read the reconciliation file
      reconcile_data = File.readlines(reconcile_file).map(&:strip)

      # Process each line in the reconciliation file
      reconcile_data.each do |line|
        next if line.empty? || line.start_with?('#')

        # Parse the line
        parts = line.split(',')
        transaction_id = parts[0].strip
        category = parts[1].strip

        # Find the transaction
        transaction = uncoded_transactions.find { |t| t.transaction_id == transaction_id }
        next unless transaction

        # Check if the transaction has an unknown category
        unknown_categories = ['Income:Unknown', 'Expenses:Unknown']
        unknown_category = unknown_categories.find do |cat|
          transaction.from_account == cat || transaction.to_account == cat
        end
        next unless unknown_category

        # Create the categories hash with a single category
        new_categories = { category => transaction.amount }

        # Create the reverse transaction
        begin
          reverse_transaction = transaction.create_reverse_transaction(new_categories)

          # Append to coding.ledger
          File.open('coding.ledger', 'a') do |file|
            file.puts reverse_transaction.to_ledger
          end

          puts "Coded transaction #{transaction_id} with category #{category}"
        rescue StandardError => e
          puts "Error coding transaction #{transaction_id}: #{e.message}"
        end
      end
    end
  end
end 