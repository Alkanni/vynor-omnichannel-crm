require 'rails_helper'

RSpec.describe AiAgent::Product do
  let(:ai_agent) { create(:ai_agent) }

  it 'takes the account of its AI agent' do
    expect(create(:ai_agent_product, ai_agent: ai_agent).account_id).to eq(ai_agent.account_id)
  end

  it 'validates name, description, and numbers' do
    product = build(:ai_agent_product, ai_agent: ai_agent, name: '', description: 'a' * 5_001, price: -1, weight: 1.5, stock: -2)

    expect(product).not_to be_valid
    expect(product.errors.attribute_names).to contain_exactly(:name, :description, :price, :weight, :stock)
  end

  it 'leaves price, weight, and stock blank when they are not recorded' do
    product = create(:ai_agent_product, ai_agent: ai_agent, price: nil, weight: nil, stock: nil)

    expect(product.reload).to have_attributes(price: nil, weight: nil, stock: nil)
  end

  it 'prices products in the installation currency, IDR unless set' do
    expect(described_class.currency).to eq('IDR')

    create(:installation_config, name: 'AI_AGENT_PRODUCT_CURRENCY', value: 'USD')

    expect(described_class.currency).to eq('USD')
  end

  it 'accepts image uploads' do
    product = build(:ai_agent_product, ai_agent: ai_agent)
    product.image.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')

    expect(product).to be_valid
  end

  it 'rejects non image files' do
    product = build(:ai_agent_product, ai_agent: ai_agent)
    product.image.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'sample.pdf', content_type: 'application/pdf')

    expect(product).not_to be_valid
    expect(product.errors.attribute_names).to eq([:image])
  end
end
