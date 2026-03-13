class ServiceManagerExpense < ApplicationRecord
  include ServiceExpenseAmountSync

  belongs_to :service_expense_structure
  belongs_to :manager

  validates :manager_id, presence: true
end
