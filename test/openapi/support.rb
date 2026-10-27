require "test_helper"
require "openapi_first"

# Base of the contract suite that bin/openapi-verify runs (design.md,
# decisions 2 to 4). The default test run never loads it: its files end in
# _contract.rb, not _test.rb.
#
# Every request a test here makes with an API token must be a documented
# operation of docs/openapi.yaml. Its response must match the document,
# whatever the status, and so must the request when the API accepted it
# (2xx); error examples send invalid input on purpose.
class OpenapiContractTest < ActionDispatch::IntegrationTest
  DOCUMENT = Rails.root.join("docs/openapi.yaml")

  def self.document
    @document ||= OpenapiFirst.load(DOCUMENT.to_s)
  end

  # The document as plain data, for checks of the document itself.
  def self.document_data
    @document_data ||= YAML.safe_load_file(DOCUMENT)
  end

  Operation = Data.define(:method, :path, :id, :definition) do
    def to_s = "#{id} (#{method} #{path})"

    def success_status
      definition.fetch("responses").keys.find { |status| status.start_with?("2") }.to_i
    end
  end

  # Every property name the document describes, at any depth.
  def self.documented_names
    @documented_names ||= Set.new.tap do |names|
      collect = ->(node) do
        case node
        when Hash
          names.merge(node["properties"].keys) if node["properties"].is_a?(Hash)
          node.each_value(&collect)
        when Array
          node.each(&collect)
        end
      end
      collect.(document_data)
    end
  end

  # Every operation of the document, in document order.
  def self.operations
    @operations ||= document_data.fetch("paths").flat_map do |path, item|
      item.slice("get", "post", "put", "patch", "delete").map do |method, definition|
        Operation.new(method: method.upcase, path: path, id: definition["operationId"], definition: definition)
      end
    end
  end

  %i[get post patch put delete].each do |verb|
    define_method(verb) do |path, **options|
      super(path, **options).tap { verify_exchange }
    end
  end

  private
    def bearer(value)
      { "Authorization" => "Bearer #{value}" }
    end

    # The document the hook checks against; a test may swap in a variant.
    def openapi_document
      OpenapiContractTest.document
    end

    def verify_exchange
      return unless request.authorization.to_s.match?(ApiTokenAuthentication::BEARER_SCHEME)

      request.body&.rewind
      rack_request = Rack::Request.new(request.env)
      rack_response = Rack::Response.new([ response.body ], response.status, response.headers)
      exchange = "#{request.request_method} #{request.path}"

      validated_request = openapi_document.validate_request(rack_request)
      flunk "#{exchange} is not a documented operation" if validated_request.unknown?

      operation = validated_request.request_definition.operation_id
      validated_response = openapi_document.validate_response(rack_request, rack_response)
      if validated_response.invalid?
        flunk "#{operation} (#{exchange}) answered #{response.status}: #{describe(validated_response.error)}"
      end
      if response.successful? && validated_request.invalid?
        flunk "#{operation} (#{exchange}) accepted a request the document rejects: #{describe(validated_request.error)}"
      end
    end

    # The causes first: missing fields, then values at undocumented names. A
    # failure inside an allOf part makes unevaluatedProperties reject every
    # other field too; those follow, after the causes.
    def describe(failure)
      errors = failure.errors
      return failure.exception_message if errors.blank?

      ranked = errors.each_with_index.sort_by do |error, index|
        name = error.data_pointer.split("/").last
        rank = if error.message.include?("missing required") then 0
        elsif !OpenapiContractTest.documented_names.include?(name) then 1
        else 2
        end
        [ rank, index ]
      end.map(&:first)

      shown = ranked.first(5).map(&:message)
      shown << "#{errors.size - shown.size} more" if errors.size > shown.size
      shown.join("; ")
    end
end
