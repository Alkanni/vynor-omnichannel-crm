# Price, weight, and stock of an AI Agent product are optional, so a product that does not record them is not sent to the
# model as costing, weighing, or stocking 0. Weight 0 means nothing, so it becomes blank; price and stock 0 may mean free
# or sold out, so they stay (owner decision Q1 on #121). Rolling back fills blanks with 0 again.
class MakeAiAgentProductNumbersOptional < ActiveRecord::Migration[7.1]
  COLUMNS = %i[price weight stock].freeze

  def up
    change_table :ai_agent_products, bulk: true do |t|
      COLUMNS.each do |column|
        t.change_null column, true
        t.change_default column, from: 0, to: nil
      end
    end
    execute 'UPDATE ai_agent_products SET weight = NULL WHERE weight = 0'
  end

  def down
    execute 'UPDATE ai_agent_products SET price = COALESCE(price, 0), weight = COALESCE(weight, 0), stock = COALESCE(stock, 0)'
    change_table :ai_agent_products, bulk: true do |t|
      COLUMNS.each do |column|
        t.change_default column, from: nil, to: 0
        t.change_null column, false
      end
    end
  end
end
