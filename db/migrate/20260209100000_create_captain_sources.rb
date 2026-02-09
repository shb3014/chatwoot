class CreateCaptainSources < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_sources do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :source_type, null: false, default: 0
      t.string :title, null: false
      t.text :content
      t.string :external_link
      t.integer :status, null: false, default: 0
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :captain_sources, :source_type
    add_index :captain_sources, :status
    add_index :captain_sources, [:account_id, :external_link], unique: true,
                                                               where: 'external_link IS NOT NULL',
                                                               name: 'index_captain_sources_on_account_and_link'
    add_index :captain_sources, :embedding, using: :ivfflat, name: 'vector_idx_captain_sources_embedding'
  end
end
