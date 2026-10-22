require "test_helper"
require "socket"
require "support/live_kit_test_helper"

class LiveKit::RoomServiceTest < ActiveSupport::TestCase
  include LiveKitTestHelper

  # Records requests and answers each with the next response, [status, body],
  # or raises it when it is an exception.
  class FakeTransport
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def post(uri, body, headers)
      @requests << { url: uri.to_s, body: JSON.parse(body), headers: headers }
      response = @responses.shift
      raise response if response.is_a?(Exception)

      response
    end
  end

  test "lists a room's participants" do
    transport = FakeTransport.new([ 200, { participants: [ { identity: "7", name: "Alice" } ] }.to_json ])

    participants = service(transport).list_participants("project-1")

    assert_equal [ { "identity" => "7", "name" => "Alice" } ], participants
    assert_equal "http://localhost:7880/twirp/livekit.RoomService/ListParticipants", transport.requests.last[:url]
    assert_equal({ "room" => "project-1" }, transport.requests.last[:body])
    assert_equal "application/json", transport.requests.last[:headers]["Content-Type"]
  end

  test "authenticates with a short-lived admin token for the one room" do
    transport = FakeTransport.new([ 200, "{}" ])

    freeze_time do
      service(transport).list_participants("project-1")

      jwt = transport.requests.last[:headers]["Authorization"].delete_prefix("Bearer ")
      header, payload, signature = jwt.split(".")
      assert_equal OpenSSL::HMAC.digest("SHA256", "secret", "#{header}.#{payload}"), Base64.urlsafe_decode64(signature)
      claims = jwt_claims(jwt)
      assert_equal "devkey", claims["iss"]
      assert_equal 1.minute.from_now.to_i, claims["exp"]
      assert_equal({ "room" => "project-1", "roomAdmin" => true, "roomCreate" => true }, claims["video"])
    end
  end

  test "removes a participant" do
    transport = FakeTransport.new([ 200, "{}" ])

    assert_nil service(transport).remove_participant("project-1", "7")

    assert_equal "http://localhost:7880/twirp/livekit.RoomService/RemoveParticipant", transport.requests.last[:url]
    assert_equal({ "room" => "project-1", "identity" => "7" }, transport.requests.last[:body])
  end

  test "deletes a room" do
    transport = FakeTransport.new([ 200, "{}" ])

    assert_nil service(transport).delete_room("project-1")

    assert_equal "http://localhost:7880/twirp/livekit.RoomService/DeleteRoom", transport.requests.last[:url]
    assert_equal({ "room" => "project-1" }, transport.requests.last[:body])
  end

  test "calls the HTTPS equivalent of a secure WebSocket URL" do
    transport = FakeTransport.new([ 200, "{}" ])

    LiveKit::RoomService.new(url: "wss://media.example.com/", api_key: "k", api_secret: "s", transport: transport).delete_room("project-1")

    assert_equal "https://media.example.com/twirp/livekit.RoomService/DeleteRoom", transport.requests.last[:url]
  end

  test "a room that does not exist is empty" do
    not_found = [ 404, { code: "not_found", msg: "requested room does not exist" }.to_json ]
    transport = FakeTransport.new(not_found, not_found, not_found)

    assert_equal [], service(transport).list_participants("project-1")
    assert_nil service(transport).remove_participant("project-1", "7")
    assert_nil service(transport).delete_room("project-1")
  end

  test "an error answer raises" do
    transport = FakeTransport.new([ 401, { code: "unauthenticated", msg: "invalid token" }.to_json ])

    error = assert_raises(LiveKit::RoomService::Error) { service(transport).list_participants("project-1") }
    assert_not_kind_of LiveKit::RoomService::Unavailable, error
    assert_includes error.message, "401 unauthenticated"
  end

  test "a server failure means the server is unavailable" do
    transport = FakeTransport.new([ 503, "upstream unavailable" ])

    assert_raises(LiveKit::RoomService::Unavailable) { service(transport).list_participants("project-1") }
  end

  test "a network failure means the server is unavailable" do
    transport = FakeTransport.new(Errno::ECONNREFUSED.new)

    assert_raises(LiveKit::RoomService::Unavailable) { service(transport).list_participants("project-1") }
  end

  test "gives up on a server that does not answer within 2 seconds" do
    server = TCPServer.new("127.0.0.1", 0)
    service = LiveKit::RoomService.new(url: "ws://127.0.0.1:#{server.addr[1]}", api_key: "devkey", api_secret: "secret")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(LiveKit::RoomService::Unavailable) { service.list_participants("project-1") }
    assert_in_delta 2, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, 1
  ensure
    server&.close
  end

  private
    def service(transport)
      LiveKit::RoomService.new(url: "ws://localhost:7880", api_key: "devkey", api_secret: "secret", transport: transport)
    end
end
