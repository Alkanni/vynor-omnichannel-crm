class AddContextExpansionToAiAgents < ActiveRecord::Migration[7.1]
  # Chunks keep the section of their source, so the knowledge search can send the chunks next to a match within its section
  # (#134). Every agent, existing ones included, sends one chunk on each side of a match; rolling back drops both columns.
  def change
    add_column :ai_agent_knowledge_chunks, :section, :integer
    add_column :ai_agents, :context_expansion_radius, :integer, null: false, default: 1
  end
end
