require 'rails_helper'

RSpec.describe CaptainMessageFeedback, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:message) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:rated_by).class_name('User') }
  end

  describe 'validations' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }
    let(:message) { create(:message, conversation: conversation, account: account) }

    it 'validates presence of rating' do
      feedback = build(:captain_message_feedback, rating: nil)
      expect(feedback).not_to be_valid
      expect(feedback.errors[:rating]).to include("can't be blank")
    end

    it 'validates rating is -1, 0, or 1' do
      expect(build(:captain_message_feedback, rating: 1)).to be_valid
      expect(build(:captain_message_feedback, rating: 0)).to be_valid
      expect(build(:captain_message_feedback, rating: -1)).to be_valid
      expect(build(:captain_message_feedback, rating: 2)).not_to be_valid
      expect(build(:captain_message_feedback, rating: -2)).not_to be_valid
    end

    it 'validates uniqueness of message_id scoped to rated_by_id' do
      create(:captain_message_feedback, message: message, rated_by: user)
      duplicate_feedback = build(:captain_message_feedback, message: message, rated_by: user)

      expect(duplicate_feedback).not_to be_valid
      expect(duplicate_feedback.errors[:message_id]).to include('already has feedback from this user')
    end

    it 'allows multiple feedback on same message from different users' do
      user2 = create(:user, account: account)
      create(:captain_message_feedback, message: message, rated_by: user)
      feedback2 = build(:captain_message_feedback, message: message, rated_by: user2)

      expect(feedback2).to be_valid
    end

    it 'validates feedback_type inclusion' do
      valid_types = %w[helpful unhelpful incorrect incomplete too_technical too_vague]
      valid_types.each do |type|
        expect(build(:captain_message_feedback, feedback_type: type)).to be_valid
      end

      expect(build(:captain_message_feedback, feedback_type: 'invalid_type')).not_to be_valid
      expect(build(:captain_message_feedback, feedback_type: nil)).to be_valid
    end

    it 'validates resolution_method inclusion' do
      valid_methods = %w[captain_solution agent_different_solution escalated]
      valid_methods.each do |method|
        expect(build(:captain_message_feedback, resolution_method: method)).to be_valid
      end

      expect(build(:captain_message_feedback, resolution_method: 'invalid_method')).not_to be_valid
      expect(build(:captain_message_feedback, resolution_method: nil)).to be_valid
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }

    before do
      create(:captain_message_feedback, rating: 1, feedback_type: 'helpful')
      create(:captain_message_feedback, rating: -1, feedback_type: 'unhelpful')
      create(:captain_message_feedback, rating: 0, feedback_type: 'incomplete')
      create(:captain_message_feedback, rating: 1, feedback_type: 'incorrect', issue_resolved: true)
      create(:captain_message_feedback, rating: -1, feedback_type: 'too_vague', issue_resolved: false)
    end

    describe '.positive' do
      it 'returns feedbacks with positive rating' do
        expect(described_class.positive.count).to eq(2)
        expect(described_class.positive.pluck(:rating).uniq).to eq([1])
      end
    end

    describe '.negative' do
      it 'returns feedbacks with negative rating' do
        expect(described_class.negative.count).to eq(2)
        expect(described_class.negative.pluck(:rating).uniq).to eq([-1])
      end
    end

    describe '.neutral' do
      it 'returns feedbacks with neutral rating' do
        expect(described_class.neutral.count).to eq(1)
        expect(described_class.neutral.first.rating).to eq(0)
      end
    end

    describe '.helpful' do
      it 'returns helpful feedbacks' do
        expect(described_class.helpful.count).to eq(1)
        expect(described_class.helpful.first.feedback_type).to eq('helpful')
      end
    end

    describe '.unhelpful' do
      it 'returns unhelpful feedbacks' do
        expect(described_class.unhelpful.count).to eq(1)
        expect(described_class.unhelpful.first.feedback_type).to eq('unhelpful')
      end
    end

    describe '.resolved' do
      it 'returns feedbacks where issue was resolved' do
        expect(described_class.resolved.count).to eq(1)
        expect(described_class.resolved.first.issue_resolved).to be true
      end
    end

    describe '.unresolved' do
      it 'returns feedbacks where issue was not resolved' do
        expect(described_class.unresolved.count).to eq(1)
        expect(described_class.unresolved.first.issue_resolved).to be false
      end
    end

    describe '.recent' do
      it 'returns feedbacks ordered by created_at descending' do
        feedbacks = described_class.recent
        expect(feedbacks.first.created_at).to be >= feedbacks.last.created_at
      end
    end
  end

  describe 'callbacks' do
    describe 'after_create :log_feedback_creation' do
      let(:account) { create(:account) }
      let(:user) { create(:user, account: account) }
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, inbox: inbox, account: account) }
      let(:message) { create(:message, conversation: conversation, account: account) }

      it 'logs feedback creation' do
        allow(Captain::Logger).to receive(:info)

        feedback = create(:captain_message_feedback,
                          message: message,
                          conversation: conversation,
                          rated_by: user,
                          rating: 1,
                          feedback_type: 'helpful')

        expect(Captain::Logger).to have_received(:info).with(
          '[CaptainMessageFeedback] Feedback created',
          hash_including(
            feedback_id: feedback.id,
            message_id: message.id,
            conversation_id: conversation.id,
            rated_by_id: user.id,
            rating: 1,
            feedback_type: 'helpful'
          )
        )
      end
    end
  end

  describe 'factory' do
    it 'creates valid captain_message_feedback object' do
      feedback = create(:captain_message_feedback)
      expect(feedback).to be_valid
      expect(feedback.rating).to be_in([-1, 0, 1])
      expect(feedback.message).to be_present
      expect(feedback.conversation).to be_present
      expect(feedback.rated_by).to be_present
    end

    it 'creates feedback with all attributes' do
      feedback = create(:captain_message_feedback,
                        rating: 1,
                        feedback_type: 'helpful',
                        notes: 'Great response!',
                        issue_resolved: true,
                        resolution_method: 'captain_solution')

      expect(feedback.rating).to eq(1)
      expect(feedback.feedback_type).to eq('helpful')
      expect(feedback.notes).to eq('Great response!')
      expect(feedback.issue_resolved).to be true
      expect(feedback.resolution_method).to eq('captain_solution')
    end
  end
end
