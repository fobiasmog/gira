require "json"
require "net/http"

# The parts of LiveKit's server API the application uses, called as Twirp with
# JSON bodies on the HTTP equivalent of the server's WebSocket URL. Each call
# authenticates with a short-lived admin token for its one room. A room that
# does not exist counts as an empty one.
class LiveKit::RoomService
  # The server answered with an error.
  class Error < StandardError; end
  # The server could not be reached or failed: worth trying again later.
  class Unavailable < Error; end

  TIMEOUT = 2.seconds
  ADMIN_TOKEN_TTL = 1.minute
  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET,
    Errno::EHOSTUNREACH, Errno::ENETUNREACH, EOFError, IOError, SocketError, OpenSSL::SSL::SSLError
  ].freeze

  # Posts with Net::HTTP and answers [status, body].
  class NetHttpTransport
    def post(uri, body, headers)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) do |http|
        http.post(uri.request_uri, body, headers)
      end
      [ response.code.to_i, response.body ]
    end
  end

  def initialize(url:, api_key:, api_secret:, transport: NetHttpTransport.new)
    @base_url = url.sub(/\Aws/, "http").delete_suffix("/")
    @api_key = api_key
    @api_secret = api_secret
    @transport = transport
  end

  # The participants in a room, as LiveKit's ParticipantInfo hashes.
  def list_participants(room)
    call("ListParticipants", room, { room: room }).fetch("participants", [])
  end

  def remove_participant(room, identity)
    call("RemoveParticipant", room, { room: room, identity: identity })
    nil
  end

  # Ends the call for everybody in the room.
  def delete_room(room)
    call("DeleteRoom", room, { room: room })
    nil
  end

  private
    def call(method, room, body)
      uri = URI("#{@base_url}/twirp/livekit.RoomService/#{method}")
      headers = { "Authorization" => "Bearer #{admin_token(room)}", "Content-Type" => "application/json" }
      status, response_body = begin
        @transport.post(uri, JSON.generate(body), headers)
      rescue *NETWORK_ERRORS => error
        raise Unavailable, "LiveKit #{method} failed: #{error.class}"
      end

      parsed = parse(response_body)
      return parsed if status.between?(200, 299)
      return {} if parsed["code"] == "not_found"

      raise (status >= 500 ? Unavailable : Error), "LiveKit #{method} answered #{status} #{parsed["code"]}"
    end

    def parse(body)
      parsed = JSON.parse(body.presence || "{}")
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # DeleteRoom needs roomCreate; the other calls need roomAdmin for the room.
    def admin_token(room)
      LiveKit::AccessToken.new(api_key: @api_key, api_secret: @api_secret, ttl: ADMIN_TOKEN_TTL,
        video: { room: room, roomAdmin: true, roomCreate: true }).to_jwt
    end
end
