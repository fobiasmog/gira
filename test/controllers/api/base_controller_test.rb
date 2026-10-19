require "test_helper"

class Api::ErrorProbeController < Api::BaseController
  class Boom < StandardError; end

  def show = render(json: { ok: true })
  def forbidden = raise(Forbidden)
  def missing = User.find(0)
  def invalid = User.create!(name: "")
  def boom = raise(Boom, "PG::Error: SELECT secret FROM users")

  rate_limit to: 1, within: 1.minute, only: :limited, store: ActiveSupport::Cache::MemoryStore.new
  def limited = render(json: { ok: true })
end

class Api::BaseControllerTest < ActionDispatch::IntegrationTest
  ACTIONS = %w[show forbidden missing invalid boom limited].freeze

  # Requests a probe action and returns the response. with_routing starts a
  # fresh integration session and discards it afterwards, so signing in and
  # capturing the response both happen inside it.
  def probe(action, signed_in: true, times: 1)
    with_routing do |set|
      set.draw { namespace(:api) { ACTIONS.each { |name| get "probe/#{name}", to: "error_probe##{name}" } } }
      sign_in_as users(:one) if signed_in
      times.times { get "/api/probe/#{action}" }
      response
    end
  end

  test "anonymous API requests get 401 JSON instead of a redirect" do
    res = probe(:show, signed_in: false)

    assert_equal 401, res.status
    assert_equal "application/json", res.media_type
    assert_equal "unauthorized", res.parsed_body.dig("error", "code")
  end

  test "signed-in requests succeed" do
    assert_equal 200, probe(:show).status
  end

  test "missing permission is 403" do
    res = probe(:forbidden)

    assert_equal 403, res.status
    assert_equal "forbidden", res.parsed_body.dig("error", "code")
  end

  test "missing records are 404" do
    res = probe(:missing)

    assert_equal 404, res.status
    assert_equal({ "code" => "not_found", "message" => "Not found." }, res.parsed_body["error"])
  end

  test "unknown API paths are 404 JSON" do
    sign_in_as users(:one)
    get "/api/no/such/thing"

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  test "validation errors are 422 with per-field messages" do
    res = probe(:invalid)

    assert_equal 422, res.status
    assert_equal "validation_failed", res.parsed_body.dig("error", "code")
    assert_includes res.parsed_body.dig("error", "fields").keys, "name"
    assert_includes res.parsed_body.dig("error", "fields").keys, "email_address"
  end

  test "rate-limited requests are 429" do
    res = probe(:limited, times: 2)

    assert_equal 429, res.status
    assert_equal "rate_limited", res.parsed_body.dig("error", "code")
  end

  test "unexpected exceptions are 500 with a generic message and are reported" do
    res = nil
    assert_error_reported(Api::ErrorProbeController::Boom) { res = probe(:boom) }

    assert_equal 500, res.status
    assert_equal({ "code" => "internal_error", "message" => "Something went wrong. Please try again." }, res.parsed_body["error"])
    assert_no_match(/PG::|SELECT|Boom|ErrorProbe|backtrace/, res.body)
  end
end
