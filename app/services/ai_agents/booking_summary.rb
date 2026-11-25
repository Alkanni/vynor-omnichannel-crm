# The booking summary of an agent with a summary template (AiAgent#booking_summary_template): instead of writing the
# summary that the customer confirms, the reply model sets "show_booking_summary" and fills in the booking (see
# AiAgents::ActionSchema#summary_request), and the summary rendered from the template becomes the last bubble of the
# reply, with the name the booking would be recorded with (see Booking.ai_customer_name). Only replies have it: the
# Watcher sends no messages. A reply that hands off or fails the reply check shows none, and the summary itself is not
# checked, since it shows the booking for the customer to confirm. The playground has no conversation, so its summary
# has none of the conversation's variables.
class AiAgents::BookingSummary
  FIELD = 'show_booking_summary'.freeze
  INSTRUCTIONS = <<~TEXT.freeze
    For this agent, the summary comes from a template that is sent after your messages and asks the customer to confirm
    it. Never write a summary or ask the customer to confirm a booking in "messages". Whenever you would read the summary,
    also after the customer changes the service, date, or time, set "show_booking_summary" to true, fill "booking" with
    its values, as for a booking, and put only one short line without any booking detail or question in "messages", such
    as "Baik, Kak.". Set "show_booking_summary" to false otherwise, also when "create_booking" is true.
  TEXT

  # conversation: the conversation of the reply, nil in the playground; actions: its AiAgents::ActionSchema.
  pattr_initialize [:ai_agent!, :conversation, :actions!]

  # The AiAgents::ReplyGenerator::Reply with the summary its content asked for as its last bubble, or with why that
  # booking cannot be one.
  def add_to(reply, content)
    return reply if reply.handoff || reply.trace.validation&.knowledge_gap?

    request = actions.summary_request(content)
    return reply.with(booking_summary_rejection: request[:booking_rejection]) unless request[:booking]

    summary = render(request[:booking])
    reply.with(messages: [*reply.messages.first(AiAgents::ReplyGenerator::MAX_REPLY_MESSAGES - 1), summary], booking_summary: summary)
  end

  private

  def render(attributes)
    booking = Booking.new(account: ai_agent.account, ai_agent: ai_agent, conversation: conversation, **attributes)
    booking.customer_name = Booking.ai_customer_name(booking.customer_name, conversation&.contact)
    booking.render_message(ai_agent.booking_summary_template)
  end
end
