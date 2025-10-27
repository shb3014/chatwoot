class AddBubbleAnimationsToChannelWebWidgets < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_web_widgets, :bubble_animations_config, :jsonb, default: {}
  end
end

