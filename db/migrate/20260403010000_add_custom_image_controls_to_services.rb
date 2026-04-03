class AddCustomImageControlsToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services,
               :use_custom_image_for_display,
               :boolean,
               null: false,
               default: false
  end
end
