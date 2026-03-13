class AddBusinessToCoreRecords < ActiveRecord::Migration[7.1]
  def up
    add_reference :productos, :business, foreign_key: true
    add_reference :suppliers, :business, foreign_key: true
    add_reference :facturas, :business, foreign_key: true
    add_reference :accounts, :business, foreign_key: true

    business_id = ensure_default_business_id

    execute("UPDATE productos SET business_id = #{business_id} WHERE business_id IS NULL")
    execute("UPDATE suppliers SET business_id = #{business_id} WHERE business_id IS NULL")
    execute("UPDATE facturas SET business_id = #{business_id} WHERE business_id IS NULL")
    execute("UPDATE accounts SET business_id = #{business_id} WHERE business_id IS NULL")

    change_column_null :productos, :business_id, false
    change_column_null :suppliers, :business_id, false
    change_column_null :facturas, :business_id, false
    change_column_null :accounts, :business_id, false
  end

  def down
    remove_reference :productos, :business, foreign_key: true
    remove_reference :suppliers, :business, foreign_key: true
    remove_reference :facturas, :business, foreign_key: true
    remove_reference :accounts, :business, foreign_key: true
  end

  private

  def ensure_default_business_id
    existing_id = select_value("SELECT id FROM businesses ORDER BY id LIMIT 1")
    return existing_id.to_i if existing_id.present?

    execute("INSERT INTO businesses (name, created_at, updated_at) VALUES ('Principal', NOW(), NOW())")
    select_value("SELECT id FROM businesses ORDER BY id LIMIT 1").to_i
  end
end
