require_relative "support"

# The validation hook itself, against variants of the document.
class OpenapiHookContract < OpenapiContractTest
  setup { @document = OpenapiContractTest.document }

  def openapi_document
    @document
  end

  def use_document
    data = OpenapiContractTest.document_data.deep_dup
    yield data
    @document = OpenapiFirst.parse(data)
  end

  test "a conforming token request passes" do
    get api_me_path, headers: bearer("glnr_two_goal_read")

    assert_response :success
  end

  test "a response field the schema does not describe fails, naming the operation and the field" do
    use_document { |data| data.dig("components", "schemas", "Profile", "allOf", 1, "properties").delete("admin") }

    error = assert_raises(Minitest::Assertion) { get api_me_path, headers: bearer("glnr_two_goal_read") }

    assert_match(/\AshowProfile \(GET \/api\/me\) answered 200: .*`\/admin`/, error.message)
  end

  test "a status the operation does not list fails, naming the operation and the status" do
    use_document { |data| data.dig("paths", "/api/me", "get", "responses").delete("401") }

    error = assert_raises(Minitest::Assertion) { get api_me_path, headers: bearer("glnr_unknown") }

    assert_match(/\AshowProfile \(GET \/api\/me\) answered 401: Status 401 is not defined/, error.message)
  end

  test "a token request to an undocumented path fails, naming the method and path" do
    error = assert_raises(Minitest::Assertion) { get api_teammates_path, headers: bearer("glnr_two_goal_read") }

    assert_equal "GET /api/teammates is not a documented operation", error.message
  end

  test "a request without a token is not checked" do
    sign_in_as users(:two)

    get api_teammates_path

    assert_response :success
  end

  test "a rejected request may break the document; an accepted one may not" do
    use_document do |data|
      data["paths"]["/api/projects/{project_id}/labels"] = {
        "post" => {
          "operationId" => "createLabel",
          "parameters" => [ { "name" => "project_id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } } ],
          "requestBody" => { "required" => true, "content" => { "application/json" => { "schema" => {
            "type" => "object", "required" => [ "title" ], "properties" => { "title" => { "type" => "string", "minLength" => 1, "maxLength" => 5 } }
          } } } },
          "responses" => {
            "201" => { "description" => "Created", "content" => { "application/json" => { "schema" => { "type" => "object" } } } },
            "422" => { "$ref" => "#/components/responses/Unauthorized" }
          }
        }
      }
    end

    post api_project_labels_path(projects(:goal)), params: { title: "" }, headers: bearer("glnr_two_goal_read_write"), as: :json
    assert_response :unprocessable_content

    error = assert_raises(Minitest::Assertion) do
      post api_project_labels_path(projects(:goal)), params: { title: "too long here" }, headers: bearer("glnr_two_goal_read_write"), as: :json
    end
    assert_match(/\AcreateLabel \(POST \/api\/projects\/\d+\/labels\) accepted a request the document rejects: .*`\/title`/, error.message)
  end
end
