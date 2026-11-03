require "test_helper"

# Client ID metadata documents (spec mcp-authorization, "Client ID metadata
# documents"; add-mcp-oauth design.md, decision 4), with a stubbed resolver
# and HTTP transport. HttpTransportTest below drives the real transport
# against a local server.
class Oauth::ClientMetadataDocumentTest < ActiveSupport::TestCase
  URL = "https://claude.ai/oauth/claude-code-client-metadata"
  PUBLIC_IP = "160.79.104.10"

  # Answers every GET with the next of its responses, and records where it
  # connected.
  class FakeTransport
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def get(uri, address:, timeout:)
      @requests << [ uri.to_s, address ]
      response = @responses.length > 1 ? @responses.shift : @responses.first
      response.respond_to?(:call) ? response.call : response
    end
  end

  setup do
    @original = Oauth::ClientMetadataDocument.resolver, Oauth::ClientMetadataDocument.transport, Oauth::ClientMetadataDocument.timeout
    @resolved = []
    stub_resolver PUBLIC_IP
    stub_document({ client_id: URL, client_name: "Claude Code", redirect_uris: [ "http://localhost/callback", "http://127.0.0.1/callback" ] })
    oauth_applications(:claude_code).destroy!
  end

  teardown do
    Oauth::ClientMetadataDocument.resolver, Oauth::ClientMetadataDocument.transport, Oauth::ClientMetadataDocument.timeout = @original
  end

  def stub_resolver(*answers)
    Oauth::ClientMetadataDocument.resolver = lambda do |host|
      @resolved << host
      answer = answers.length > 1 ? answers.shift : answers.first
      Array(answer)
    end
  end

  def stub_document(document)
    respond_with body: JSON.generate(document)
  end

  def respond_with(status: 200, content_type: "application/json", body:)
    @transport = FakeTransport.new(Oauth::ClientMetadataDocument::Response.new(status: status, content_type: content_type, body: body))
    Oauth::ClientMetadataDocument.transport = @transport
  end

  def resolve(url = URL, redirect_uri: "http://localhost:51234/callback")
    Oauth::ClientMetadataDocument.resolve(url, redirect_uri: redirect_uri)
  end

  def assert_refused(url = URL, **options)
    assert_no_difference -> { Oauth::Application.count } do
      assert_raises(Oauth::ClientMetadataDocument::Error) { resolve(url, **options) }
    end
  end

  test "Claude Code: the document is fetched from the resolved address and stored as a public client" do
    application = resolve

    assert_equal [ [ URL, PUBLIC_IP ] ], @transport.requests
    assert_equal "Claude Code", application.name
    assert_equal URL, application.uid
    assert application.cimd?
    assert_not application.confidential?
    assert_nil application.secret
    assert_equal [ "http://localhost/callback", "http://127.0.0.1/callback" ], application.redirect_uris
    assert_in_delta Time.current, application.metadata_fetched_at, 2
  end

  test "the stored copy is used for 24 hours, then fetched again" do
    resolve
    travel 23.hours
    resolve
    assert_equal 1, @transport.requests.size

    travel 2.hours
    resolve
    assert_equal 2, @transport.requests.size
    assert_equal 1, Oauth::Application.where(uid: URL).count
  end

  test "mismatched client id" do
    stub_document({ client_id: "https://evil.example/claude-code", redirect_uris: [ "http://localhost/callback" ] })

    assert_refused
  end

  test "private address: IPv4, IPv6 and IPv4-mapped addresses are refused without a request" do
    [ "10.0.0.5", "127.0.0.1", "169.254.169.254", "192.168.1.1", "172.16.0.1", "100.64.0.1", "0.0.0.0", "224.0.0.1",
      "255.255.255.255", "::1", "fd00::1", "fe80::1", "::ffff:10.0.0.5", "::ffff:160.79.104.10", "64:ff9b::a00:5",
      "2002:a00:5::1", "ff02::1", "::" ].each do |address|
      stub_resolver address

      assert_refused
    end
    assert_empty @transport.requests
  end

  test "private address: a name with one private address among public ones is refused" do
    stub_resolver [ PUBLIC_IP, "10.0.0.5" ]

    assert_refused
    assert_empty @transport.requests
  end

  test "private address: a resolver that answers public, then private, is asked once and the public address is used" do
    stub_resolver PUBLIC_IP, "127.0.0.1"

    resolve

    assert_equal [ "claude.ai" ], @resolved
    assert_equal [ [ URL, PUBLIC_IP ] ], @transport.requests
  end

  test "a name that does not resolve is refused" do
    stub_resolver []

    assert_refused
  end

  test "a public IPv6 address is fetched" do
    stub_resolver "2607:6bc0::10"

    assert resolve
    assert_equal "2607:6bc0::10", @transport.requests.sole.last
  end

  test "unlisted redirect URI: one refetch, at most once a minute" do
    resolve
    travel 2.minutes

    assert_equal [ "http://localhost/callback", "http://127.0.0.1/callback" ], resolve(redirect_uri: "https://evil.example/cb").redirect_uris
    assert_equal 2, @transport.requests.size

    resolve(redirect_uri: "https://evil.example/cb")
    resolve(redirect_uri: "https://evil.example/other")
    assert_equal 2, @transport.requests.size

    travel 2.minutes
    resolve(redirect_uri: "https://evil.example/cb")
    assert_equal 3, @transport.requests.size
  end

  test "a listed redirect URI, on any loopback port, needs no refetch" do
    resolve
    travel 2.minutes
    resolve(redirect_uri: "http://127.0.0.1:60000/callback")
    resolve(redirect_uri: "http://localhost:3000/callback")

    assert_equal 1, @transport.requests.size
  end

  test "a refetched document replaces the stored redirect URIs and name" do
    resolve
    travel 2.minutes
    stub_document({ client_id: URL, client_name: "Claude Code 2", redirect_uris: [ "https://claude.ai/new/callback" ] })

    application = resolve(redirect_uri: "https://claude.ai/new/callback")

    assert_equal [ "Claude Code 2", [ "https://claude.ai/new/callback" ] ], [ application.name, application.redirect_uris ]
  end

  test "a 6 KB document is refused" do
    respond_with body: JSON.generate(client_id: URL, redirect_uris: [ "http://localhost/callback" ], padding: "x" * 6.kilobytes)

    assert_refused
  end

  test "a slow response is refused" do
    Oauth::ClientMetadataDocument.timeout = 0.2
    Oauth::ClientMetadataDocument.transport = FakeTransport.new(-> { sleep 1 })

    assert_refused
  end

  test "a redirect is refused, not followed" do
    respond_with status: 302, content_type: "text/html", body: ""

    assert_refused
    assert_equal 1, @transport.requests.size
  end

  test "other statuses, content types and bodies are refused" do
    [ { status: 404, body: "{}" }, { content_type: "text/html", body: JSON.generate(client_id: URL) },
      { body: "not json" }, { body: "[]" } ].each do |response|
      respond_with(**response)

      assert_refused
    end
  end

  test "a transport failure is refused" do
    Oauth::ClientMetadataDocument.transport = FakeTransport.new(-> { raise Errno::ECONNREFUSED })

    assert_refused
  end

  test "document checks: redirect URIs, client authentication and client name" do
    base = { client_id: URL, redirect_uris: [ "http://localhost/callback" ] }

    [ base.merge(redirect_uris: []), base.merge(redirect_uris: "http://localhost/callback"),
      base.merge(redirect_uris: [ "http://example.com/callback" ]), base.merge(redirect_uris: [ "https://a.example/cb#x" ]),
      base.merge(redirect_uris: [ "javascript:alert(1)" ]), base.merge(redirect_uris: [ "urn:ietf:wg:oauth:2.0:oob" ]),
      base.merge(token_endpoint_auth_method: "client_secret_basic"), base.merge(client_name: "x" * 101),
      base.merge(client_name: 42) ].each do |document|
      stub_document document

      assert_refused
    end
  end

  test "the client name falls back to the URL's host" do
    stub_document({ client_id: URL, redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ], token_endpoint_auth_method: "none" })

    assert_equal "claude.ai", resolve(redirect_uri: nil).name
  end

  test "URL rules" do
    [ "http://claude.ai/oauth/metadata", "https://claude.ai", "https://claude.ai/", "https://user:pass@claude.ai/metadata",
      "https://claude.ai/metadata#fragment", "https://claude.ai/#{"a" * 250}", "https:///metadata", "https://claude ai/x" ].each do |url|
      assert_refused url
    end
    assert_empty @transport.requests
  end
