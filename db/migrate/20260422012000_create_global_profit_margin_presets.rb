class CreateGlobalProfitMarginPresets < ActiveRecord::Migration[7.1]
  def change
    create_table :global_profit_margin_presets do |t|
      t.decimal :percentage, precision: 7, scale: 2, null: false

      t.timestamps
    end

    add_index :global_profit_margin_presets, :percentage, unique: true
  end
end
