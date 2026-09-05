class AddDraftLeaseToVentas < ActiveRecord::Migration[7.1]
  def change
    add_column :ventas, :draft_lock_user_id, :bigint
    add_column :ventas, :draft_lock_token, :string
    add_column :ventas, :draft_lock_expires_at, :datetime
    add_index :ventas, :draft_lock_token, unique: true
    add_index :ventas, :draft_lock_expires_at
    add_foreign_key :ventas, :users, column: :draft_lock_user_id
  end
end
