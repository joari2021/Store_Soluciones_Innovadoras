class CreateProfitMarginPresetsAndLinkToProductos < ActiveRecord::Migration[7.1]
  def up
    unless table_exists?(:profit_margin_presets)
      create_table :profit_margin_presets do |t|
        t.references :business, null: false, foreign_key: true
        t.decimal :percentage, precision: 7, scale: 2, null: false

        t.timestamps
      end
    end

    unless index_exists?(:profit_margin_presets, %i[business_id percentage], unique: true)
      add_index :profit_margin_presets, %i[business_id percentage], unique: true,
                                                                    name: 'index_profit_margin_presets_on_business_and_percentage'
    end

    return if column_exists?(:productos, :profit_margin_preset_id)

    add_reference :productos, :profit_margin_preset, foreign_key: true
  end

  def down
    if column_exists?(:productos, :profit_margin_preset_id)
      remove_reference :productos, :profit_margin_preset, foreign_key: true
    end

    return unless table_exists?(:profit_margin_presets)

    if index_exists?(
      :profit_margin_presets, name: 'index_profit_margin_presets_on_business_and_percentage'
    )
      remove_index :profit_margin_presets,
                   name: 'index_profit_margin_presets_on_business_and_percentage'
    end
    drop_table :profit_margin_presets
  end
end
