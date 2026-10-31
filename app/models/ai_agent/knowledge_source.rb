# == Schema Information
#
# Table name: ai_agent_knowledge_sources
#
#  id            :bigint           not null, primary key
#  content       :text
#  error_message :string
#  external_url  :text
#  metadata      :jsonb            not null
#  source_type   :integer          not null
#  status        :integer          default("ready"), not null
#  title         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  ai_agent_id   :bigint           not null
#
# Indexes
#
#  index_ai_agent_knowledge_sources_on_account_id      (account_id)
#  index_ai_agent_knowledge_sources_on_agent_and_type  (ai_agent_id,source_type)
#
class AiAgent::KnowledgeSource < ApplicationRecord
  MAX_EXTRACTED_CHARACTERS = 500_000
  MAX_FILE_SIZE = 100.megabytes
  FILE_CONTENT_TYPES = {
    '.pdf' => %w[application/pdf],
    '.doc' => %w[application/msword application/x-ole-storage],
    '.docx' => %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document],
    '.txt' => %w[text/plain],
    '.md' => %w[text/markdown text/x-markdown text/plain]
  }.freeze

  belongs_to :account
  belongs_to :ai_agent
  has_one_attached :file

  enum :source_type, { text: 0, qa: 1, website: 2, file: 3 }, validate: true
  enum :status, { ready: 0, pending: 1, processing: 2, failed: 3 }

  before_validation :assign_account
  before_validation :prepare_external_source, on: :create

  validates :title, presence: true
  validates :title, length: { maximum: 255 }, if: :text?
  validates :content, length: { maximum: 100_000 }, if: :text?
  validates :title, length: { maximum: 1_000 }, if: :qa?
  validates :content, presence: true, length: { maximum: 5_000 }, if: :qa?
  validates :external_url, presence: true, length: { maximum: 2_048 }, if: :website?
  validates :external_url, uniqueness: { scope: :ai_agent_id }, if: :website?
  validate :external_url_is_http, if: :website?
  validate :acceptable_file, if: :file?
  validate :file_only_on_file_sources
  validates :content, length: { maximum: MAX_EXTRACTED_CHARACTERS }, if: -> { website? || file? }

  after_create_commit :enqueue_processing, if: :pending?
  after_commit -> { ai_agent.schedule_training }, unless: :destroyed_by_association

  def resync!
    update!(status: :pending, error_message: nil)
    enqueue_processing
  end

  def store_extracted!(content, title: self.title)
    update!(title: title, content: content.first(MAX_EXTRACTED_CHARACTERS), status: :ready,
            metadata: metadata.merge('truncated' => content.length > MAX_EXTRACTED_CHARACTERS))
  end

  # nil until the source has chunks (see AiAgent::KnowledgeChunk.index_summaries).
  def index_summary
    ai_agent.knowledge_chunks.where(chunkable: self).index_summaries(AiAgents::LlmClient.embedding_model)[id]
  end

  def copy_to!(target_agent)
    copy = target_agent.knowledge_sources.new(
      attributes.slice('source_type', 'title', 'content', 'external_url', 'status', 'error_message', 'metadata')
    )
    return copy.save! unless file.attached?

    file.open do |tempfile|
      copy.file.attach(io: File.open(tempfile.path), filename: file.filename.to_s, content_type: file.content_type)
      copy.save!
    end
  end

  private

  def assign_account
    self.account_id = ai_agent&.account_id
  end

  def prepare_external_source
    return unless website? || file?

    self.status = :pending if content.blank?
    self.title = default_title if title.blank?
  end

  def default_title
    return external_url if website?

    file.filename.to_s if file.attached?
  end

  def enqueue_processing
    AiAgents::ProcessKnowledgeSourceJob.perform_later(self)
  end

  def external_url_is_http
    uri = URI.parse(external_url.to_s)
    errors.add(:external_url, :invalid) unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::Error
    errors.add(:external_url, :invalid)
  end

  def file_only_on_file_sources
    errors.add(:file, :present) if file.attached? && !file?
  end

  def acceptable_file
    return errors.add(:file, :blank) unless file.attached?

    allowed_types = FILE_CONTENT_TYPES[File.extname(file.filename.to_s).downcase]
    errors.add(:file, 'type is not supported') unless allowed_types&.include?(file.content_type)
    errors.add(:file, 'is too big') if file.byte_size > MAX_FILE_SIZE
  end
end
