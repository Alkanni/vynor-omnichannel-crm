# == Schema Information
#
# Table name: ai_agent_products
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  price       :decimal(15, 2)   default(0.0), not null
#  stock       :integer          default(0), not null
#  weight      :integer          default(0), not null
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
class AiAgent::Product < ApplicationRecord
  include Rails.application.routes.url_helpers

  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_IMAGE_SIZE = 5.megabytes

  belongs_to :account
  belongs_to :ai_agent
  has_one_attached :image

  before_validation :assign_account
  after_commit -> { ai_agent.schedule_training }, unless: :destroyed_by_association

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5_000 }
  validates :price, numericality: { greater_than_or_equal_to: 0, less_than: 10**13 }
  validates :weight, :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 2**31 }
  validate :acceptable_image, if: -> { image.attached? && attachment_changes['image'].present? }

  def image_url
    return '' unless image.attached? && image.representable?

    url_for(image.representation(resize_to_fill: [160, 160]))
  end

  def copy_to!(target_agent)
    copy = target_agent.products.new(attributes.slice('name', 'description', 'price', 'weight', 'stock'))
    copy.image.attach(io: StringIO.new(image.download), filename: image.filename.to_s, content_type: image.content_type) if image.attached?
    copy.save!
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
