class ServiceVariableExpense < ApplicationRecord
  include ServiceExpenseAmountSync

  belongs_to :service_expense_structure

  validates :description, presence: true
end
