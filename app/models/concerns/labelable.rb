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

    # When the conversation already carries an exclusive label, reject all additions.
    return if has_exclusive_label?

    new_labels = Array(new_labels).map(&:to_s)
    current_labels = label_list.map(&:to_s)
    combined_labels = (current_labels + new_labels).uniq
    update!(label_list: combined_labels)
  end

  # Returns true when any of the conversation's current labels is marked exclusive.
  def has_exclusive_label?
    return false unless respond_to?(:account)

    current_titles = label_list.map { |l| l.to_s.downcase }
    return false if current_titles.empty?

    account.labels.where(exclusive: true)
           .where('LOWER(title) IN (?)', current_titles)
           .exists?
  end
end
