class AddPostSaleDebitAndInvoiceBreakdownFlags < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :post_sale_cost_debit, :boolean, default: false, null: false
    add_index :services, :post_sale_cost_debit

    add_column :service_product_expenses, :breakdown_in_invoice, :boolean, default: false, null: false
    add_index :service_product_expenses, :breakdown_in_invoice
  end
end
