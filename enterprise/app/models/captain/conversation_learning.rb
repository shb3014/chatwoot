# == Schema Information
#
# Table name: captain_conversation_learnings
#
#  id                 :bigint           not null, primary key
#  embedding          :vector(1536)
#  issue_summary      :text
#  last_message_at    :datetime
#  learned_at         :datetime
#  quality_rating     :integer
#  resolution_summary :text
#  status             :integer          default("learned"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  assistant_id       :bigint           not null
#  conversation_id    :bigint           not null
#
# Indexes
#
#  index_captain_conversation_learnings_on_account_id       (account_id)
#  index_captain_conversation_learnings_on_assistant_id     (assistant_id)
#  index_captain_conversation_learnings_on_conversation_id  (conversation_id) UNIQUE
#  index_captain_conversation_learnings_on_embedding        (embedding) USING ivfflat
#  index_captain_conversation_learnings_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assistant_id => captain_assistants.id)
#  fk_rails_...  (conversation_id => conversations.id)
#
class Captain::ConversationLearning < ApplicationRecord
  self.table_name = 'captain_conversation_learnings'

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation, class_name: '::Conversation'

  has_neighbors :embedding, normalize: true

  enum status: { learned: 0, forgotten: 1 }

  validates :quality_rating, inclusion: { in: 0..100 }, allow_nil: true

  before_validation :ensure_account
  before_validation :ensure_assistant
  after_commit :update_embedding, on: [:create, :update]

  scope :ordered, -> { order(learned_at: :desc, updated_at: :desc) }

  def embedding_content
    [
      issue_summary.presence && "Issue: #{issue_summary}",
      resolution_summary.presence && "Resolution: #{resolution_summary}"
    ].compact.join("\n")
  end

  private

  def ensure_account
    self.account ||= conversation&.account
  end

  def ensure_assistant
    self.assistant ||= conversation&.inbox&.captain_assistant
  end

  def update_embedding
    return unless learned?
    return if embedding_content.blank?
    return unless saved_change_to_issue_summary? || saved_change_to_resolution_summary? || embedding.nil?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, embedding_content)
  end
end
