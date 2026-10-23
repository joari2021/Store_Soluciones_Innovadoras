class BeerTicketSettingProduct < ApplicationRecord
  belongs_to :beer_ticket_setting
  belongs_to :producto

  validates :producto_id, uniqueness: { scope: :beer_ticket_setting_id }
end
