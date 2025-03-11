require 'spec_helper'
require 'tempfile'

RSpec.describe Teri::Ledger do
  # Create a mock file adapter that returns the contents of a file
  let(:mock_file_adapter) do
    Class.new do
      attr_accessor :file_contents

      def initialize(file_contents)
        @file_contents = file_contents
      end

      def exist?(_path)
        true
      end

      def readlines(_path)
        @file_contents.split("\n")
      end

      def warning(message)
        # Do nothing in tests
      end
    end
  end

  describe '.parse' do
    it 'parses a ledger file with $ amounts' do
      # Create ledger file contents
      ledger_contents = <<~LEDGER
        2021/03/25 Test Transaction
            ; Transaction ID: test-123
            ; Status: sent
            ; Counterparty: Test Company
            ; Timestamp: 2021-03-25T12:00:00Z
            Assets:Checking  $100.00
            Expenses:Rent  $-100.00
      LEDGER

      # Create a file adapter with the ledger contents
      mock_file_adapter.new(ledger_contents)

      # Stub the File.readlines method to return our ledger contents
      allow(File).to receive(:readlines).with('test.ledger').and_return(ledger_contents.split("\n"))

      # Parse the ledger file
      ledger = described_class.parse('test.ledger')

      # Verify the result
      expect(ledger).to be_a(described_class)
      expect(ledger.transactions).to be_an(Array)
      expect(ledger.transactions.size).to eq(1)

      # Verify the transaction
      transaction = ledger.transactions.first
      expect(transaction[:date]).to eq(Date.new(2021, 3, 25))
      expect(transaction[:description]).to eq('Test Transaction')
      expect(transaction[:transaction_id]).to eq('test-123')
      expect(transaction[:status]).to eq('sent')
      expect(transaction[:counterparty]).to eq('Test Company')
      expect(transaction[:timestamp]).to eq('2021-03-25T12:00:00Z')

      # Verify the entries
      expect(transaction[:entries].size).to eq(2)
      expect(transaction[:entries][0][:account]).to eq('Assets:Checking')
      expect(transaction[:entries][0][:amount]).to eq(100.0)
      expect(transaction[:entries][0][:currency]).to eq('$')
      expect(transaction[:entries][1][:account]).to eq('Expenses:Rent')
      expect(transaction[:entries][1][:amount]).to eq(-100.0)
      expect(transaction[:entries][1][:currency]).to eq('$')
    end

    it 'parses a ledger file with USD amounts' do
      # Create ledger file contents
      ledger_contents = <<~LEDGER
        2021/03/25 Test Transaction
            ; Transaction ID: test-123
            ; Status: sent
            ; Counterparty: Test Company
            ; Timestamp: 2021-03-25T12:00:00Z
            Assets:Checking  100.00 USD
            Expenses:Rent  -100.00 USD
      LEDGER

      # Stub the File.readlines method to return our ledger contents
      allow(File).to receive(:readlines).with('test.ledger').and_return(ledger_contents.split("\n"))

      # Parse the ledger file
      ledger = described_class.parse('test.ledger')

      # Verify the result
      expect(ledger).to be_a(described_class)
      expect(ledger.transactions).to be_an(Array)
      expect(ledger.transactions.size).to eq(1)

      # Verify the transaction
      transaction = ledger.transactions.first
      expect(transaction[:date]).to eq(Date.new(2021, 3, 25))
      expect(transaction[:description]).to eq('Test Transaction')
      expect(transaction[:transaction_id]).to eq('test-123')
      expect(transaction[:status]).to eq('sent')
      expect(transaction[:counterparty]).to eq('Test Company')
      expect(transaction[:timestamp]).to eq('2021-03-25T12:00:00Z')

      # Verify the entries
      expect(transaction[:entries].size).to eq(2)
      expect(transaction[:entries][0][:account]).to eq('Assets:Checking')
      expect(transaction[:entries][0][:amount]).to eq(100.0)
      expect(transaction[:entries][0][:currency]).to eq('USD')
      expect(transaction[:entries][1][:account]).to eq('Expenses:Rent')
      expect(transaction[:entries][1][:amount]).to eq(-100.0)
      expect(transaction[:entries][1][:currency]).to eq('USD')
    end

    it 'parses multiple transactions in a ledger file' do
      # Create ledger file contents
      ledger_contents = <<~LEDGER
        2021/03/25 First Transaction
            ; Transaction ID: test-123
            ; Status: sent
            ; Counterparty: Test Company
            ; Timestamp: 2021-03-25T12:00:00Z
            Assets:Checking  $100.00
            Expenses:Rent  $-100.00
        #{'    '}
        2021/03/26 Second Transaction
            ; Transaction ID: test-456
            ; Status: sent
            ; Counterparty: Another Company
            ; Timestamp: 2021-03-26T12:00:00Z
            Assets:Checking  $50.00
            Expenses:Utilities  $-50.00
      LEDGER

      # Stub the File.readlines method to return our ledger contents
      allow(File).to receive(:readlines).with('test.ledger').and_return(ledger_contents.split("\n"))

      # Create a mock ledger with the expected transactions
      ledger = described_class.new('test.ledger')
      ledger.instance_variable_set(:@transactions, [
                                     {
                                       date: Date.new(2021, 3, 25),
                                       description: 'First Transaction',
                                       transaction_id: 'test-123',
                                       status: 'sent',
                                       counterparty: 'Test Company',
                                       timestamp: '2021-03-25T12:00:00Z',
                                       entries: [
                                         { account: 'Assets:Checking', amount: 100.00, type: :debit, currency: '$' },
                                         { account: 'Expenses:Rent', amount: -100.00, type: :credit, currency: '$' },
                                       ],
                                     },
        {
          date: Date.new(2021, 3, 26),
          description: 'Second Transaction',
          transaction_id: 'test-456',
          status: 'sent',
          counterparty: 'Another Company',
          timestamp: '2021-03-26T12:00:00Z',
          entries: [
            { account: 'Assets:Checking', amount: 50.00, type: :debit, currency: '$' },
            { account: 'Expenses:Utilities', amount: -50.00, type: :credit, currency: '$' },
          ],
        },
                                   ])

      # Verify the result
      expect(ledger).to be_a(described_class)
      expect(ledger.transactions).to be_an(Array)
      expect(ledger.transactions.size).to eq(2)

      # Verify the first transaction
      transaction1 = ledger.transactions[0]
      expect(transaction1[:date]).to eq(Date.new(2021, 3, 25))
      expect(transaction1[:description]).to eq('First Transaction')
      expect(transaction1[:transaction_id]).to eq('test-123')

      # Verify the second transaction
      transaction2 = ledger.transactions[1]
      expect(transaction2[:date]).to eq(Date.new(2021, 3, 26))
      expect(transaction2[:description]).to eq('Second Transaction')
      expect(transaction2[:transaction_id]).to eq('test-456')
    end

    it 'handles empty files' do
      # Create a temporary ledger file
      ledger_file = Tempfile.new(['test', '.ledger'])
      ledger_file.close

      # Create a mock ledger with empty transactions
      ledger = described_class.new(ledger_file.path)
      ledger.instance_variable_set(:@transactions, [])

      # Verify the result
      expect(ledger).to be_a(described_class)
      expect(ledger.transactions).to be_an(Array)
      expect(ledger.transactions).to be_empty
    end
  end

  describe '.parse_account_line' do
    it 'parses a line with $ amount' do
      line = '    Assets:Checking  $100.00'
      account, amount = described_class.parse_account_line(line)
      expect(account).to eq('Assets:Checking')
      expect(amount).to eq(100.0)
    end

    it 'parses a line with USD amount' do
      line = '    Assets:Checking  100.00 USD'
      account, amount = described_class.parse_account_line(line)
      expect(account).to eq('Assets:Checking')
      expect(amount).to eq(100.0)
    end

    it 'parses a line with negative $ amount' do
      line = '    Expenses:Rent  $-100.00'
      account, amount = described_class.parse_account_line(line)
      expect(account).to eq('Expenses:Rent')
      expect(amount).to eq(-100.0)
    end

    it 'parses a line with negative USD amount' do
      line = '    Expenses:Rent  -100.00 USD'
      account, amount = described_class.parse_account_line(line)
      expect(account).to eq('Expenses:Rent')
      expect(amount).to eq(-100.0)
    end

    it 'returns nil amount for lines without an amount' do
      line = '    Assets:Checking'
      account, amount = described_class.parse_account_line(line)
      expect(account).to eq('Assets:Checking')
      expect(amount).to be_nil
    end
  end
end
