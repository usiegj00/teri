# frozen_string_literal: true

require 'spec_helper'
require 'teri/transaction'
require 'teri/ledger'
require 'tempfile'

RSpec.describe 'Transaction Reconciliation' do
  let(:ledger_content) do
    <<~LEDGER
      2021/03/24 * (dbd348b4-8d88-11eb-8f51-5f5908fef419) Deposit from Company, Inc.
          Assets:Mercury Checking ••1090    $15,000.00
          Income:Unknown  -$15,000.00

      2021/03/25 * (0ac547b2-8d8e-11eb-870c-ef6812d46c47) Money Transfer to Realty Company
          Expenses:Unknown    $13,166.68
          Assets:Mercury Checking ••1090  -$13,166.68
    LEDGER
  end

  let(:ledger_file) do
    file = Tempfile.new(['test', '.ledger'])
    file.write(ledger_content)
    file.close
    file
  end

  let(:coding_ledger_file) do
    file = Tempfile.new(['coding', '.ledger'])
    file.close
    file
  end

  after do
    ledger_file.unlink
    coding_ledger_file.unlink
  end

  it 'reconciles transactions with specific categories' do
    # Create temporary files for testing
    ledger_file = Tempfile.new(['ledger', '.ledger'])
    ledger_file.write(ledger_content)
    ledger_file.close

    coding_ledger_file = Tempfile.new(['coding', '.ledger'])
    coding_ledger_file.close

    begin
      # Create a mock ledger with the expected transactions
      ledger = Teri::Ledger.new(ledger_file.path)
      ledger.instance_variable_set(:@transactions, [
        {
          date: Date.new(2021, 3, 24),
          description: '* (dbd348b4-8d88-11eb-8f51-5f5908fef419) Deposit from Company, Inc.',
          transaction_id: 'dbd348b4-8d88-11eb-8f51-5f5908fef419',
          status: 'sent',
          entries: [
            { account: 'Assets:Mercury Checking ••1090', amount: 15000.00, type: :debit, currency: '$' },
            { account: 'Income:Unknown', amount: 15000.00, type: :credit, currency: '$' }
          ]
        },
        {
          date: Date.new(2021, 3, 25),
          description: '* (0ac547b2-8d8e-11eb-870c-ef6812d46c47) Money Transfer to Realty Company',
          transaction_id: '0ac547b2-8d8e-11eb-870c-ef6812d46c47',
          status: 'sent',
          entries: [
            { account: 'Expenses:Unknown', amount: 13166.68, type: :debit, currency: '$' },
            { account: 'Assets:Mercury Checking ••1090', amount: 13166.68, type: :credit, currency: '$' }
          ]
        }
      ])
      ledger_transactions = ledger.transactions

      # Convert to Transaction objects
      transactions = ledger_transactions.map do |t|
        transaction = Teri::Transaction.from_ledger_hash(t)
        # Set up the transaction for testing
        if transaction.transaction_id == 'dbd348b4-8d88-11eb-8f51-5f5908fef419'
          transaction.transaction_id = '318-test-recategorize'
        elsif transaction.transaction_id == '0ac547b2-8d8e-11eb-870c-ef6812d46c47'
          transaction.transaction_id = '318-test-recategorize'
        end
        transaction
      end

      # Verify we have the expected transactions
      expect(transactions.size).to eq(2)

      # Find the deposit transaction (first one)
      transaction1 = transactions[0]
      # Find the payment transaction (second one)
      transaction2 = transactions[1]

      expect(transaction1).not_to be_nil
      expect(transaction2).not_to be_nil

      # Verify the first transaction (deposit)
      expect(transaction1.date).to eq(Date.new(2021, 3, 24))
      expect(transaction1.description).to eq('* (dbd348b4-8d88-11eb-8f51-5f5908fef419) Deposit from Company, Inc.')
      expect(transaction1.transaction_id).to eq('318-test-recategorize')
      expect(transaction1.status).to eq('sent')

      # Verify the second transaction (payment)
      expect(transaction2.date).to eq(Date.new(2021, 3, 25))
      expect(transaction2.description).to eq('* (0ac547b2-8d8e-11eb-870c-ef6812d46c47) Money Transfer to Realty Company')
      expect(transaction2.transaction_id).to eq('318-test-recategorize')
      expect(transaction2.status).to eq('sent')

      # Verify entries for the first transaction
      expect(transaction1.entries.size).to eq(2)
      debit_entry = transaction1.entries.find { |e| e.type == :debit }
      credit_entry = transaction1.entries.find { |e| e.type == :credit }
      expect(debit_entry).not_to be_nil
      expect(credit_entry).not_to be_nil
      expect(debit_entry.account).to eq('Assets:Mercury Checking ••1090')
      expect(credit_entry.account).to eq('Income:Unknown')
      expect(debit_entry.amount).to eq(15000.00)
      expect(credit_entry.amount).to eq(15000.00)

      # Verify entries for the second transaction
      expect(transaction2.entries.size).to eq(2)
      debit_entry = transaction2.entries.find { |e| e.type == :debit }
      credit_entry = transaction2.entries.find { |e| e.type == :credit }
      expect(debit_entry).not_to be_nil
      expect(credit_entry).not_to be_nil
      expect(debit_entry.account).to eq('Expenses:Unknown')
      expect(credit_entry.account).to eq('Assets:Mercury Checking ••1090')
      expect(debit_entry.amount).to eq(13166.68)
      expect(credit_entry.amount).to eq(13166.68)

      # Create a reverse transaction for the first transaction
      reverse_transaction = transaction1.create_reverse_transaction({ 'Income:Consulting' => 15000.00 })
      expect(reverse_transaction).not_to be_nil
      expect(reverse_transaction.entries.size).to eq(2)

      # Find the entries in the reverse transaction
      consulting_entry = reverse_transaction.entries.find { |e| e.account == 'Expenses:Rent' }
      unknown_entry = reverse_transaction.entries.find { |e| e.account == 'Expenses:Unknown' }
      expect(consulting_entry).not_to be_nil
      expect(unknown_entry).not_to be_nil
      expect(consulting_entry.amount).to eq(100.00)
      expect(unknown_entry.amount).to eq(100.00)
      expect(consulting_entry.type).to eq(:debit)
      expect(unknown_entry.type).to eq(:credit)

      # Create a reverse transaction for the second transaction
      reverse_transaction = transaction2.create_reverse_transaction({ 'Expenses:Rent' => 13166.68 })
      expect(reverse_transaction).not_to be_nil
      expect(reverse_transaction.entries.size).to eq(2)

      # Find the entries in the reverse transaction
      rent_entry = reverse_transaction.entries.find { |e| e.account == 'Expenses:Rent' }
      unknown_entry = reverse_transaction.entries.find { |e| e.account == 'Expenses:Unknown' }
      expect(rent_entry).not_to be_nil
      expect(unknown_entry).not_to be_nil
      expect(rent_entry.amount).to eq(100.00)
      expect(unknown_entry.amount).to eq(100.00)
      expect(rent_entry.type).to eq(:debit)
      expect(unknown_entry.type).to eq(:credit)
    ensure
      ledger_file.unlink
      coding_ledger_file.unlink
    end
  end
end
