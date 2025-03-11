# Teri

Teri is a double-entry accounting tool for personal banking. It helps manage banking transactions in ledger format, allowing you to code transactions, generate balance sheets, and income statements.

## Understanding Debits and Credits in Double-Entry Accounting

In double-entry accounting, every transaction is recorded in two accounts: one with a **debit (Dr.)** and one with a **credit (Cr.)**. Debits and credits reflect opposite sides of a transaction, ensuring every transaction stays balanced.

### Definitions:

- **Debit (Dr.)**: Represents the **left side** of an accounting entry.
- **Credit (Cr.)**: Represents the **right side** of an accounting entry.

**Important:**  
**Debits must always equal credits** for every transaction.

---

### Impact of Debits and Credits by Account Type:

| Account Type         | Debit (Dr.)             | Credit (Cr.)            |
|----------------------|-------------------------|-------------------------|
| **Assets**           | **Increase ⬆️**         | Decrease ⬇️             |
| **Liabilities**      | Decrease ⬇️             | **Increase ⬆️**         |
| **Equity**           | Decrease ⬇️             | **Increase ⬆️**         |
| **Income (Revenue)** | Decrease ⬇️             | **Increase ⬆️**         |
| **Expenses**         | **Increase ⬆️**         | Decrease ⬇️             |

**Mnemonic** (to remember easily): **DEALER**

- **D**ividends, **E**xpenses, **A**ssets increase with **Debit**
- **L**iabilities, **E**quity, **R**evenue increase with **Credit**

---

### Example Scenario:

1. **Invest $50,000 cash into your company**:
    - **Debit**: `Assets:Cash` **$50,000** (Cash increases)
    - **Credit**: `Equity:Owner's Capital` **$50,000** (Equity increases)

2. **Buy property for $35,000**:
    - **Debit**: `Assets:Property` **$35,000** (Property increases)
    - **Credit**: `Assets:Cash` **$35,000** (Cash decreases)

3. **Pay $1,500 for property maintenance**:
    - **Debit**: `Expenses:Maintenance` **$1,500** (Expenses increase)
    - **Credit**: `Assets:Cash` **$1,500** (Cash decreases)

4. **Receive $2,000 rental income**:
    - **Debit**: `Assets:Cash` **$2,000** (Cash increases)
    - **Credit**: `Income:Rental Income` **$2,000** (Revenue increases)

---

### Why Use Debits and Credits?

Debits and credits enforce the core accounting equation:

\[
\text{Assets} = \text{Liabilities} + \text{Equity}
\]

This ensures financial statements remain balanced, accurate, and easy to verify.

---

### Quick Summary:

- **Debit (Dr.) = Left side**: Increases Assets, Expenses; Decreases Liabilities, Equity, Income
- **Credit (Cr.) = Right side**: Increases Liabilities, Equity, Income; Decreases Assets, Expenses

Each accounting entry must balance with equal **debits and credits**.

## Ledger

```
$ ledger -f current.ledger bal ^Income ^Expenses --invert
      -13,166.68 USD  Expenses:Maintenance
$ ledger -f current.ledger bal Assets Liabilities Equity
        1,833.32 USD  Assets:Mercury Checking ••1090
      -15,000.00 USD  Equity:Capital
--------------------
      -13,166.68 USD
```

### Consistent Currency Formatting

To ensure all amounts are displayed with the same currency format (using $ symbol), use the `--exchange $` option:

```
$ ledger -f current.ledger --exchange $ bal Assets Liabilities Equity
          $1,833.32  Assets:Mercury Checking ••1090
        $-15,000.00  Equity:Capital
--------------------
        $-13,166.68
```

This option converts all currencies to dollars and displays them with the $ symbol, preventing mixed currency formats in the output.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'teri'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install teri
```

## Usage

Teri provides several commands to help you manage your banking transactions:

### Code Transactions

```bash
# Code new transactions
teri code

# Code transactions using a reconciliation file
teri code -f reconcile_example.txt

