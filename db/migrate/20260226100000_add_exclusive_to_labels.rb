class AddExclusiveToLabels < ActiveRecord::Migration[7.0]
  def change
    add_column :labels, :exclusive, :boolean, default: false, null: false
  end
end
