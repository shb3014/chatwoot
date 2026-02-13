# == Schema Information
#
# Table name: captain_sources
#
#  id            :bigint           not null, primary key
#  content       :text
#  embedding     :vector(1536)
#  external_link :string
#  metadata      :jsonb
#  source_type   :integer          default("web_url"), not null
#  status        :integer          default("pending"), not null
#  title         :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_captain_sources_on_account_and_link  (account_id,external_link) UNIQUE WHERE (external_link IS NOT NULL)
#  index_captain_sources_on_account_id        (account_id)
#  index_captain_sources_on_source_type       (source_type)
#  index_captain_sources_on_status            (status)
#  vector_idx_captain_sources_embedding       (embedding) USING ivfflat
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Captain::Source < ApplicationRecord
  self.table_name = 'captain_sources'

  belongs_to :account
  has_one_attached :pdf_file
  has_neighbors :embedding, normalize: true

  enum source_type: { web_url: 0, pdf: 1, private_article: 2 }
  enum status: { pending: 0, processing: 1, active: 2, failed: 3 }

  validates :title, presence: true, if: :private_article?
  validates :external_link, presence: true, if: :web_url?
  validates :external_link, uniqueness: { scope: :account_id }, allow_blank: true
  validates :content, presence: true, if: :private_article?
  validates :content, length: { maximum: 200_000 }
  validate :validate_pdf_format, if: :pdf?
  validate :validate_file_attachment, if: -> { pdf_file.attached? }

  before_validation :set_external_link_for_pdf
  before_validation :infer_title_if_blank

  after_create_commit :enqueue_processing_job, unless: :private_article?
  after_create_commit :enqueue_initial_embedding_job, if: :private_article?
  after_update_commit :enqueue_embedding_job, if: :should_update_embedding?

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(source_type: type) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def self.search(query)
    embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)
    where(status: :active)
      .nearest_neighbors(:embedding, embedding, distance: 'cosine')
      .limit(5)
  end

  def embedding_content
    "#{title}\n#{content}".truncate(8000)
  end

  def recrawl!
    return if private_article?

    update!(status: :pending, content: nil, embedding: nil)
    Captain::Sources::ProcessJob.perform_later(self)
  end

  private

  def infer_title_if_blank
    return if title.present?

    self.title = if web_url?
                   begin
                     URI.parse(external_link).host
                   rescue StandardError
                     external_link
                   end
                 elsif pdf? && pdf_file.attached?
                   pdf_file.filename.base.tr('_-', ' ').titleize
                 else
                   'Untitled'
                 end
  end

  def enqueue_processing_job
    Captain::Sources::ProcessJob.perform_later(self)
  end

  def enqueue_initial_embedding_job
    Captain::Llm::UpdateEmbeddingJob.perform_later(self, embedding_content)
  end

  def enqueue_embedding_job
    Captain::Llm::UpdateEmbeddingJob.perform_later(self, embedding_content)
  end

  def should_update_embedding?
    (saved_change_to_title? || saved_change_to_content?) && content.present?
  end

  def validate_pdf_format
    return unless pdf_file.attached?

    errors.add(:pdf_file, I18n.t('captain.sources.pdf_format_error')) unless pdf_file.blob.content_type == 'application/pdf'
  end

  def validate_file_attachment
    return unless pdf_file.attached?
    return unless pdf_file.blob.byte_size > 10.megabytes

    errors.add(:pdf_file, I18n.t('captain.sources.pdf_size_error'))
  end

  def set_external_link_for_pdf
    return unless pdf? && pdf_file.attached? && external_link.blank?

    timestamp = Time.current.strftime('%Y%m%d%H%M%S')
    self.external_link = "PDF:#{pdf_file.filename.base}_#{timestamp}"
  end
end
