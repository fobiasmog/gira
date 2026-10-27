# The OpenAPI document of the token API (spec api-documentation), for
# signed-in users to read or import into their tools. Not opened to tokens.
class Api::OpenapiController < Api::BaseController
  DOCUMENT = Rails.root.join("docs/openapi.yaml")

  def show
    response.headers["Cache-Control"] = "private, no-store"
    send_file DOCUMENT, type: "application/yaml", disposition: :inline
  end
end
