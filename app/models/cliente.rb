class Cliente < ApplicationRecord
  DOCUMENT_TYPES = %w[V E J G].freeze

  belongs_to :business
  has_many :ventas, dependent: :nullify
  has_many :debts, foreign_key: :cliente_id, dependent: :nullify

  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
  validates :name, presence: true

  def document_label
    return document_type if document_number.blank?

    "#{document_type}-#{document_number}"
  end
end
