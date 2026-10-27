// The part of swagger-ui-dist that entrypoints/api-docs.ts uses; the package
// ships no type declarations.
declare module "swagger-ui-dist/swagger-ui-bundle.js" {
  interface SwaggerRequest {
    url: string
    credentials?: RequestCredentials
    // Set on the request that fetches the OpenAPI document.
    loadSpec?: boolean
  }

  interface SwaggerUIOptions {
    domNode: HTMLElement
    url: string
    deepLinking?: boolean
    persistAuthorization?: boolean
    requestInterceptor?: (request: SwaggerRequest) => SwaggerRequest
  }

  export default function SwaggerUIBundle(options: SwaggerUIOptions): unknown
}
