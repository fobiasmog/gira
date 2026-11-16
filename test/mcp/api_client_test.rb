require_relative "support"

# The API answers JSON, which is UTF-8 (RFC 8259), but Net::HTTP tags a body
# that holds any non-ASCII byte as binary. Such a body in a tool result made
# the MCP reply fail to serialize, so a call the API had carried out was
# reported as "Internal error".
class McpApiClientTest < ActiveSupport::TestCase
  def answer(body)
    GoalnerMcp::ApiClient.new(->(*) { [ 200, body ] }).request("GET", "/api/me").body
  end

  test "a binary body with non-ASCII text comes back as UTF-8" do
    body = answer(%({"title":"Готово – 7.2…"}).b)

    assert_equal Encoding::UTF_8, body.encoding
    assert_equal %({"title":"Готово – 7.2…"}), body
    assert_includes JSON.generate(text: body), "Готово – 7.2…"
  end

  test "an ASCII body is unchanged" do
    body = answer(%({"title":"Adopt the cards..."}).b)

    assert_equal Encoding::UTF_8, body.encoding
    assert_equal %({"title":"Adopt the cards..."}), body
  end

  test "bytes that are not UTF-8 become replacement characters" do
    body = answer("caf\xE9 ok".b)

    assert_equal "caf� ok", body
    assert body.valid_encoding?
  end

  test "a frozen body is not modified" do
    sent = %({"title":"…"}).b.freeze

    assert_equal %({"title":"…"}), answer(sent)
    assert_equal Encoding::ASCII_8BIT, sent.encoding
  end
end
