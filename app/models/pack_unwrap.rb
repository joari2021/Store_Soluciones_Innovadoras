class PackUnwrap < ApplicationRecord
  belongs_to :business
  belongs_to :pack_producto, class_name: 'Producto'
  belongs_to :unit_producto, class_name: 'Producto'
  belongs_to :user
  has_many :pack_unwrap_items, dependent: :destroy

  validates :cant_presentation, numericality: { only_integer: true, greater_than: 0 }
  validates :performed_on, :performed_at, presence: true
  validates :total_packs_opened, :total_units_created,
            numericality: { greater_than_or_equal_to: 0 }
end
