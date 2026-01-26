FactoryBot.define do
  factory :captain_message_feedback do
    association :message
    association :conversation
    association :rated_by, factory: :user

    rating { [1, 0, -1].sample }
    feedback_type { %w[helpful unhelpful incorrect incomplete too_technical too_vague].sample }
    notes { nil }
    issue_resolved { nil }
    resolution_method { nil }

    trait :positive do
      rating { 1 }
      feedback_type { 'helpful' }
    end

    trait :negative do
      rating { -1 }
      feedback_type { 'unhelpful' }
    end

    trait :neutral do
      rating { 0 }
      feedback_type { 'incomplete' }
    end

    trait :with_resolution do
      issue_resolved { true }
      resolution_method { 'captain_solution' }
    end

    trait :escalated do
      issue_resolved { false }
      resolution_method { 'escalated' }
    end

    trait :with_notes do
      notes { Faker::Lorem.sentence }
    end
  end
end
