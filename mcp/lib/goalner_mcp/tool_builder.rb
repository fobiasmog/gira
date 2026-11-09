module GoalnerMcp
  # Builds one MCP tool per operation of docs/openapi.yaml whose success
  # response is JSON or empty (spec mcp-server, "Tools follow the API
  # document"; add-mcp-server design.md, decisions 4 and 5). The file
  # downloads, which answer with bytes, are left out by that rule.
  #
  # - Name: the operationId. Title: the summary. Description: the summary, the
  #   description, then the method and path.
  # - Input schema: the path parameters (required), the query parameters and
  #   the properties of the JSON request body, with $ref, allOf and nullable
  #   oneOf inlined so the schema is self-contained. A name that is both a
  #   parameter and a body property fails the build.
  # - Hints: by HTTP method, except read_only_hint, which is the operation's
  #   read_only?, the predicate ToolCall also applies to read-only
  #   connections (harden-mcp-oauth design.md, decision 11).
  class ToolBuilder
    DOCUMENT = File.expand_path("../../../docs/openapi.yaml", __dir__)
    METHODS = %w[ get post put patch delete ].freeze

    # nil leaves a hint unset. MCP takes a tool that is not read-only as
    # destructive unless told otherwise, so false is explicit.
    HINTS = {
      "GET" => { destructive_hint: nil, idempotent_hint: nil },
      "POST" => { destructive_hint: false, idempotent_hint: false },
      "PATCH" => { destructive_hint: false, idempotent_hint: false },
      "PUT" => { destructive_hint: false, idempotent_hint: true },
      "DELETE" => { destructive_hint: true, idempotent_hint: true }
    }.freeze

    class Error < StandardError; end

    Operation = Data.define(:id, :method, :path, :summary, :description, :parameters, :body_schema) do
      def body? = !body_schema.nil?
      def path_parameters = parameters.select { it["in"] == "path" }.map { it["name"] }
      def query_parameters = parameters.select { it["in"] == "query" }.map { it["name"] }
      def body_properties = body_schema ? body_schema.fetch("properties", {}).keys : []
      def read_only? = method == "GET"
    end

    def initialize(api, document: YAML.safe_load_file(DOCUMENT))
      @api = api
      @document = document
    end

    def tools
      operations.map { |operation| build(operation) }
    end

    def operations
      @document.fetch("paths").flat_map do |path, item|
        item.slice(*METHODS).filter_map do |method, definition|
          next unless json_or_empty?(definition)

          Operation.new(
            id: definition.fetch("operationId"),
            method: method.upcase,
            path: path,
            summary: definition.fetch("summary"),
            description: definition["description"],
            parameters: parameters(item, definition),
            body_schema: body_schema(definition)
          )
        end
      end
    end

    private
      def json_or_empty?(definition)
        _status, success = definition.fetch("responses").find { |status, _| status.to_s.start_with?("2") }
        content = success && inline(success)["content"]
        content.nil? || content.key?("application/json")
      end

      # The path's parameters, then the operation's, which override a path
      # parameter of the same name and location.
      def parameters(item, definition)
        (Array(item["parameters"]) + Array(definition["parameters"])).map { inline(it) }
          .to_h { [ [ it["name"], it["in"] ], it ] }.values
      end

      def body_schema(definition)
        body = definition["requestBody"] or return
        schema = inline(body).dig("content", "application/json", "schema")
        schema or raise Error, "#{definition["operationId"]} has no JSON request body"
      end

      def build(operation)
        call = ToolCall.new(@api, operation)
        MCP::Tool.define(
          name: operation.id,
          title: operation.summary,
          description: [ operation.summary, operation.description&.strip, "#{operation.method} #{operation.path}" ].compact.join("\n\n"),
          input_schema: input_schema(operation),
          annotations: HINTS.fetch(operation.method).merge(read_only_hint: operation.read_only?, open_world_hint: false)
        ) do |server_context:, **arguments|
          call.call(arguments, server_context.auth_info)
        end
      end

      def input_schema(operation)
        properties = {}
        required = []

        operation.parameters.each do |parameter|
          raise Error, "#{operation.id}: parameters in #{parameter["in"]} are not supported" unless %w[ path query ].include?(parameter["in"])

          name = parameter.fetch("name")
          properties[name] = parameter.fetch("schema").merge(parameter.slice("description"))
          required << name if parameter["in"] == "path" || parameter["required"]
        end

        operation.body_schema&.fetch("properties", {})&.each do |name, schema|
          raise Error, "#{operation.id}: #{name} is both a parameter and a body property" if properties.key?(name)

          properties[name] = schema
        end
        required.concat(Array(operation.body_schema&.fetch("required", nil)))

        { "type" => "object", "properties" => properties, "required" => required.uniq, "additionalProperties" => false }
      end

      # The node with every $ref replaced by its target and every allOf merged
      # into one schema. Sibling keywords of a $ref, such as a description,
      # win over the target's.
      def inline(node)
        case node
        when Array
          node.map { inline(it) }
        when Hash
          if node.key?("$ref")
            inline(resolve(node["$ref"])).merge(inline(node.except("$ref")))
          elsif node.key?("allOf")
            merge_all(node["allOf"].map { inline(it) } + [ inline(node.except("allOf")) ])
          else
            node.transform_values { inline(it) }
          end
        else
          node
        end
      end

      def resolve(ref)
        raise Error, "only local references are supported: #{ref}" unless ref.start_with?("#/")

        ref.delete_prefix("#/").split("/").reduce(@document) { |node, key| node.fetch(key) }
      end

      def merge_all(schemas)
        schemas.reduce({}) do |merged, schema|
          merged.merge(schema) do |key, old, new|
            case key
            when "properties" then old.merge(new)
            when "required" then old | new
            else new
            end
          end
        end
      end
  end
end
