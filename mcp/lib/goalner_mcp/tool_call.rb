module GoalnerMcp
  # One call of a generated tool: exactly one API request, made with the
  # caller's credential, so every rule of the API applies to it (spec
  # mcp-server, "Tool calls act as the token"; add-mcp-server design.md,
  # decisions 4 and 8). The SDK has validated the arguments before.
  #
  # - Path parameters are URL-encoded, so task keys such as GOAL-12 pass.
  # - Query parameters and body properties are sent only when given. A body
  #   property given as nil is sent as null.
  # - 2xx: the response body as text, or "Done." when there is none. 401: the
  #   credential is marked rejected, and Authentication answers 401. Other
  #   errors: the envelope's code, message and field messages, as a tool error.
  #   An unreachable or failing API: a generic tool error.
  # - A read-only connection calling a tool that is not read-only gets
  #   insufficient_scope without an API request (add-mcp-oauth design.md,
  #   decision 9). A connection whose exchange is refused is answered like an
  #   API 401, and an exchange over its limit gets rate_limited. The exchange
  #   already ran in Authentication; its answer is reused (Credential).
  class ToolCall
    def initialize(api, operation)
      @api = api
      @operation = operation
    end

    INSUFFICIENT_SCOPE = "insufficient_scope: This connection is read-only."
    RATE_LIMITED = "rate_limited: Too many requests. Try again later."

    def call(arguments, credential)
      return error(INSUFFICIENT_SCOPE) if credential.read_only_connection? && !@operation.read_only?

      response = @api.request(@operation.method, path(arguments), token: upstream_token(credential), body: body(arguments))
      credential.api_status = response.status

      case response.status
      when 204 then text("Done.")
      when 200..299 then text(response.body)
      when 401
        credential.reject!
        raise Unauthorized
      else error(describe(response))
      end
    rescue ApiClient::Unavailable
      error(ApiClient::UNAVAILABLE_MESSAGE)
    rescue ConnectionTokens::RateLimited
      error(RATE_LIMITED)
    end

    private
      def upstream_token(credential)
        credential.upstream_token
      rescue ConnectionTokens::Refused
        credential.reject!
        raise Unauthorized
      end

      def path(arguments)
        path = @operation.path.gsub(/\{(\w+)\}/) { URI.encode_uri_component(arguments.fetch($1.to_sym).to_s) }
        query = @operation.query_parameters.filter_map { |name| [ name, arguments[name.to_sym] ] if arguments.key?(name.to_sym) }
        query.empty? ? path : "#{path}?#{URI.encode_www_form(query)}"
      end

      def body(arguments)
        return unless @operation.body?

        @operation.body_properties.each_with_object({}) do |name, body|
          body[name] = arguments[name.to_sym] if arguments.key?(name.to_sym)
        end
      end

      def describe(response)
        envelope = JSON.parse(response.body).fetch("error")
        lines = [ "#{envelope.fetch("code")}: #{envelope.fetch("message")}" ]
        envelope.fetch("fields", nil)&.each do |field, messages|
          Array(messages).each { |message| lines << "#{field}: #{message}" }
        end
        lines.join("\n")
      rescue JSON::ParserError, KeyError, TypeError, NoMethodError
        GoalnerMcp.logger.error("API answered #{response.status} without an error envelope")
        ApiClient::UNAVAILABLE_MESSAGE
      end

      def text(value)
        MCP::Tool::Response.new([ { type: "text", text: value } ])
      end

      def error(value)
        MCP::Tool::Response.new([ { type: "text", text: value } ], error: true)
      end
  end
end
