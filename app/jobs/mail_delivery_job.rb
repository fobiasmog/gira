require "net/smtp"

# Delivers every email in the background and retries transient SMTP and
# network failures with growing delays (spec notifications, "Emails are sent
# in the background").
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  TRANSIENT_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Net::SMTPServerBusy, Net::SMTPUnknownError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, IOError, SocketError
  ].freeze

  retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 10)
end
