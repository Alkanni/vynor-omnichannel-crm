# == Schema Information
#
# Table name: ai_agent_knowledge_sources
#
#  id          :bigint           not null, primary key
#  content     :text
#  source_type :integer          not null
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  ai_agent_id :bigint           not null
#
# Indexes
#
#  index_ai_agent_knowledge_sources_on_account_id      (account_id)
#  index_ai_agent_knowledge_sources_on_agent_and_type  (ai_agent_id,source_type)
#
class AiAgent::KnowledgeSource < ApplicationRecord
  belongs_to :account
  belongs_to :ai_agent

  enum :source_type, { text: 0, qa: 1 }, validate: true

  before_validation :assign_account

  validates :title, presence: true
  validates :title, length: { maximum: 255 }, if: :text?
  validates :content, length: { maximum: 100_000 }, if: :text?
  validates :title, length: { maximum: 1_000 }, if: :qa?
  validates :content, presence: true, length: { maximum: 5_000 }, if: :qa?

  private

  def assign_account
    self.account_id = ai_agent&.account_id
  end
end
