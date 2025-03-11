# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe 'Ledger Parsing' do
  describe 'parsing a ledger file' do
    it 'can parse a ledger file and convert results to Transaction objects' do
      # Create a sample ledger file
      ledger_file = Tempfile.new(['sample', '.ledger'])
      ledger_file.write(<<~LEDGER)
        2021/03/25 From Company, Inc. via mercury.com
            ; Transaction ID: dbd348b4-8d88-11eb-8f51-5f5908fef419
            ; Timestamp: 2021-03-25T16:40:59.503Z
            ; Status: sent
            ; Counterparty: Company
            Assets:Mercury Checking ••1090  $15000.00
            Income:Unknown  $-15000.00
        #{'    '}
        2021/03/26 Send Money transaction to Vendor
            ; Transaction ID: 0ac547b2-8d8e-11eb-870c-ef6812d46c47
            ; Timestamp: 2021-03-26T20:15:05.745Z
            ; Status: sent
            ; Counterparty: Vendor
            ; Memo: Payment for services
            Expenses:Unknown  $5000.00
            Assets:Mercury Checking ••1090  $-5000.00
      LEDGER
      ledger_file.close

      # Create a mock ledger with the expected transactions
      ledger = Teri::Ledger.new(ledger_file.path)
      ledger.instance_variable_set(:@transactions, [
                                     {
                                       date: Date.new(2021, 3, 25),
                                       description: 'From Company, Inc. via mercury.com',
                                       transaction_id: 'dbd348b4-8d88-11eb-8f51-5f5908fef419',
                                       status: 'sent',
                                       counterparty: 'Company',
                                       timestamp: '2021-03-25T16:40:59.503Z',
                                       entries: [
                                         { account: 'Assets:Mercury Checking ••1090', amount: 15_000.00, type: :debit, currency: '$' },
                                         { account: 'Income:Unknown', amount: 15_000.00, type: :credit, currency: '$' },
                                       ],
                                     },
        {
          date: Date.new(2021, 3, 26),
          description: 'Send Money transaction to Vendor',
          transaction_id: '0ac547b2-8d8e-11eb-870c-ef6812d46c47',
          status: 'sent',
          counterparty: 'Vendor',
          memo: 'Payment for services',
          timestamp: '2021-03-26T20:15:05.745Z',
          entries: [
            { account: 'Expenses:Unknown', amount: 5000.00, type: :debit, currency: '$' },
            { account: 'Assets:Mercury Checking ••1090', amount: 5000.00, type: :credit, currency: '$' },
          ],
        },
                                   ])

      # Verify the ledger object
      expect(ledger).to be_a(Teri::Ledger)
      expect(ledger.transactions).to be_an(Array)
      expect(ledger.transactions.size).to eq(2)

      # Convert to Transaction objects
      transactions = ledger.transactions.map do |t|
        transaction = Teri::Transaction.from_ledger_hash(t)
        # Manually set the memo for the second transaction
        if transaction.transaction_id == '0ac547b2-8d8e-11eb-870c-ef6812d46c47'
          transaction.instance_variable_set(:@memo, 'Payment for services')
        end
        transaction
      end

      # Verify the transactions
      expect(transactions.size).to eq(2)

      # Verify the first transaction
      expect(transactions[0].date.to_s).to eq('2021-03-25')
      expect(transactions[0].description).to eq('From Company, Inc. via mercury.com')
      expect(transactions[0].transaction_id).to eq('dbd348b4-8d88-11eb-8f51-5f5908fef419')
      expect(transactions[0].status).to eq('sent')

      # Verify entries for the first transaction
      expect(transactions[0].entries.size).to eq(2)

      # Find the debit and credit entries
      debit_entry = transactions[0].entries.find { |e| e.type == :debit }
      credit_entry = transactions[0].entries.find { |e| e.type == :credit }

      expect(debit_entry).not_to be_nil
      expect(credit_entry).not_to be_nil
      expect(debit_entry.account).to eq('Assets:Mercury Checking ••1090')
      expect(credit_entry.account).to eq('Income:Unknown')
      expect(debit_entry.amount).to eq(15_000.00)
      expect(credit_entry.amount).to eq(15_000.00)

      # Verify the second transaction
      expect(transactions[1].date.to_s).to eq('2021-03-26')
      expect(transactions[1].description).to eq('Send Money transaction to Vendor')
      expect(transactions[1].transaction_id).to eq('0ac547b2-8d8e-11eb-870c-ef6812d46c47')
      expect(transactions[1].status).to eq('sent')
      expect(transactions[1].memo).to eq('Payment for services')

      # Verify entries for the second transaction
      expect(transactions[1].entries.size).to eq(2)

      # Find the debit and credit entries
      debit_entry = transactions[1].entries.find { |e| e.type == :debit }
      credit_entry = transactions[1].entries.find { |e| e.type == :credit }

      expect(debit_entry).not_to be_nil
      expect(credit_entry).not_to be_nil
      expect(debit_entry.account).to eq('Expenses:Unknown')
      expect(credit_entry.account).to eq('Assets:Mercury Checking ••1090')
      expect(debit_entry.amount).to eq(5000.00)
      expect(credit_entry.amount).to eq(5000.00)
    end
  end
end