end

# The real transport against a plain-HTTP server on this machine: it connects
# to the given address with the original name in Host, reads at most 5 KB,
# and does not follow redirects.
class Oauth::ClientMetadataDocument::HttpTransportTest < ActiveSupport::TestCase
  def serve(response)
    server = TCPServer.new("127.0.0.1", 0)
    @request = Queue.new
    thread = Thread.new do
      client = server.accept
      lines = []
      while (line = client.gets) && line != "\r\n"
        lines << line
      end
      @request << lines
      client.write(response)
      client.close
    end
    yield URI("http://client.example:#{server.addr[1]}/metadata.json")
  ensure
    thread&.join(1)
    server&.close
  end

  def get(uri)
    Oauth::ClientMetadataDocument::HttpTransport.new.get(uri, address: "127.0.0.1", timeout: 1)
  end

  test "connects to the address, with the name in Host" do
    serve("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}") do |uri|
      response = get(uri)

      assert_equal [ 200, "application/json", "{}" ], [ response.status, response.content_type, response.body ]
      assert_includes @request.pop, "Host: client.example:#{uri.port}\r\n"
    end
  end

  test "a redirect is answered, not followed" do
    serve("HTTP/1.1 302 Found\r\nLocation: http://169.254.169.254/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n") do |uri|
      assert_equal 302, get(uri).status
    end
  end

  test "more than 5 KB is not read" do
    body = "x" * 6.kilobytes
    serve("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n#{body}") do |uri|
      assert_raises(Oauth::ClientMetadataDocument::HttpTransport::TooLarge) { get(uri) }
    end
  end

  test "a declared length over 5 KB is refused before reading" do
    serve("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 6000\r\nConnection: close\r\n\r\n") do |uri|
      assert_raises(Oauth::ClientMetadataDocument::HttpTransport::TooLarge) { get(uri) }
    end
  end
