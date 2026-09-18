class AddScansoloEnabledFlagToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :scansolo_feature_flags, :bigint, default: 0, null: false
  end
end
