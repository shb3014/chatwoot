class MakeCaptainSourceTitleNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :captain_sources, :title, true
  end
end
