module Teri
  # Represents a single entry (debit or credit) in a transaction
  class Entry
    attr_reader :account, :amount, :currency, :type

    # Initialize a new entry
    # @param account [String] The account name
    # @param amount [Float] The amount (positive value)
    # @param currency [String] The currency code
    # @param type [Symbol] Either :debit or :credit
    def initialize(account:, amount:, type:, currency: 'USD')
      @account = account
      @amount = amount.abs # Always store as positive
      @currency = normalize_currency(currency)
      @type = type.to_sym

      raise ArgumentError, 'Type must be :debit or :credit' unless [:debit, :credit].include?(@type)
      raise ArgumentError, 'Amount must be positive' unless @amount.positive?
    end

    # Normalize currency to ensure consistent representation
    # @param currency [String] The currency string to normalize
    # @return [String] The normalized currency string
    def normalize_currency(currency)
      return 'USD' if currency == '$' || currency.to_s.strip.upcase == 'USD'

      currency.to_s.strip.upcase
    end

    # Get the signed amount (positive for debits, negative for credits)
    # @return [Float] The signed amount
    def signed_amount
      @type == :debit ? @amount : -@amount
    end

    # Convert the entry to a ledger format string
    # @return [String] The entry in ledger format
    def to_ledger
      # Always format as $ for consistency with source transactions
      "    #{@account}  $#{signed_amount}"
    end
  end

  class Transaction
    attr_accessor :date, :description, :transaction_id, :status, :counterparty, :memo, :timestamp, :currency,
                  :source_info
    attr_reader :entries, :comments, :hints

    def initialize(date:, description:, transaction_id: nil, status: nil, counterparty: nil, memo: nil, timestamp: nil,
                   currency: 'USD', source_info: nil)
      @date = date
      @description = description
      @transaction_id = transaction_id || SecureRandom.uuid
      @status = status
      @counterparty = counterparty
      @memo = memo
      @timestamp = timestamp
      @currency = self.class.normalize_currency(currency)
      @source_info = source_info
      @entries = []
      @comments = []
      @hints = []
    end

    # Add an entry to the transaction
    # @param account [String] The account name
    # @param amount [Float] The amount (positive value)
    # @param type [Symbol] Either :debit or :credit
    # @return [Entry] The created entry
    def add_entry(account:, amount:, type:)
      entry = Entry.new(
        account: account,
        amount: amount,
        currency: @currency,
        type: type
      )
      @entries << entry
      entry
    end

    # Add a debit entry
    # @param account [String] The account name
    # @param amount [Float] The amount (positive value)
    # @return [Entry] The created entry
    def add_debit(account:, amount:)
      add_entry(account: account, amount: amount, type: :debit)
    end

    # Add a credit entry
    # @param account [String] The account name
    # @param amount [Float] The amount (positive value)
    # @return [Entry] The created entry
    def add_credit(account:, amount:)
      add_entry(account: account, amount: amount, type: :credit)
    end

    # Add a comment to the transaction
    # @param comment [String] The comment to add
    # @return [Array<String>] The updated comments array
    def add_comment(comment)
      @comments << comment
      @comments
    end

    # Add a hint for AI suggestions
    # @param hint [String] The hint to add
    # @return [Array<String>] The updated hints array
    def add_hint(hint)
      @hints << hint
      @hints
    end

    # Check if the transaction is balanced (sum of debits equals sum of credits)
    # @return [Boolean] True if balanced, false otherwise
    def balanced?
      total_debits = @entries.select { |e| e.type == :debit }.sum(&:amount)
      total_credits = @entries.select { |e| e.type == :credit }.sum(&:amount)

      (total_debits - total_credits).abs < 0.001 # Allow for small floating point differences
    end

    # Validate the transaction and return any warnings
    # @return [Array<String>] Array of warning messages
    def validate
      warnings = []

      # Check if transaction has entries
      if @entries.empty?
        warnings << 'Transaction has no entries'
        return warnings
      end

      # Check if transaction is balanced
      unless balanced?
        total_debits = @entries.select { |e| e.type == :debit }.sum(&:amount)
        total_credits = @entries.select { |e| e.type == :credit }.sum(&:amount)
        warnings << "Transaction is not balanced: debits (#{total_debits}) != credits (#{total_credits})"
      end

      # Check if transaction has at least one debit and one credit
      warnings << 'Transaction has no debits' if @entries.none? { |e| e.type == :debit }

      warnings << 'Transaction has no credits' if @entries.none? { |e| e.type == :credit }

      warnings
    end

    # Check if the transaction is valid
    # @return [Boolean] True if valid, false otherwise
    def valid?
      validate.empty?
    end

    def to_s
      # Build source info string if available
      source_info_str = ''
      if @source_info && @source_info[:file]
        line_info = ''
        if @source_info[:start_line] && @source_info[:end_line]
          line_info = "##{@source_info[:start_line]}-#{@source_info[:end_line]}"
        end
        source_info_str = "Importing: #{@source_info[:file]}#{line_info}"
      end

      status_info = @status ? " [#{@status}]" : ''

      # Build the output
      output = []
      output << source_info_str unless source_info_str.empty?
      output << "Transaction: #{@transaction_id}#{status_info}"
      output << "Date: #{@date}"
      output << "Description: #{@description}" if @description

      # Add entries
      output << 'Entries:'
      @entries.each do |entry|
        output << "  #{entry.type.to_s.capitalize}: #{entry.account} #{entry.amount} #{entry.currency}"
      end

      output << "Counterparty: #{@counterparty}" if @counterparty

      # Add validation warnings if any
      warnings = validate
      unless warnings.empty?
        output << 'Warnings:'
        warnings.each do |warning|
          output << "  #{warning}"
        end
      end

      # Add hints if available
      if @hints && !@hints.empty?
        output << 'Hints:'
        @hints.each do |hint|
          output << "  - #{hint}"
        end
      end

      output.join("\n")
    end

    # Format transaction for ledger file
    def to_ledger
      # Ensure the transaction is balanced before writing to ledger
      unless balanced?
        warnings = validate
        raise "Cannot write unbalanced transaction to ledger: #{warnings.join(', ')}"
      end

      output = "#{@date.strftime('%Y/%m/%d')} #{@description}\n"
      output += "    ; Transaction ID: #{@transaction_id}\n" if @transaction_id
      output += "    ; Status: #{@status}\n" if @status
      output += "    ; Counterparty: #{@counterparty}\n" if @counterparty
      output += "    ; Memo: #{@memo}\n" if @memo
      output += "    ; Timestamp: #{@timestamp}\n" if @timestamp

      # Add entries
      @entries.each do |entry|
        output += "#{entry.to_ledger}\n"
      end

      # Add custom comments
      @comments.each do |comment|
        output += "    ; #{comment}\n"
      end

      output
    end

    # Create a reverse transaction (for recoding)
    # @param new_categories [Hash] A hash of new categories to use
    # @return [Transaction] The reverse transaction
    def create_reverse_transaction(new_categories = nil)
      # Create a new transaction with the same metadata
      reverse_transaction = Transaction.new(
        date: @date,
        description: "Reversal: #{@description}",
        transaction_id: "rev-#{@transaction_id}",
        status: @status,
        counterparty: @counterparty,
        memo: "Reversal of transaction #{@transaction_id}",
        timestamp: @timestamp,
        currency: @currency,
        source_info: @source_info
      )

      # Add the original transaction ID as a comment for easier identification
      reverse_transaction.add_comment("Original Transaction ID: #{@transaction_id}")

      # Copy any hints to the reverse transaction
      @hints.each do |hint|
        reverse_transaction.add_hint(hint)
      end

      # If no new categories are provided, just reverse all entries
      if new_categories.nil? || new_categories.empty?
        @entries.each do |entry|
          if entry.type == :debit
            reverse_transaction.add_credit(account: entry.account, amount: entry.amount)
          else
            reverse_transaction.add_debit(account: entry.account, amount: entry.amount)
          end
        end
        return reverse_transaction
      end

      # Find the unknown entry to replace
      unknown_categories = ['Income:Unknown', 'Expenses:Unknown']
      unknown_entry = @entries.find { |e| unknown_categories.include?(e.account) }

      # If there's no unknown entry, raise an error
      raise 'Cannot recategorize transaction without an Unknown category' unless unknown_entry

      # Calculate the total amount from the new categories
      total_amount = new_categories.values.sum { |v| v.is_a?(String) ? Transaction.parse_amount(v) : v }

      # Ensure the total amount matches the Unknown entry amount
      if (total_amount - unknown_entry.amount).abs > 0.001
        raise "Total amount of new categories (#{total_amount}) does not match the Unknown entry amount (#{unknown_entry.amount})"
      end

      # Add the new categories with the same type as the Unknown entry
      new_categories.each do |category, amount|
        amount_value = amount.is_a?(String) ? Transaction.parse_amount(amount) : amount
        if unknown_entry.type == :debit
          reverse_transaction.add_debit(account: category, amount: amount_value)
        else
          reverse_transaction.add_credit(account: category, amount: amount_value)
        end
      end

      # Add a balancing entry for the Unknown entry (reversed)
      if unknown_entry.type == :debit
        reverse_transaction.add_credit(account: unknown_entry.account, amount: total_amount)
      else
        reverse_transaction.add_debit(account: unknown_entry.account, amount: total_amount)
      end

      reverse_transaction
    end

    # Create a Transaction from a ledger hash
    # @param hash [Hash] Hash with transaction details
    # @return [Transaction] Transaction object
    def self.from_ledger_hash(hash)
      # Extract the required fields
      date = hash[:date]
      description = hash[:description]

      # Extract the optional fields
      transaction_id = hash[:transaction_id]
      status = hash[:status]
      counterparty = hash[:counterparty]
      memo = hash[:memo]
      timestamp = hash[:timestamp]
      currency = normalize_currency(hash[:currency] || 'USD')
      source_info = hash[:source_info]

      # Create a new Transaction
      transaction = new(
        date: date,
        description: description,
        transaction_id: transaction_id,
        status: status,
        counterparty: counterparty,
        memo: memo,
        timestamp: timestamp,
        currency: currency,
        source_info: source_info
      )

      # Add entries
      if hash[:entries]
        hash[:entries].each do |entry|
          transaction.add_entry(
            account: entry[:account],
            amount: entry[:amount],
            type: entry[:type]
          )
        end
      elsif hash[:from_account] && hash[:to_account] && hash[:amount]
        # Legacy format
        amount = hash[:amount]
        from_account = hash[:from_account]
        to_account = hash[:to_account]

        # Convert to new format
        amount_value = amount.is_a?(String) ? parse_amount(amount) : amount

        if amount_value.negative?
          # Handle negative amounts
          transaction.add_credit(account: from_account, amount: amount_value.abs)
          transaction.add_debit(account: to_account, amount: amount_value.abs)
        else
          # Use the traditional approach
          transaction.add_debit(account: to_account, amount: amount_value)
          transaction.add_credit(account: from_account, amount: amount_value)
        end
      end

      transaction
    end

    # Normalize currency to ensure consistent representation (class method)
    # @param currency [String] The currency string to normalize
    # @return [String] The normalized currency string
    def self.normalize_currency(currency)
      return 'USD' if currency == '$' || currency.to_s.strip.upcase == 'USD'

      currency.to_s.strip.upcase
    end

    # Parse an amount string into a float
    # @param amount_str [String] The amount string to parse
    # @return [Float] The parsed amount
    def self.parse_amount(amount_str)
      return amount_str.to_f unless amount_str.is_a?(String)

      # Extract the actual amount value from strings like "Checking ••1090  $10000.00" or "Income:Unknown  -10000.00 USD"
      case amount_str
      when /\$[\-\d,\.]+/
        # Handle $ format
        clean_amount = amount_str.match(/\$[\-\d,\.]+/)[0]
        clean_amount.gsub(/[\$,]/, '').to_f
      when /([\-\d,\.]+)\s+[\$USD]+/
        # Handle "100.00 USD" or "100.00 $" format
        clean_amount = amount_str.match(/([\-\d,\.]+)\s+[\$USD]+/)[1]
        clean_amount.delete(',').to_f
      when /^[\-\d,\.]+$/
        # Handle plain number format
        amount_str.delete(',').to_f
      else
        # If it's just a category name without an amount, return 0
        # This will be handled by the caller
        0.0
      end
    end
  end
end
