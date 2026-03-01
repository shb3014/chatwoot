class AddHardRulesAndPositionToLabels < ActiveRecord::Migration[7.0]
  def change
    add_column :labels, :position, :integer, default: 0, null: false
    add_column :labels, :hard_rules, :jsonb, default: [], null: false
  end
end
