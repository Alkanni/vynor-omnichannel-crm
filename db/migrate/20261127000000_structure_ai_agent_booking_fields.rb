# Booking fields become objects (see AiAgent::BookingFields): each name a text field without description, options, or
# requirement, which the AI fills as before. Going down keeps only the names, as the code before this migration reads them,
# so it runs before rolling the image back.
class StructureAiAgentBookingFields < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agents, :booking_services, :jsonb, default: [], null: false
    execute <<~SQL.squish
      UPDATE ai_agents SET booking_fields = (
        SELECT jsonb_agg(
          jsonb_build_object('name', name, 'description', '', 'type', 'text', 'options', '[]'::jsonb, 'required', false) ORDER BY position
        )
        FROM jsonb_array_elements_text(booking_fields) WITH ORDINALITY AS fields(name, position)
      )
      WHERE booking_fields <> '[]'::jsonb
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE ai_agents SET booking_fields = (
        SELECT jsonb_agg(field -> 'name' ORDER BY position) FROM jsonb_array_elements(booking_fields) WITH ORDINALITY AS fields(field, position)
      )
      WHERE booking_fields <> '[]'::jsonb
    SQL
    remove_column :ai_agents, :booking_services
  end
end
