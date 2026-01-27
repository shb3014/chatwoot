class DropCaptainMessageFeedbacks < ActiveRecord::Migration[7.0]
  def change
    drop_table :captain_message_feedbacks, if_exists: true
  end
end
