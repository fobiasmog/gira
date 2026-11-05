ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/oauth_test_helper"

# No test reaches the network for a client ID metadata document
# (harden-mcp-oauth design.md, decision 10): the default resolver and
# transport raise. Tests that fetch documents put stubs of their own in place.
Oauth::ClientMetadataDocument.resolver = ->(_host) { raise "network access in tests" }
Oauth::ClientMetadataDocument.transport = Class.new { def get(*, **) = raise("network access in tests") }.new

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rate limit counters live in the cache.
    setup { Rails.cache.clear }
  end
end
