# No email ever leaves for an agent's address (spec agents, "Agents never
# receive email"; add-agents design.md, decision 3). The flows that would
# email an account skip agents themselves; this is the second line of
# defence, for every mailer, including ones written later. The agent domain's
# null MX record is the third.
#
# Recipients on the agent domain are removed. A message left with nobody to
# go to is not delivered, and only its mailer is logged.
module AgentMailInterceptor
  RECIPIENT_FIELDS = %i[to cc bcc].freeze

  def self.delivering_email(message)
    RECIPIENT_FIELDS.each do |field|
      addresses = Array(message.public_send(field))
      kept = addresses.reject { |address| Agent.reserved_address?(address) }
      message.public_send(:"#{field}=", kept) unless kept.size == addresses.size
    end
    return if RECIPIENT_FIELDS.any? { |field| Array(message.public_send(field)).any? }

    message.perform_deliveries = false
    Rails.logger.warn("Mail to an agent's address was not sent (#{message.delivery_handler || 'unknown mailer'})")
  end
end

ActiveSupport.on_load(:action_mailer) { register_interceptor(AgentMailInterceptor) }
