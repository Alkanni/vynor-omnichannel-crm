require 'rails_helper'

RSpec.describe BillingHelper do
  describe '#default_plan?' do
    let(:account) { create(:account, custom_attributes: { 'plan_name' => 'Hacker' }) }

    before do
      create(:installation_config, {
               name: 'CHATWOOT_CLOUD_PLANS',
               value: [
                 {
                   'name' => 'Hacker',
                   'product_id' => ['plan_id'],
                   'price_ids' => ['price_1']
                 },
                 {
                   'name' => 'Startups',
                   'product_id' => ['plan_id_2'],
                   'price_ids' => ['price_2']
                 }
               ]
             })
    end

    it 'returns true for the default plan name' do
      expect(helper.send(:default_plan?, account)).to be(true)
      account.custom_attributes['plan_name'] = 'Startups'
      expect(helper.send(:default_plan?, account)).to be(false)
    end
  end
end
