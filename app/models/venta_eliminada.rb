class VentaEliminada < ApplicationRecord
  self.table_name = 'venta_eliminadas'

  belongs_to :business
  belongs_to :venta, optional: true
  belongs_to :seller_user, class_name: 'User', optional: true
  belongs_to :cashier_user, class_name: 'User', optional: true
  belongs_to :cliente, optional: true
  belongs_to :deleted_by_user, class_name: 'User', optional: true

  validates :business_id, presence: true
  validates :deleted_at, presence: true
end