# Code transactions using saved responses
teri code -r responses.txt

# Code transactions and save responses
teri code -s new_responses.txt

# Code transactions with OpenAI suggestions
# (requires OPENAI_API_KEY environment variable or -k option)
teri code

# Code transactions with a specific OpenAI API key
teri code -k your_api_key_here

# Code transactions without OpenAI suggestions
teri code -d

# Code transactions with auto-apply for OpenAI suggestions
teri code -a
```

### AI-Assisted Transaction Coding

Teri can use OpenAI's API to suggest categories for transactions based on their details and previous codings. This feature helps streamline the coding process by providing intelligent suggestions.

#### How It Works

1. When coding a transaction, Teri sends the transaction details (description, amount, counterparty, etc.) to OpenAI's API.
2. OpenAI analyzes the transaction and suggests the most appropriate category based on the available categories and previous codings.
3. The suggestion is displayed to the user, who can choose to accept it or select a different category.
4. The user can also select option 'A' to automatically apply OpenAI's suggestions for all remaining transactions in the session.

#### Requirements

- An OpenAI API key (set as the `OPENAI_API_KEY` environment variable or provided with the `-k` option)
- The `ruby-openai` gem (included as a dependency)

#### Configuration Options

- `-k, --openai-api-key`: Specify the OpenAI API key (defaults to the `OPENAI_API_KEY` environment variable)
- `-d, --disable-ai`: Disable AI suggestions
- `-a, --auto-apply-ai`: Automatically apply AI suggestions for all transactions

#### Logging

Teri automatically logs all interactions with OpenAI and user inputs during coding sessions. This helps with:

- Debugging issues with AI suggestions
- Tracking the prompts sent to OpenAI
- Reviewing user decisions and feedback
- Auditing transaction categorization decisions

Log files are stored in the `logs` directory with timestamps in their filenames:
- `logs/coding_session_YYYYMMDD_HHMMSS.log`: Contains logs of the coding session, including user interactions and decisions
- `logs/openai_YYYYMMDD_HHMMSS.log`: Contains the detailed prompts sent to OpenAI and the responses received

The logs include:
- Transaction details
- AI suggestions and confidence levels
- User selections and feedback
- Categorization decisions

This logging system helps maintain a record of all transaction coding decisions and the AI's role in those decisions, which can be valuable for auditing and improving the system over time.

### Check Uncoded Transactions

```bash
# Check for uncoded transactions
teri check-uncoded
```

### Generate Reports

```bash
# Generate balance sheet for the last 2 years
teri balance-sheet

# Generate balance sheet for the last 5 years
teri balance-sheet -p 5

# Generate income statement for the last 2 years
teri income-statement

# Generate income statement for the last 5 years
teri income-statement -p 5
```

### Close Year

```bash
# Close the books for the previous year
teri close-year

# Close the books for a specific year
teri close-year -y 2021
```

### Fix Balance Sheet

```bash
# Fix the balance sheet
teri fix-balance
```

### Version Information

```bash
# Display version information
teri version
```

## File Structure

- `transactions/*.ledger`: Original transaction files
- `coding.ledger`: Contains reverse transactions for proper categorization

## Reconciliation File Format

You can use a reconciliation file to batch process transactions instead of coding them interactively. The file format is:

```
transaction_id,category1:amount1,category2:amount2,...
```

- If amount is not specified, the full transaction amount will be used
- For split transactions, specify multiple categories with their respective amounts
- Lines starting with # are treated as comments

Example:
```
# Single category coding
0ac547b2-8d8e-11eb-870c-ef6812d46c47,Expenses:Rent

# Split transaction
dbd348b4-8d88-11eb-8f51-5f5908fef419,Income:Sales:10000.00,Income:Services:5000.00

# Loan payment split between principal and interest
46fa4d2e-be4c-11eb-a705-afde9e1ac01b,Expenses:Loan:Principal:150.00,Expenses:Interest:28.00
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/example/teri.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). 
