require 'spec_helper'

RSpec.describe Teri::Transaction do
  let(:date) { Date.new(2021, 3, 25) }
  let(:description) { 'Test Transaction' }
  let(:transaction_id) { 'test-123' }
  let(:status) { 'sent' }
  let(:currency) { 'USD' }

  describe 'Entry' do
    describe '#initialize' do
      it 'creates a valid debit entry' do
        entry = Teri::Entry.new(
          account: 'Assets:Checking',
          amount: 100.00,
          currency: 'USD',
          type: :debit
        )

        expect(entry.account).to eq('Assets:Checking')
        expect(entry.amount).to eq(100.00)
        expect(entry.currency).to eq('USD')
        expect(entry.type).to eq(:debit)
      end

      it 'creates a valid credit entry' do
        entry = Teri::Entry.new(
          account: 'Expenses:Rent',
          amount: 100.00,
          currency: 'USD',
          type: :credit
        )

        expect(entry.account).to eq('Expenses:Rent')
        expect(entry.amount).to eq(100.00)
        expect(entry.currency).to eq('USD')
        expect(entry.type).to eq(:credit)
      end

      it 'raises an error for invalid type' do
        expect do
          Teri::Entry.new(
            account: 'Assets:Checking',
            amount: 100.00,
            currency: 'USD',
            type: :invalid
          )
        end.to raise_error(ArgumentError, 'Type must be :debit or :credit')
      end

      it 'raises an error for zero amount' do
        expect do
          Teri::Entry.new(
            account: 'Assets:Checking',
            amount: 0,
            currency: 'USD',
            type: :debit
          )
        end.to raise_error(ArgumentError, 'Amount must be positive')
      end

      it 'converts negative amounts to positive' do
        entry = Teri::Entry.new(
          account: 'Assets:Checking',
          amount: -100.00,
          currency: 'USD',
          type: :debit
        )

        expect(entry.amount).to eq(100.00)
      end
    end

    describe '#signed_amount' do
      it 'returns positive amount for debit' do
        entry = Teri::Entry.new(
          account: 'Assets:Checking',
          amount: 100.00,
          currency: 'USD',
          type: :debit
        )

        expect(entry.signed_amount).to eq(100.00)
      end

      it 'returns negative amount for credit' do
        entry = Teri::Entry.new(
          account: 'Expenses:Rent',
          amount: 100.00,
          currency: 'USD',
          type: :credit
        )

        expect(entry.signed_amount).to eq(-100.00)
      end
    end

    describe '#to_ledger' do
      it 'formats debit entry for ledger' do
        entry = Teri::Entry.new(
          account: 'Assets:Checking',
          amount: 100.00,
          currency: 'USD',
          type: :debit
        )

        expect(entry.to_ledger).to eq('    Assets:Checking  $100.0')
      end

      it 'formats credit entry for ledger' do
        entry = Teri::Entry.new(
          account: 'Expenses:Rent',
          amount: 100.00,
          currency: 'USD',
          type: :credit
        )

        expect(entry.to_ledger).to eq('    Expenses:Rent  $-100.0')
      end
    end
  end

  describe 'Transaction' do
    subject do
      described_class.new(
        date: date,
        description: description,
        transaction_id: transaction_id,
        status: status,
        currency: currency
      )
    end

    describe '#initialize' do
      it 'creates an empty transaction' do
        expect(subject.entries).to be_empty
        expect(subject.date).to eq(date)
        expect(subject.description).to eq(description)
        expect(subject.transaction_id).to eq(transaction_id)
        expect(subject.status).to eq(status)
        expect(subject.currency).to eq(currency)
      end
    end

    describe '#add_entry' do
      it 'adds an entry to the transaction' do
        entry = subject.add_entry(
          account: 'Assets:Checking',
          amount: 100.00,
          type: :debit
        )

        expect(subject.entries.size).to eq(1)
        expect(subject.entries.first).to eq(entry)
        expect(entry.account).to eq('Assets:Checking')
        expect(entry.amount).to eq(100.00)
        expect(entry.type).to eq(:debit)
      end
    end

    describe '#add_debit' do
      it 'adds a debit entry to the transaction' do
        entry = subject.add_debit(
          account: 'Assets:Checking',
          amount: 100.00
        )

        expect(subject.entries.size).to eq(1)
        expect(subject.entries.first).to eq(entry)
        expect(entry.account).to eq('Assets:Checking')
        expect(entry.amount).to eq(100.00)
        expect(entry.type).to eq(:debit)
      end
    end

    describe '#add_credit' do
      it 'adds a credit entry to the transaction' do
        entry = subject.add_credit(
          account: 'Expenses:Rent',
          amount: 100.00
        )

        expect(subject.entries.size).to eq(1)
        expect(subject.entries.first).to eq(entry)
        expect(entry.account).to eq('Expenses:Rent')
        expect(entry.amount).to eq(100.00)
        expect(entry.type).to eq(:credit)
      end
    end

    describe '#balanced?' do
      it 'returns true for a balanced transaction' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 100.00)

        expect(subject.balanced?).to be true
      end

      it 'returns false for an unbalanced transaction' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 50.00)

        expect(subject.balanced?).to be false
      end

      it 'handles multiple entries' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 75.00)
        subject.add_credit(account: 'Expenses:Utilities', amount: 25.00)

        expect(subject.balanced?).to be true
      end

      it 'handles floating point precision issues' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 33.33)
        subject.add_credit(account: 'Expenses:Utilities', amount: 33.33)
        subject.add_credit(account: 'Expenses:Food', amount: 33.34)

        expect(subject.balanced?).to be true
      end
    end

    describe '#validate' do
      it 'returns no warnings for a valid transaction' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 100.00)

        expect(subject.validate).to be_empty
      end

      it 'warns about empty transactions' do
        expect(subject.validate).to include('Transaction has no entries')
      end

      it 'warns about unbalanced transactions' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 50.00)

        warnings = subject.validate
        expect(warnings).to include('Transaction is not balanced: debits (100.0) != credits (50.0)')
      end

      it 'warns about transactions with no debits' do
        subject.add_credit(account: 'Expenses:Rent', amount: 100.00)
        subject.add_credit(account: 'Expenses:Utilities', amount: 50.00)

        warnings = subject.validate
        expect(warnings).to include('Transaction has no debits')
      end

      it 'warns about transactions with no credits' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_debit(account: 'Assets:Savings', amount: 50.00)

        warnings = subject.validate
        expect(warnings).to include('Transaction has no credits')
      end
    end

    describe '#valid?' do
      it 'returns true for a valid transaction' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 100.00)

        expect(subject.valid?).to be true
      end

      it 'returns false for an invalid transaction' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)

        expect(subject.valid?).to be false
      end
    end

    describe '#to_ledger' do
      it 'formats a transaction for ledger file' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 100.00)

        expected_output = "2021/03/25 Test Transaction\n    " \
                          "; Transaction ID: test-123\n    " \
                          "; Status: sent\n    " \
                          "Assets:Checking  $100.0\n    " \
                          "Expenses:Rent  $-100.0\n"

        expect(subject.to_ledger).to eq(expected_output)
      end

      it 'raises an error for unbalanced transactions' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)

        expect { subject.to_ledger }.to raise_error(RuntimeError, /Cannot write unbalanced transaction to ledger/)
      end
    end

    describe '#create_reverse_transaction' do
      it 'creates a transaction with reversed entries' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Income:Unknown', amount: 100.00)

        reverse = subject.create_reverse_transaction

        expect(reverse.entries.size).to eq(2)

        # Find the entries
        checking_credit = reverse.entries.find { |e| e.type == :credit && e.account == 'Assets:Checking' }
        unknown_debit = reverse.entries.find { |e| e.type == :debit && e.account == 'Income:Unknown' }

        expect(checking_credit).not_to be_nil
        expect(unknown_debit).not_to be_nil
        expect(checking_credit.amount).to eq(100.00)
        expect(unknown_debit.amount).to eq(100.00)

        expect(reverse.valid?).to be true
      end

      it 'creates a transaction that recategorizes only the Unknown portion' do
        subject.transaction_id = '318-test-recategorize'
        subject.add_debit(account: 'Expenses:Unknown', amount: 100.00)
        subject.add_credit(account: 'Assets:Checking', amount: 100.00)

        reverse_transaction = subject.create_reverse_transaction({ 'Expenses:Rent' => 100.00 })

        expect(reverse_transaction.entries.size).to eq(2)

        # Find the entries
        rent_entry = reverse_transaction.entries.find { |e| e.account == 'Expenses:Rent' }
        unknown_entry = reverse_transaction.entries.find { |e| e.account == 'Expenses:Unknown' }

        # Verify the entries
        expect(rent_entry).not_to be_nil
        expect(unknown_entry).not_to be_nil
        expect(rent_entry.type).to eq(:debit)
        expect(unknown_entry.type).to eq(:credit)
        expect(rent_entry.amount).to eq(100.00)
        expect(unknown_entry.amount).to eq(100.00)
      end

      it 'raises an error when recategorizing a transaction without an Unknown category' do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Rent', amount: 100.00)

        new_categories = {
          'Expenses:Utilities' => 100.00,
        }

        expect do
          subject.create_reverse_transaction(new_categories)
        end.to raise_error(RuntimeError,
                           /Cannot recategorize transaction without an Unknown category/)
      end

      it "raises an error when the total amount of new categories doesn't match the Unknown entry amount" do
        subject.add_debit(account: 'Assets:Checking', amount: 100.00)
        subject.add_credit(account: 'Expenses:Unknown', amount: 100.00)

        new_categories = {
          'Expenses:Rent' => 50.00,
          'Expenses:Utilities' => 25.00,
        }

        expect do
          subject.create_reverse_transaction(new_categories)
        end.to raise_error(RuntimeError,
                           /Total amount of new categories .* does not match the Unknown entry amount/)
      end
    end

    describe '.from_ledger_hash' do
      it 'creates a transaction from a ledger hash with entries' do
        hash = {
          date: date,
          description: description,
          transaction_id: transaction_id,
          status: status,
          currency: currency,
          entries: [
            { account: 'Assets:Checking', amount: 100.00, type: :debit },
            { account: 'Expenses:Rent', amount: 100.00, type: :credit },
          ],
        }

        transaction = described_class.from_ledger_hash(hash)

        expect(transaction.entries.size).to eq(2)
        expect(transaction.entries[0].account).to eq('Assets:Checking')
        expect(transaction.entries[0].amount).to eq(100.00)
        expect(transaction.entries[0].type).to eq(:debit)

        expect(transaction.entries[1].account).to eq('Expenses:Rent')
        expect(transaction.entries[1].amount).to eq(100.00)
        expect(transaction.entries[1].type).to eq(:credit)

        expect(transaction.valid?).to be true
      end

      it 'creates a transaction from a legacy ledger hash' do
        hash = {
          date: date,
          description: description,
          transaction_id: transaction_id,
          status: status,
          amount: 100.00,
          from_account: 'Assets:Checking',
          to_account: 'Expenses:Rent',
          currency: currency,
        }

        transaction = described_class.from_ledger_hash(hash)

        expect(transaction.entries.size).to eq(2)
        expect(transaction.entries[0].account).to eq('Expenses:Rent')
        expect(transaction.entries[0].amount).to eq(100.00)
        expect(transaction.entries[0].type).to eq(:debit)

        expect(transaction.entries[1].account).to eq('Assets:Checking')
        expect(transaction.entries[1].amount).to eq(100.00)
        expect(transaction.entries[1].type).to eq(:credit)

        expect(transaction.valid?).to be true
      end
    end

    # Test real-world accounting scenarios
    describe 'accounting scenarios' do
      it 'handles investing cash into a company' do
        # Invest $50,000 cash into your company
        transaction = described_class.new(
          date: date,
          description: 'Initial investment',
          transaction_id: transaction_id,
          status: status,
          currency: currency
        )

        transaction.add_debit(account: 'Assets:Cash', amount: 50_000.00)
        transaction.add_credit(account: "Equity:Owner's Capital", amount: 50_000.00)

        expect(transaction.valid?).to be true
      end

      it 'handles buying property' do
        # Buy property for $35,000
        transaction = described_class.new(
          date: date,
          description: 'Purchase property',
          transaction_id: transaction_id,
          status: status,
          currency: currency
        )

        transaction.add_debit(account: 'Assets:Property', amount: 35_000.00)
        transaction.add_credit(account: 'Assets:Cash', amount: 35_000.00)

        expect(transaction.valid?).to be true
      end

      it 'handles paying for maintenance' do
        # Pay $1,500 for property maintenance
        transaction = described_class.new(
          date: date,
          description: 'Property maintenance',
          transaction_id: transaction_id,
          status: status,
          currency: currency
        )

        transaction.add_debit(account: 'Expenses:Maintenance', amount: 1500.00)
        transaction.add_credit(account: 'Assets:Cash', amount: 1500.00)

        expect(transaction.valid?).to be true
      end

      it 'handles receiving rental income' do
        # Receive $2,000 rental income
        transaction = described_class.new(
          date: date,
          description: 'Rental income',
          transaction_id: transaction_id,
          status: status,
          currency: currency
        )

        transaction.add_debit(account: 'Assets:Cash', amount: 2000.00)
        transaction.add_credit(account: 'Income:Rental Income', amount: 2000.00)

        expect(transaction.valid?).to be true
      end

      it 'handles complex split transactions' do
        # Pay $2,500 for multiple expenses
        transaction = described_class.new(
          date: date,
          description: 'Monthly expenses',
          transaction_id: transaction_id,
          status: status,
          currency: currency
        )

        transaction.add_credit(account: 'Assets:Checking', amount: 2500.00)
        transaction.add_debit(account: 'Expenses:Rent', amount: 1500.00)
        transaction.add_debit(account: 'Expenses:Utilities', amount: 300.00)
        transaction.add_debit(account: 'Expenses:Groceries', amount: 400.00)
        transaction.add_debit(account: 'Expenses:Internet', amount: 100.00)
        transaction.add_debit(account: 'Expenses:Phone', amount: 200.00)

        expect(transaction.valid?).to be true
      end

      it 'handles loan payments with principal and interest' do
        # Pay $178 loan payment ($150 principal, $28 interest)
        transaction = described_class.new(
          date: date,
          description: 'Loan payment',
          transaction_id: transaction_id,
          status: status,
          currency: currency
        )

        transaction.add_credit(account: 'Assets:Checking', amount: 178.00)
        transaction.add_debit(account: 'Liabilities:Loan', amount: 150.00)
        transaction.add_debit(account: 'Expenses:Interest', amount: 28.00)

        expect(transaction.valid?).to be true
      end
    end

    describe 'currency normalization' do
      it 'normalizes $ to USD in Entry' do
        entry = Teri::Entry.new(
          account: 'Assets:Checking',
          amount: 100.00,
          currency: '$',
          type: :debit
        )

        expect(entry.currency).to eq('USD')
      end

      it 'normalizes $ to USD in Transaction.from_ledger_hash' do
        hash = {
          date: date,
          description: description,
          transaction_id: transaction_id,
          status: status,
          amount: 100.00,
          from_account: 'Assets:Checking',
          to_account: 'Expenses:Rent',
          currency: '$',
        }

        transaction = described_class.from_ledger_hash(hash)

        expect(transaction.currency).to eq('USD')
        expect(transaction.entries.all? { |e| e.currency == 'USD' }).to be true
      end

      it 'handles mixed currency symbols in parse_amount' do
        amount_with_dollar = '$100.00'
        amount_with_usd = '100.00 USD'
        amount_with_dollar_space = '100.00 $'

        expect(described_class.parse_amount(amount_with_dollar)).to eq(100.00)
        expect(described_class.parse_amount(amount_with_usd)).to eq(100.00)
        expect(described_class.parse_amount(amount_with_dollar_space)).to eq(100.00)
      end
    end
  end
end
