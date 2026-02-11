module Labelable
  extend ActiveSupport::Concern

  included do
    acts_as_taggable_on :labels
  end

  def update_labels(labels = nil)
    update!(label_list: labels)
  end

  def add_labels(new_labels = nil)
    return if new_labels.blank?

    new_labels = Array(new_labels).map(&:to_s)
    current_labels = label_list.map(&:to_s)
    combined_labels = (current_labels + new_labels).uniq
    update!(label_list: combined_labels)
  end
end
