require 'rails_helper'

RSpec.describe AiAgent::Promotion do
  let(:ai_agent) { create(:ai_agent, timezone: 'Asia/Jakarta') }

  it 'takes the account of its AI agent' do
    expect(create(:ai_agent_promotion, ai_agent: ai_agent).account_id).to eq(ai_agent.account_id)
  end

  it 'validates title, description, and an end date on or after the start date' do
    promotion = build(:ai_agent_promotion, ai_agent: ai_agent, title: '', description: '', starts_on: Date.new(2026, 11, 10),
                                           ends_on: Date.new(2026, 11, 9))

    expect(promotion).not_to be_valid
    expect(promotion.errors.attribute_names).to contain_exactly(:title, :description, :ends_on)
    expect(build(:ai_agent_promotion, ai_agent: ai_agent, starts_on: Date.new(2026, 11, 10), ends_on: Date.new(2026, 11, 10))).to be_valid
    expect(build(:ai_agent_promotion, ai_agent: ai_agent, title: 'a' * 256, description: 'a' * 5_001)).not_to be_valid
  end

  describe '#status' do
    it 'is active through the end date in the timezone of the AI agent and archived from the next day' do
      promotion = create(:ai_agent_promotion, ai_agent: ai_agent, ends_on: Date.new(2026, 11, 30))

      # 23:59 on 30 November in Jakarta is 16:59 UTC, and 00:00 on 1 December is 17:00 UTC on 30 November.
      travel_to(Time.utc(2026, 11, 30, 16, 59)) { expect(promotion.status).to eq('active') }
      travel_to(Time.utc(2026, 11, 30, 17, 0)) { expect(promotion.status).to eq('archived') }
    end

    it 'is scheduled before the start date and active from it' do
      promotion = create(:ai_agent_promotion, ai_agent: ai_agent, starts_on: Date.new(2026, 12, 1))

      travel_to(Time.utc(2026, 11, 30, 16, 59)) { expect(promotion.status).to eq('scheduled') }
      travel_to(Time.utc(2026, 11, 30, 17, 0)) { expect(promotion.status).to eq('active') }
    end

    it 'is always active without dates' do
      expect(create(:ai_agent_promotion, ai_agent: ai_agent).status(Date.new(2030, 1, 1))).to eq('active')
    end
  end

  describe '.status_on' do
    it 'finds the promotions with each status on a date' do
      date = Date.new(2026, 11, 25)
      always = create(:ai_agent_promotion, ai_agent: ai_agent)
      running = create(:ai_agent_promotion, ai_agent: ai_agent, starts_on: date, ends_on: date)
      scheduled = create(:ai_agent_promotion, ai_agent: ai_agent, starts_on: date + 1)
      archived = create(:ai_agent_promotion, ai_agent: ai_agent, ends_on: date - 1)

      expect(described_class.status_on('active', date)).to contain_exactly(always, running)
      expect(described_class.status_on('scheduled', date)).to contain_exactly(scheduled)
      expect(described_class.status_on('archived', date)).to contain_exactly(archived)
    end
  end

  describe '#products=' do
    it 'changes the promotion when its products change, so the next indexing rewrites its chunk' do
      products = create_list(:ai_agent_product, 2, ai_agent: ai_agent)
      promotion = create(:ai_agent_promotion, ai_agent: ai_agent, products: products)

      expect { promotion.update!(products: products.reverse) }.not_to change(promotion, :updated_at)
      expect { promotion.update!(products: products.first(1)) }.to change(promotion, :updated_at)
      expect(promotion.reload.products).to eq(products.first(1))
    end
  end
end
