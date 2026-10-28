// The API documentation page, /api/docs (spec api-documentation): Swagger UI
// over the OpenAPI document. A separate entry point, so the viewer never
// becomes part of the single-page application.
import SwaggerUIBundle from "swagger-ui-dist/swagger-ui-bundle.js"
import "swagger-ui-dist/swagger-ui.css"
import "../styles/fonts.css"
import "../styles/tokens.css"
import "../styles/api-docs.css"

const root = document.getElementById("api-docs")
const url = root?.dataset.documentUrl

if (root && url) {
  SwaggerUIBundle({
    domNode: root,
    url,
    deepLinking: true,
    // The token entered under "Authorize" lives only in this page.
    persistAuthorization: false,
    // "Try it out" behaves like an external client: only the entered token
    // authenticates it, never the session cookie (design.md, decision 7). The
    // document itself is for signed-in users, so its request keeps the cookie.
    requestInterceptor: (request) => {
      if (!request.loadSpec) request.credentials = "omit"
      return request
    },
  })
}
