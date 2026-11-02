module GoalnerMcp
  # The token API, reached over the private network at GOALNER_API_URL, never
  # the public URL (add-mcp-server design.md, decision 7). Each request carries
  # the caller's credential and is sent once: requests are never retried, so a
  # timed-out write is never repeated. No cookies and no X-Forwarded-For are
  # sent, so the API sees the MCP container as the client.
  #
  # The transport is swappable: tests call the Rails application in-process.
  class ApiClient
    Response = Data.define(:status, :body)

    # The API could not be reached, timed out, or answered with a redirect or a
    # server error (decision 8). The detail goes to the log, never to clients.
    class Unavailable < StandardError; end

    UNAVAILABLE_MESSAGE = "Goalner is unavailable. Try again later."

    HEADERS = {
      "Accept" => "application/json",
      # force_ssl redirects plain HTTP. The web role trusts this header from
      # private networks, where the MCP container sits.
      "X-Forwarded-Proto" => "https",
      "User-Agent" => "goalner-mcp/#{VERSION}"
    }.freeze

    attr_reader :transport

    def initialize(transport)
      @transport = transport
    end

    # path includes any query string; body is JSON-encoded when given. Raises
    # Unavailable for anything but a 2xx or 4xx answer. A redirect means a
    # misconfiguration, such as a public GOALNER_API_URL or a lost
    # X-Forwarded-Proto, and is logged as an error.
    def request(method, path, token:, body: nil)
      headers = HEADERS.merge("Authorization" => "Bearer #{token}")
      headers["Content-Type"] = "application/json" if body

      begin
        status, response_body = transport.call(method, path, headers, body && JSON.generate(body))
      rescue StandardError => error
        unavailable "#{error.class}: #{error.message}"
      end

      unavailable "redirected with #{status}; check GOALNER_API_URL and X-Forwarded-Proto" if status.between?(300, 399)
      unavailable "answered #{status}" if status >= 500
      Response.new(status: status, body: response_body)
    end

    # Net::HTTP with one keep-alive connection per thread: 2 seconds to
    # connect, 15 to read, no retries and no proxy.
    class HttpTransport
      OPEN_TIMEOUT = 2
      READ_TIMEOUT = 15

      def initialize(base_url)
        @uri = URI(base_url)
        @key = :"goalner_mcp_http_#{object_id}"
      end

      def call(method, path, headers, body)
        request = Net::HTTPGenericRequest.new(method, !body.nil?, method != "HEAD", path, headers)
        request.body = body if body
        response = connection.request(request)
        [ response.code.to_i, response.body.to_s ]
      rescue StandardError
        disconnect
        raise
      end

      private
        def connection
          http = Thread.current[@key]
          return http if http&.started?

          http = Net::HTTP.new(@uri.host, @uri.port, nil)
          http.use_ssl = @uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.write_timeout = READ_TIMEOUT
          http.max_retries = 0
          Thread.current[@key] = http.tap(&:start)
        end

        def disconnect
          http = Thread.current[@key]
          Thread.current[@key] = nil
          http.finish if http&.started?
        rescue IOError
        end
    end

    private
      # Paths carry tool arguments, so the log names neither the path nor the
      # body (spec mcp-server, "Privacy of MCP logs").
      def unavailable(detail)
        GoalnerMcp.logger.error("API unavailable: #{detail}")
        raise Unavailable, detail
      end
  end
end