end

# The same scenarios as the browser sees them: the consent page, or an error
# page without a redirect.
class Oauth::ClientMetadataDocumentRequestTest < ActionDispatch::IntegrationTest
  URL = Oauth::ClientMetadataDocumentTest::URL

  setup do
    @original = Oauth::ClientMetadataDocument.resolver, Oauth::ClientMetadataDocument.transport
    @document = { client_id: URL, client_name: "Claude Code", redirect_uris: [ "http://localhost/callback", "http://127.0.0.1/callback" ] }
    @address = Oauth::ClientMetadataDocumentTest::PUBLIC_IP
    Oauth::ClientMetadataDocument.resolver = ->(_host) { [ @address ] }
    @transport = Oauth::ClientMetadataDocumentTest::FakeTransport.new(-> {
      Oauth::ClientMetadataDocument::Response.new(status: 200, content_type: "application/json", body: JSON.generate(@document))
    })
    Oauth::ClientMetadataDocument.transport = @transport
    oauth_applications(:claude_code).destroy!
    sign_in_as users(:two)
  end

  teardown do
    Oauth::ClientMetadataDocument.resolver, Oauth::ClientMetadataDocument.transport = @original
  end

  def authorize(redirect_uri: "http://localhost:51234/callback")
    get oauth_authorization_path(response_type: "code", client_id: URL, redirect_uri: redirect_uri, scope: "read",
      state: "s", code_challenge: new_pkce.challenge, code_challenge_method: "S256")
  end

  def assert_error_page
    assert_response :bad_request
    assert_select "h1", "This app can't connect"
    assert_nil response.location
  end

  test "Claude Code: the consent page names the client as its document does" do
    authorize

    assert_response :success
    assert_select "h1", "localhost wants to access your Goalner account"
    assert_select "p", "The app calls itself Claude Code."
    assert_select "p", "Its details are published by claude.ai."
  end

  test "mismatched client id: an error page, no redirect, and no authorization possible" do
    @document[:client_id] = "https://evil.example/metadata"

    authorize
    assert_error_page
    post oauth_authorization_path, params: { response_type: "code", client_id: URL, redirect_uri: "http://localhost:51234/callback",
      scope: "read", state: "s", code_challenge: new_pkce.challenge, code_challenge_method: "S256", access: "read" }
    assert_error_page
    assert_empty Oauth::AccessGrant.all
  end

  test "private address: an error page, and no request to it" do
    @address = "169.254.169.254"

    authorize

    assert_error_page
    assert_empty @transport.requests
  end

  test "unlisted redirect URI: an error page, no redirect" do
    authorize(redirect_uri: "https://evil.example/callback")

    assert_error_page
    assert_select "code", "invalid_redirect_uri"
  end
end
