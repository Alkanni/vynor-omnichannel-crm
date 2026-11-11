class AddContextExpansionToAiAgents < ActiveRecord::Migration[7.1]
  # Chunks keep the section of their source, so the knowledge search can send the chunks next to a match within its section
  # (#134). Agents keep sending only the matches until an admin sets a Context Expansion Radius: in evals/ai-agent radius 1
  # sent the facts that smaller Context Limits missed, but at the default limit it also sent paragraphs that do not answer
  # the question, one of which misled a reply. Rolling back drops both columns.
  def change
    add_column :ai_agent_knowledge_chunks, :section, :integer
    add_column :ai_agents, :context_expansion_radius, :integer, null: false, default: 0
  end
end
