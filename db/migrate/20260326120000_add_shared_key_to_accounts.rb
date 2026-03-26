class AddSharedKeyToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :shared_key, :string
    add_index :accounts, :shared_key

    Account.reset_column_information
    Business.reset_column_information

    master_business = Business.order(:created_at).first
    return if master_business.blank?

    master_accounts = master_business.accounts.order(:id).to_a
    master_accounts.each do |account|
      next if account.shared_key.present?

      account.update_columns(shared_key: SecureRandom.uuid)
    end

    Business.where.not(id: master_business.id).find_each do |business|
      master_accounts.each do |master_account|
        target = business.accounts.find_by(
          name: master_account.name,
          account_type: master_account.account_type,
          currency: master_account.currency
        )

        if target.present?
          target.update_columns(
            shared_key: master_account.shared_key,
            name: master_account.name,
            account_type: master_account.account_type,
            currency: master_account.currency,
            theme_color: master_account.theme_color,
            notes: master_account.notes
          )
        else
          target = business.accounts.create!(
            shared_key: master_account.shared_key,
            name: master_account.name,
            account_type: master_account.account_type,
            currency: master_account.currency,
            theme_color: master_account.theme_color,
            notes: master_account.notes,
            balance: 0,
            active: false,
            is_primary: false
          )
        end

        target.logo.attach(master_account.logo.blob) if master_account.logo.attached? && !target.logo.attached?

        if master_account.payment_method_image.attached? && !target.payment_method_image.attached?
          target.payment_method_image.attach(master_account.payment_method_image.blob)
        end
      end
    end

    Account.where(shared_key: nil).find_each do |account|
      account.update_columns(shared_key: SecureRandom.uuid)
    end

    change_column_null :accounts, :shared_key, false
  end

  def down
    remove_index :accounts, :shared_key
    remove_column :accounts, :shared_key
  end
end
