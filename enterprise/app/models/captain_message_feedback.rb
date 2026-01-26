# == Schema Information
#
# Table name: captain_message_feedbacks
#
#  id                :bigint           not null, primary key
#  feedback_type     :string
#  issue_resolved    :boolean
#  notes             :text
#  rating            :integer          not null
#  resolution_method :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  conversation_id   :bigint           not null
#  message_id        :bigint           not null
#  rated_by_id       :bigint           not null
#
# Indexes
#
#  index_captain_feedbacks_on_message_and_rater        (message_id,rated_by_id) UNIQUE
#  index_captain_message_feedbacks_on_conversation_id  (conversation_id)
#  index_captain_message_feedbacks_on_message_id       (message_id)
#  index_captain_message_feedbacks_on_rated_by_id      (rated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (rated_by_id => users.id)
#
class CaptainMessageFeedback < ApplicationRecord
  # Associations
  belongs_to :message
  belongs_to :conversation
  belongs_to :rated_by, class_name: 'User'

  # Validations
  validates :rating, presence: true, inclusion: { in: [-1, 0, 1] }
  validates :message_id, uniqueness: { scope: :rated_by_id, message: 'already has feedback from this user' }
  validates :feedback_type, inclusion: {
    in: %w[helpful unhelpful incorrect incomplete too_technical too_vague],
    allow_nil: true
  }
  validates :resolution_method, inclusion: {
    in: %w[captain_solution agent_different_solution escalated],
    allow_nil: true
  }

  # Enums (we'll use string columns with validation instead of Rails enums for flexibility)

  # Scopes
  scope :positive, -> { where('rating > 0') }
  scope :negative, -> { where('rating < 0') }
  scope :neutral, -> { where(rating: 0) }
  scope :helpful, -> { where(feedback_type: 'helpful') }
  scope :unhelpful, -> { where(feedback_type: 'unhelpful') }
  scope :resolved, -> { where(issue_resolved: true) }
  scope :unresolved, -> { where(issue_resolved: false) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :log_feedback_creation

  private

  def log_feedback_creation
    Captain::Logger.info(
      '[CaptainMessageFeedback] Feedback created',
      feedback_id: id,
      message_id: message_id,
      conversation_id: conversation_id,
      rated_by_id: rated_by_id,
      rating: rating,
      feedback_type: feedback_type
    )
  end
end
