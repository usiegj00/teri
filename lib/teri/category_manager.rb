module Teri
  # Manages categories for accounting transactions
  class CategoryManager
    attr_reader :expense_categories, :income_categories, :asset_categories, :liability_categories, :equity_categories

    def initialize
      # Define common account categories
      @expense_categories = [
        'Expenses:Rent',
        'Expenses:Utilities',
        'Expenses:Salaries',
        'Expenses:Insurance',
        'Expenses:Office',
        'Expenses:Professional',
        'Expenses:Taxes',
        'Expenses:Interest',
        'Expenses:Maintenance',
        'Expenses:Other',
      ]

      @income_categories = [
        'Income:Sales',
        'Income:Services',
        'Income:Interest',
        'Income:Rent',
        'Income:Other',
      ]

      @asset_categories = [
        'Assets:Cash',
        'Assets:Accounts Receivable',
        'Assets:Inventory',
        'Assets:Equipment',
        'Assets:Property',
        'Assets:Other',
      ]

      @liability_categories = [
        'Liabilities:Accounts Payable',
        'Liabilities:Loans',
        'Liabilities:Mortgage',
        'Liabilities:Credit Cards',
        'Liabilities:Taxes Payable',
        'Liabilities:Other',
      ]

      @equity_categories = [
        'Equity:Capital',
        'Equity:Retained Earnings',
        'Equity:Drawings',
        'Equity:Other',
      ]
    end

    # Returns all categories combined
    def all_categories
      @expense_categories + @income_categories + @asset_categories + @liability_categories + @equity_categories
    end

    # Check if a category is valid
    def valid_category?(category)
      all_categories.include?(category)
    end

    # Get category type (expense, income, asset, liability, equity)
    def category_type(category)
      return :expense if category.start_with?('Expenses:')
      return :income if category.start_with?('Income:')
      return :asset if category.start_with?('Assets:')
      return :liability if category.start_with?('Liabilities:')
      return :equity if category.start_with?('Equity:')
      :unknown
    end

    # Add a custom category
    def add_custom_category(category)
      type = category_type(category)
      case type
      when :expense
        @expense_categories << category unless @expense_categories.include?(category)
      when :income
        @income_categories << category unless @income_categories.include?(category)
      when :asset
        @asset_categories << category unless @asset_categories.include?(category)
      when :liability
        @liability_categories << category unless @liability_categories.include?(category)
      when :equity
        @equity_categories << category unless @equity_categories.include?(category)
      end
    end
  end
end 