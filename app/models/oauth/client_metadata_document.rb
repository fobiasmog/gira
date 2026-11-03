# Client ID metadata documents (spec mcp-authorization, "Client ID metadata
# documents"; add-mcp-oauth design.md, decision 4). A client id that is an
# HTTPS URL names the JSON document at that URL, which says who the client is
# and where it may redirect. Claude's apps and Claude Code use them.
#
# 1. The URL: https, no userinfo or fragment, a path other than "/", at most
#    255 characters.
# 2. The fetch, built against SSRF: the host is resolved once, and every
#    address must be public (no private, loopback, link-local, multicast,
#    reserved, or IPv4-mapped ones). The request goes to that address with the
#    original name for SNI and Host, so a second DNS answer cannot redirect
#    it. 3 seconds in total, 5 KB at most, application/json only, and
#    redirects are not followed.
# 3. The document: its client_id is the URL, its redirect_uris are HTTPS or
#    HTTP loopback URIs, it asks for no client secret, and its client_name
#    has at most 100 characters (the URL's host when absent).
# 4. It is stored as a public application ("cimd", uid = URL) and reused for
#    24 hours. A redirect URI the stored copy does not list triggers a
#    refetch, at most once a minute per URL.
#
# Every failure raises Error; the authorization request then gets an error
# page and no redirect, since nothing about the client can be trusted yet.
class Oauth::ClientMetadataDocument
  class Error < StandardError; end

  MAX_URL_LENGTH = 255
  MAX_BYTES = 5 * 1024
  MAX_NAME_LENGTH = 100
  REUSE_FOR = 24.hours
  REFETCH_INTERVAL = 1.minute

  # Ranges no document may be fetched from, besides those IPAddr already
  # names private, loopback or link-local.
  BLOCKED_RANGES = %w[
    0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
    224.0.0.0/4 240.0.0.0/4
    ::/128 64:ff9b::/96 64:ff9b:1::/48 100::/64 2001::/23 2001:db8::/32 2002::/16 fc00::/7 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  Response = Data.define(:status, :content_type, :body)

  # GET over HTTPS to an address chosen beforehand, reading at most
  # max_bytes. Redirects are answered, not followed.
  class HttpTransport
    class TooLarge < StandardError; end

    def get(uri, address:, timeout:, max_bytes: MAX_BYTES)
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = http.ssl_timeout = http.read_timeout = http.write_timeout = timeout
      http.max_retries = 0

      http.start do
        request = Net::HTTP::Get.new(uri.request_uri, "Accept" => "application/json", "User-Agent" => "Goalner")
        http.request(request) do |response|
          raise TooLarge if response.content_length.to_i > max_bytes

          body = +""
          response.read_body do |chunk|
            body << chunk
            raise TooLarge if body.bytesize > max_bytes
          end
          return Response.new(status: response.code.to_i, content_type: response.content_type, body: body)
        end
      end
    end
  end

  # Each address the name resolves to, from the hosts file and DNS.
  RESOLVER = lambda do |host|
    dns = Resolv::DNS.new.tap { |resolver| resolver.timeouts = 1 }
    Resolv.new([ Resolv::Hosts.new, dns ]).getaddresses(host)
  ensure
    dns&.close
  end

  cattr_accessor :resolver, default: RESOLVER
  cattr_accessor :transport, default: HttpTransport.new
  cattr_accessor :timeout, default: 3

  def self.client_id?(value)
    value.is_a?(String) && value.start_with?("https://")
  end

  # The stored application for the document at url, fetched when it is not
  # stored, older than 24 hours, or does not list redirect_uri.
  def self.resolve(url, redirect_uri: nil)
    new(url).resolve(redirect_uri)
  end

  def initialize(url)
    @url = url
    @uri = parse_url(url)
  end

  def resolve(redirect_uri)
    application = Oauth::Application.cimd.find_by(uid: @url)
    return application if application && reusable?(application, redirect_uri)

    store(application || Oauth::Application.new(uid: @url, registration: :cimd), fetch)
  end

  private
    def parse_url(url)
      uri = URI.parse(url)
      valid = url.length <= MAX_URL_LENGTH && uri.is_a?(URI::HTTPS) && uri.host.present? &&
        uri.userinfo.nil? && uri.fragment.nil? && uri.path.present? && uri.path != "/"
      valid ? uri : raise(Error, "client id URL refused")
    rescue URI::InvalidURIError
      raise Error, "client id URL refused"
    end

    def reusable?(application, redirect_uri)
      fetched_at = application.metadata_fetched_at
      return false if fetched_at.nil? || fetched_at < REUSE_FOR.ago
      return true if fetched_at > REFETCH_INTERVAL.ago

      redirect_uri.blank? || Doorkeeper::OAuth::Helpers::URIChecker.valid_for_authorization?(redirect_uri, application.redirect_uri)
    end

    def fetch
      response = Timeout.timeout(timeout, Error, "client metadata document timed out") do
        transport.get(@uri, address: public_address, timeout: timeout)
      end
      raise Error, "client metadata document answered #{response.status}" unless response.status == 200
      raise Error, "client metadata document is not JSON" unless response.content_type == "application/json"
      raise Error, "client metadata document is too large" if response.body.bytesize > MAX_BYTES

      JSON.parse(response.body)
    rescue JSON::ParserError, HttpTransport::TooLarge, Timeout::Error, SystemCallError, IOError, SocketError,
           OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError, Resolv::ResolvError => error
      raise Error, "client metadata document refused: #{error.class}"
    end

    def public_address
      addresses = resolver.call(@uri.host)
      raise Error, "client id host does not resolve" if addresses.empty?
      raise Error, "client id host resolves to a non-public address" unless addresses.all? { |address| public?(address) }

      addresses.first
    end

    def public?(address)
      ip = IPAddr.new(address.to_s)
      !(ip.ipv4_mapped? || ip.ipv4_compat? || ip.private? || ip.loopback? || ip.link_local? ||
        BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) })
    rescue IPAddr::Error
      false
    end

    def store(application, document)
      application.update!(document_attributes(document).merge(confidential: false, metadata_fetched_at: Time.current))
      application
    rescue ActiveRecord::RecordInvalid
      raise Error, "client metadata document refused"
    rescue ActiveRecord::RecordNotUnique
      Oauth::Application.cimd.find_by!(uid: @url)
    end

    def document_attributes(document)
      raise Error, "client metadata document is not an object" unless document.is_a?(Hash)
      raise Error, "client_id does not match its URL" unless document["client_id"] == @url
      raise Error, "client asks for a client secret" unless document.fetch("token_endpoint_auth_method", "none") == "none"

      { name: client_name(document), redirect_uri: redirect_uris(document).join(" ") }
    end

    def redirect_uris(document)
      uris = document["redirect_uris"]
      valid = uris.is_a?(Array) && uris.any? && uris.all? { |uri| Oauth.allowed_redirect_uri?(uri) }
      valid ? uris : raise(Error, "redirect_uris refused")
    end

    def client_name(document)
      name = document["client_name"]
      return @uri.host if name.nil? || (name.is_a?(String) && name.strip.empty?)
      raise Error, "client_name refused" unless name.is_a?(String) && name.strip.length <= MAX_NAME_LENGTH

      name.strip
    end
end
