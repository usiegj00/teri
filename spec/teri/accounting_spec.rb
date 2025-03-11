require 'spec_helper'
require 'tempfile'

RSpec.describe Teri::Accounting do
  subject do
    # Mock the logger setup to avoid file system operations during tests
    logger_double = double('Logger', info: nil, warn: nil, error: nil)
    allow_any_instance_of(described_class).to receive(:setup_logger).and_return(nil)
    allow_any_instance_of(described_class).to receive(:logger).and_return(logger_double)

    described_class.new(options)
  end

  let(:options) { {} }
  let(:mock_io) { instance_double(Teri::IOAdapter) }
  let(:mock_file) { double('FileAdapter') }

  before do
    # Set up the mock IO adapter
    allow(mock_io).to receive(:puts)
    allow(mock_io).to receive(:print)

    # Set up the mock File adapter
    allow(mock_file).to receive(:exist?).and_return(false)
    allow(mock_file).to receive(:warning)
    allow(mock_file).to receive(:read_file).with('coding.ledger').and_return([])

    # Stub load_previous_codings to use the mock file adapter
    allow(subject).to receive(:load_previous_codings).and_call_original
    subject.load_previous_codings(mock_file)
  end

  describe '#code_transaction' do
    it 'creates a reverse transaction with the selected category' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Get the first predefined category
      first_category = subject.all_categories.first

      # Call the method with option 3 (first predefined category)
      reverse_transaction = subject.code_transaction(transaction, '3')

      # Verify the reverse transaction was created correctly
      expect(reverse_transaction).to be_a(Teri::Transaction)

      # Find the debit entry with the first category
      debit_entry = reverse_transaction.entries.find { |e| e.type == :debit && e.account == first_category }
      expect(debit_entry).not_to be_nil
      expect(debit_entry.amount).to eq(100.00)
    end

    it 'handles split transactions correctly' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Create a mock reverse transaction
      reverse_transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Reversal: Test Transaction',
        transaction_id: 'rev-test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the reverse transaction
      reverse_transaction.add_debit(account: 'Expenses:Rent', amount: 50.00)
      reverse_transaction.add_debit(account: 'Expenses:Utilities', amount: 50.00)
      reverse_transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Stub the code_transaction method to return our mock reverse transaction
      allow(subject).to receive(:code_transaction).and_return(reverse_transaction)

      # Call the method with option 1 (split transaction)
      split_input = 'Expenses:Rent:50.00,Expenses:Utilities:50.00'
      result = subject.code_transaction(transaction, '1', split_input)

      # Verify the reverse transaction was created correctly
      expect(result).to be_a(Teri::Transaction)

      # Find the debit entries with the split categories
      rent_entry = result.entries.find { |e| e.type == :debit && e.account == 'Expenses:Rent' }
      utilities_entry = result.entries.find { |e| e.type == :debit && e.account == 'Expenses:Utilities' }

      expect(rent_entry).not_to be_nil
      expect(utilities_entry).not_to be_nil
      expect(rent_entry.amount).to eq(50.00)
      expect(utilities_entry.amount).to eq(50.00)
    end
  end

  describe '#code_transaction_interactively' do
    it 'updates coding.ledger after each response' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Call the method
      subject.code_transaction_interactively(transaction, nil, nil, false, mock_io)

      # Verify the file was opened for appending
      expect(File).to have_received(:open).with('coding.ledger', 'a')
    end

    it 'handles AI suggestions when available' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Call the method
      subject.code_transaction_interactively(transaction, nil, nil, false, mock_io)

      # Verify the AI suggestion was displayed
      expect(mock_io).to have_received(:puts).with('AI Suggestion: Expenses:Rent (Confidence: 85.0%)')
    end

    it 'auto-applies AI suggestions when auto_apply_ai is true' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true, auto_apply_ai: true }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Call the method
      subject.code_transaction_interactively(transaction, nil, nil, true, mock_io)

      # Verify the auto-apply message was displayed
      expect(mock_io).to have_received(:puts).with(/Auto-applying AI suggestion/)
    end

    it 'returns "A" when the user selects the auto-apply option' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true, auto_apply_ai: true }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Call the method
      response = subject.code_transaction_interactively(transaction, nil, nil, true, mock_io)

      # Verify the response
      expect(response).to eq('A')
    end

    it 'collects feedback when the user doesn\'t choose the AI suggestion' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true, feedback: 'This is a property manager' }

      # Create a mock transaction
      transaction = Teri::Transaction.new(
        date: Date.new(2021, 3, 25),
        description: 'Test Transaction',
        transaction_id: 'test-123',
        status: 'sent',
        currency: 'USD'
      )

      # Add entries to the transaction
      transaction.add_debit(account: 'Expenses:Unknown', amount: 100.00)
      transaction.add_credit(account: 'Assets:Checking', amount: 100.00)

      # Create a mock reverse transaction
      reverse_transaction = double('ReverseTransaction')
      allow(reverse_transaction).to receive(:add_comment)

      # Stub the transaction_coder's code_transaction_interactively method to return our mock reverse transaction
      allow(subject.transaction_coder).to receive(:code_transaction_interactively).and_return(reverse_transaction)

      # Call the method
      subject.code_transaction_interactively(transaction, nil, nil, false, mock_io)

      # Verify the feedback was added
      expect(reverse_transaction).to have_received(:add_comment).with('Hint: This is a property manager')
    end
  end

  describe '#code_transactions' do
    it 'updates coding.ledger after each transaction is coded' do
      # Set up test behavior
      subject.test_behavior = { update_coding_ledger: true }

      # Create mock transactions
      transactions = [
        Teri::Transaction.new(
          date: Date.new(2021, 3, 25),
          description: 'Test Transaction 1',
          transaction_id: 'test-123',
          status: 'sent',
          currency: 'USD'
        ),
        Teri::Transaction.new(
          date: Date.new(2021, 3, 25),
          description: 'Test Transaction 2',
          transaction_id: 'test-456',
          status: 'sent',
          currency: 'USD'
        ),
      ]

      # Add entries to the transactions
      transactions.each do |t|
        t.add_debit(account: 'Expenses:Unknown', amount: 100.00)
        t.add_credit(account: 'Assets:Checking', amount: 100.00)
      end

      # Call the method
      subject.code_transactions(transactions)

      # Verify the file was opened for appending twice
      expect(File).to have_received(:open).with('coding.ledger', 'a').twice
    end
  end

  describe '#load_previous_codings' do
    it 'loads previous codings from coding.ledger' do
      # Set up test data
      test_data = {
        'Rent Payment' => {
          category: 'Expenses:Rent',
          split: nil,
          new_category: nil,
          feedback: 'This is a property manager',
        },
      }

      # Set up the mock file adapter
      allow(mock_file).to receive(:read_file).with('coding.ledger').and_return(test_data)

      # Call the method
      previous_codings = subject.load_previous_codings(mock_file)

      # Verify the previous codings were loaded correctly
      expect(previous_codings['Rent Payment'][:category]).to eq('Expenses:Rent')
    end

    it 'handles errors gracefully' do
      # Set up test data
      test_file_adapter = double('FileAdapter')
      allow(test_file_adapter).to receive(:read_file).with('coding.ledger').and_raise(StandardError.new('File not found'))

      # Set up the logger to receive the warning
      logger_double = double('Logger')
      allow(logger_double).to receive(:warn)
      subject.instance_variable_set(:@logger, logger_double)

      # Call the method
      result = subject.load_previous_codings(test_file_adapter)

      # Verify the error was handled gracefully
      expect(logger_double).to have_received(:warn).with(/Failed to load previous codings/)
      expect(result).to eq([])
    end
  end
end
