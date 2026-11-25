# == Schema Information
#
# Table name: ai_agent_products
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  price       :decimal(15, 2)
#  stock       :integer
#  weight      :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  ai_agent_id :bigint           not null
#
# Indexes
#
#  index_ai_agent_products_on_account_id   (account_id)
#  index_ai_agent_products_on_ai_agent_id  (ai_agent_id)
#
# Price, weight (in grams), and stock are optional: a blank one is not recorded, while 0 is (free, or sold out).
class AiAgent::Product < ApplicationRecord
  include Rails.application.routes.url_helpers

  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_IMAGE_SIZE = 5.megabytes
  DEFAULT_CURRENCY = 'IDR'.freeze

  belongs_to :account
  belongs_to :ai_agent
  has_many :promotion_products, class_name: 'AiAgent::PromotionProduct', dependent: :delete_all
  has_many :promotions, through: :promotion_products
  has_one_attached :image

  before_validation :assign_account
  # The chunk of a promotion names its products (see AiAgents::KnowledgeIndexer), so renaming or deleting one changes the
  # promotions it is linked to. Those of a deleted product are touched before its links go.
  after_update -> { promotions.touch_all }, if: :saved_change_to_name? # rubocop:disable Rails/SkipsModelValidations
  before_destroy -> { promotions.touch_all }, prepend: true # rubocop:disable Rails/SkipsModelValidations
  after_commit -> { ai_agent.schedule_training }, unless: :destroyed_by_association

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5_000 }
  validates :price, numericality: { greater_than_or_equal_to: 0, less_than: 10**13 }, allow_nil: true
  validates :weight, :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 2**31 }, allow_nil: true
  validate :acceptable_image, if: -> { image.attached? && attachment_changes['image'].present? }

  # The ISO 4217 code of every product price in the installation, from AI_AGENT_PRODUCT_CURRENCY.
  def self.currency
    AiAgents::LlmClient.setting('AI_AGENT_PRODUCT_CURRENCY') || DEFAULT_CURRENCY
  end

  def image_url
    return '' unless image.attached? && image.representable?

    url_for(image.representation(resize_to_fill: [160, 160]))
  end

  def copy_to!(target_agent)
    copy = target_agent.products.new(attributes.slice('name', 'description', 'price', 'weight', 'stock'))
    copy.image.attach(io: StringIO.new(image.download), filename: image.filename.to_s, content_type: image.content_type) if image.attached?
    copy.tap(&:save!)
  end

  private

  def assign_account
    self.account_id = ai_agent&.account_id
  end

  def acceptable_image
    errors.add(:image, 'filetype not supported') unless IMAGE_CONTENT_TYPES.include?(image.content_type)
    errors.add(:image, 'is too big') if image.byte_size > MAX_IMAGE_SIZE
  end
end
