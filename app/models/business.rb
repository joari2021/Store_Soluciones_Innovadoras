class Business < ApplicationRecord
  has_many :productos, dependent: :destroy
  has_many :suppliers, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :purchase_invoices, class_name: 'PurchaseInvoice', foreign_key: :business_id, dependent: :destroy
  has_many :clientes, dependent: :destroy
  has_many :ventas, dependent: :destroy
  has_many :venta_payments, through: :ventas
  has_many :expenses, dependent: :destroy
  has_many :expense_payments, through: :expenses
  has_many :debts, dependent: :destroy
  has_many :debt_payments, through: :debts

  validates :name, presence: true

  after_create :ensure_special_accounts

  private

  def ensure_special_accounts
    Account.ensure_special_accounts!(self)
  end
end
