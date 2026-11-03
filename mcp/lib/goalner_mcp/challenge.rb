module GoalnerMcp
  # The 401 answers of /mcp (spec mcp-server, "Protected resource metadata";
  # add-mcp-oauth design.md, decision 9). Each points to the protected
  # resource metadata and names the scopes, so a client starts sign-in, or
  # refreshes when its token was refused (error="invalid_token").
  class Challenge
    SCOPE = "read write"

    attr_reader :resource_metadata_url

    def initialize(resource_metadata_url:)
      @resource_metadata_url = resource_metadata_url
    end

    def missing_token_response
      [ 401, { "www-authenticate" => header }, [] ]
    end

    def invalid_token_response
      [ 401, { "www-authenticate" => header(error: "invalid_token"), "content-type" => "application/json" },
        [ JSON.generate(error: "invalid_token") ] ]
    end

    def header(error: nil)
      parameters = []
      parameters << %(error="#{error}") if error
      parameters << %(resource_metadata="#{resource_metadata_url}")
      parameters << %(scope="#{SCOPE}")
      "Bearer #{parameters.join(", ")}"
    end
  end
end
