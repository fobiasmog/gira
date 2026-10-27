require_relative "support"
require "support/route_table"

# The document itself, and its parity with the actions opened to API tokens
# (design.md, decision 4).
class OpenapiParityContract < OpenapiContractTest
  # "METHOD /path/{param}" for every route to an action opened to tokens.
  # Rails routes an update action to both PATCH and PUT, and the document
  # lists one of them, so both sides write either as "PATCH|PUT".
  def self.opened_operations
    RouteTable.routes.flat_map do |route|
      next [] if RouteTable.endpoint(route) == "api/base#route_not_found"

      controller = "#{route.defaults[:controller]}_controller".camelize.safe_constantize
      next [] unless controller.respond_to?(:token_actions) && controller.token_actions.include?(route.defaults[:action].to_s)

      paths = expand_optional(route.path.spec.to_s.delete_suffix("(.:format)")).map { |path| path.gsub(/:(\w+)/, '{\1}') }
      RouteTable.verbs(route).product(paths).map { |verb, path| "#{merge_update_verbs(verb)} #{path}" }
    end.uniq.sort
  end

  def self.documented_operations
    OpenapiContractTest.operations.map { |operation| "#{merge_update_verbs(operation.method)} #{operation.path}" }.uniq.sort
  end

  # files/:signed_id(/:variant) is two paths.
  def self.expand_optional(path)
    match = path.match(/\(([^()]*)\)/) or return [ path ]
    [ match.pre_match + match[1] + match.post_match, match.pre_match + match.post_match ].flat_map { |expanded| expand_optional(expanded) }
  end

  def self.merge_update_verbs(verb)
    %w[PATCH PUT].include?(verb) ? "PATCH|PUT" : verb
  end

  test "every action opened to tokens is documented, and every documented operation is opened" do
    opened = self.class.opened_operations
    documented = self.class.documented_operations

    assert_empty opened - documented, "opened to API tokens but not documented"
    assert_empty documented - opened, "documented but not opened to API tokens"
  end

  test "the document is valid OpenAPI 3.1" do
    errors = JSONSchemer.openapi(OpenapiContractTest.document_data).validate.map { |error| error["error"] }

    assert_empty errors
  end

  test "every operation has a unique operation id, a tag and a summary" do
    operations = OpenapiContractTest.operations

    assert_empty operations.reject { |operation| operation.id && operation.definition["tags"].present? && operation.definition["summary"].present? }.map(&:to_s)
    assert_equal operations.map(&:id).uniq, operations.map(&:id)
  end

  test "session-only endpoint absent: no project archiving, invitations or teammates" do
    documented = OpenapiContractTest.operations.map { |operation| "#{operation.method} #{operation.path}" }

    assert_not_includes documented, "DELETE /api/projects/{id}"
    assert_empty documented.grep(%r{/invitations|/teammates|/membership|/statuses})
  end

  test "opened endpoint documented: creating a task, with its body, its 201 task and Bearer authentication" do
    data = OpenapiContractTest.document_data
    operation = data.dig("paths", "/api/projects/{project_id}/tasks", "post")
    body = data.dig("components", "schemas", "TaskCreate")
    created = operation.dig("responses", "201", "content", "application/json", "schema", "$ref")

    assert_equal "createTask", operation["operationId"]
    assert_equal %w[title], body["required"]
    assert_includes body["properties"].keys, "status_id"
    assert_equal "#/components/schemas/TaskDetail", created
    assert_equal [ { "bearerAuth" => [] } ], data["security"]
    assert_equal({ "type" => "http", "scheme" => "bearer" }, data.dig("components", "securitySchemes", "bearerAuth").slice("type", "scheme"))
  end

  test "read-only token writes: the 403 of creating a task is the error envelope with insufficient_scope" do
    data = OpenapiContractTest.document_data
    forbidden = data.dig("paths", "/api/projects/{project_id}/tasks", "post", "responses", "403", "$ref")
    response = data.dig("components", "responses", forbidden.delete_prefix("#/components/responses/"))

    assert_equal "#/components/schemas/Error", response.dig("content", "application/json", "schema", "$ref")
    assert_equal "insufficient_scope", response.dig("content", "application/json", "example", "error", "code")
  end

  test "validation errors: the 422 of creating a label is the error envelope with field messages keyed by field" do
    data = OpenapiContractTest.document_data
    invalid = data.dig("paths", "/api/projects/{project_id}/labels", "post", "responses", "422", "$ref")
    response = data.dig("components", "responses", invalid.delete_prefix("#/components/responses/"))
    fields = data.dig("components", "schemas", "Error", "properties", "error", "properties", "fields")

    assert_equal "#/components/schemas/Error", response.dig("content", "application/json", "schema", "$ref")
    assert_equal "validation_failed", response.dig("content", "application/json", "example", "error", "code")
    assert_equal({ "type" => "array", "items" => { "type" => "string" } }, fields["additionalProperties"])
  end

  test "file downloads: an attachment and its preview, as bytes" do
    paths = OpenapiContractTest.document_data.fetch("paths")

    %w[/files/{signed_id} /files/{signed_id}/{variant}].each do |path|
      ok = paths.dig(path, "get", "responses", "200", "content")
      assert_equal({ "type" => "string", "format" => "binary" }, ok&.dig("*/*", "schema"), path)
    end
    assert_equal [ "preview" ], paths.dig("/files/{signed_id}/{variant}", "get", "parameters", 1, "schema", "enum")
  end
end
