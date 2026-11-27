require "json"
require "net/http"
require "openssl"
require "uri"

module GoalnerWorker
  # Goalner's API, as the worker calls it: with the runner secret on the
  # runner endpoints, and with the run token on the others. Answers are
  # returned as they come, server errors included; only a Goalner that
  # cannot be reached raises.
  class Api
    class Unreachable < StandardError; end

    Response = Struct.new(:status, :body) do
      def ok? = status.between?(200, 299)
      def server_error? = status >= 500
      def unauthorized? = status == 401

      def json
        @json ||= body.to_s.empty? ? nil : JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def error_code = json.is_a?(Hash) ? json.dig("error", "code") : nil
    end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    attr_reader :url

    def initialize(url)
      @url = url
      @base = URI(url)
    end

    def get(path, token:, query: nil) = request(Net::HTTP::Get, path, token:, query:)
    def post(path, token:, body: nil) = request(Net::HTTP::Post, path, token:, body:)
    def put(path, token:, body: nil) = request(Net::HTTP::Put, path, token:, body:)
    def patch(path, token:, body: nil) = request(Net::HTTP::Patch, path, token:, body:)
    def delete(path, token:) = request(Net::HTTP::Delete, path, token:)

    private
      def request(type, path, token:, query: nil, body: nil)
        uri = @base.dup
        uri.path = @base.path.chomp("/") + path
        uri.query = URI.encode_www_form(query) if query
        request = type.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Accept"] = "application/json"
        request["User-Agent"] = "goalner-worker"
        if body
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(body)
        end
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
        Response.new(response.code.to_i, response.body)
      rescue SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, EOFError => error
        raise Unreachable, error.message
      end
  end
end
