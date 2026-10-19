# Stands in for the Sentry ingest host in system tests: the SPA page gets a
# DSN that points back at the test server, and envelopes posted there are kept
# for assertions.
module SentryCapture
  mattr_accessor :dsn
  @envelopes = Queue.new

  class << self
    attr_reader :envelopes

    # The event payloads of the envelopes received so far.
    def events
      payloads = []
      payloads << @envelopes.pop until @envelopes.empty?
      payloads.flat_map do |raw|
        lines = raw.split("\n")
        lines.each_cons(2).filter_map { |header, body| JSON.parse(body) if JSON.parse(header)["type"] == "event" rescue nil }
      end
    end
  end

  class EnvelopesController < ActionController::Base
    skip_forgery_protection

    def create
      SentryCapture.envelopes << request.raw_post
      head :ok
    end
  end

  module MetaTagOverride
    def sentry_meta_tag(**options)
      SentryCapture.dsn ? tag.meta(name: "sentry-dsn", content: SentryCapture.dsn) : super
    end
  end
  ApplicationHelper.prepend(MetaTagOverride)
end
