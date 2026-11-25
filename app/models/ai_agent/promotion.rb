# == Schema Information
#
# Table name: ai_agent_promotions
#
#  id          :bigint           not null, primary key
#  description :text             not null
#  ends_on     :date
#  starts_on   :date
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  ai_agent_id :bigint           not null
#
# Indexes
#
#  index_ai_agent_promotions_on_account_id   (account_id)
#  index_ai_agent_promotions_on_ai_agent_id  (ai_agent_id)
#
# A promotion is valid from starts_on to ends_on in the agent's timezone, both days included, and a blank date leaves
# that side open. Its status follows from the dates, so it is archived on the day after it ends without any job, and
# active again once its end date moves. Only active promotions reach the model (see AiAgents::KnowledgeRetriever), and
# archived ones are not indexed (see AiAgents::KnowledgeIndexer).
class AiAgent::Promotion < ApplicationRecord
  STATUSES = %w[active scheduled archived].freeze

  belongs_to :account
  belongs_to :ai_agent
  has_many :promotion_products, class_name: 'AiAgent::PromotionProduct', dependent: :delete_all
  has_many :products, through: :promotion_products

  before_validation :assign_account
  after_commit -> { ai_agent.schedule_training }, unless: :destroyed_by_association

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 5_000 }
  validate -> { errors.add(:ends_on, I18n.t('ai_agents.promotions.errors.ends_before_start')) },
           if: -> { starts_on && ends_on && ends_on < starts_on }

  # The promotions with a status on a date.
  scope :status_on, lambda { |status, date|
    case status
    when 'active' then where(starts_on: [nil, ..date], ends_on: [nil, date..])
    when 'scheduled' then where(starts_on: date.next_day..)
    when 'archived' then where(ends_on: ...date)
    end
  }

  def status(date = ai_agent.current_date)
    if starts_on&.after?(date)
      'scheduled'
    elsif ends_on&.before?(date)
      'archived'
    else
      'active'
    end
  end

  # The chunk names the linked products, so linking or unlinking one changes the promotion (see AiAgents::KnowledgeIndexer).
  def products=(records)
    self.updated_at = Time.current if persisted? && records.map(&:id).sort != product_ids.sort
    super
  end

  # product_copies: the copy of each product of the agent by the id of the product.
  def copy_to!(target_agent, product_copies)
    target_agent.promotions.create!(attributes.slice('title', 'description', 'starts_on', 'ends_on')
                                              .merge('products' => product_copies.values_at(*product_ids)))
  end

  private

  def assign_account
    self.account_id = ai_agent&.account_id
  end
end
