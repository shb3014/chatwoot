class AddAiLearningDescriptionToLabels < ActiveRecord::Migration[7.0]
  def change
    add_column :labels, :ai_learning_description, :text
  end
end
