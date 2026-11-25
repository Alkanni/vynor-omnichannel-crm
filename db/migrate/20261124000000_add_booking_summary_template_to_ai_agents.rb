class AddBookingSummaryTemplateToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :booking_summary_template, :text
  end
end
