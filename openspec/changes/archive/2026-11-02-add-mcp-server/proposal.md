# Proposal

## Why

Personal API tokens let scripts call the API, but AI assistants such as Claude Code, Cursor and claude.ai talk to services through the Model Context Protocol (MCP), not REST. A user who wants an assistant to read their board or file tasks has to write a wrapper first. An MCP server that offers the token API as tools lets any MCP client work with Goalner.

This is the first of two changes. It serves MCP with the personal tokens that exist today, which already works in Claude Code and Cursor. `add-mcp-oauth` then adds sign-in for claude.ai, which needs OAuth.

## What Changes

- A new MCP server answers at `https://goalner.com/mcp`. It speaks the MCP Streamable HTTP transport, statelessly, with JSON responses, so any instance can answer any request.
- The server runs as its own process from this repository (`bin/mcp`), next to the main application. It reaches Goalner only through the existing API over the private network:
  - it has no business logic;
  - it does not boot Rails;
  - it has no database access.

  A reverse proxy (nginx) sends `/mcp` to it and everything else to the main application.
- Tools: one per JSON operation in `docs/openapi.yaml`, which is 35 of the 37 (the two file downloads are left out).
  - Each tool is named by its `operationId` and takes the operation's path, query and body parameters as inputs.
  - Its description comes from the document.
  - Read operations are marked read-only and deletions destructive.

  The tool list follows the document automatically, so `bin/openapi-verify` keeps the tools and the API in step as well.
- A tool call becomes exactly one API request made with the caller's credential. Every API rule therefore applies unchanged:
  - the token's project and access level;
  - the endpoint allowlist;
  - the limit of 300 requests a minute;
  - attribution to the token's owner.
- Authentication: `Authorization: Bearer <personal API token>`, forwarded to the API unchanged. A request without a token, or with a token the API rejects, receives HTTP 401. A token in the URL is ignored.
- API errors become tool errors that carry the error code, the message and the field messages, so the assistant can correct its input. Unexpected failures give a generic message.
- Logs record the MCP method, the tool, the API status and the duration, never tokens, arguments or results. Requests from a foreign browser origin are refused.
- Development and deployment:
  - `bin/dev` starts the MCP server at `http://localhost:3100/mcp`;
  - `config/deploy.yml` gains an `mcp` role;
  - the README explains how to connect Claude Code and other clients with a personal token, and how to route `/mcp` in nginx.

Not included:
- OAuth sign-in, claude.ai connectors, and connections that reach all of a user's projects. These come in `add-mcp-oauth`, which builds on this change;
- MCP resources and prompts, and file downloads as tools;
- tools that combine several API requests or accept names instead of ids;
- configuring the production nginx, which is operated outside this repository.

## Capabilities

### New Capabilities

- `mcp-server`: the MCP endpoint. Covers the transport, authentication, the tool set and how it follows the API document, how tool calls map to API requests and results, error handling, log privacy, and the server's isolation from the database.

### Modified Capabilities

None. The API and its token rules are unchanged; the MCP server is one more client of them.

## Impact

- **New code:**
  - `mcp/`: a Rack application with the server, the tool builder, the API client and the token verifier;
  - `bin/mcp`.
- **Dependencies:** the `mcp` gem (1.8.x) in a new `mcp` Gemfile group, which Rails does not load.
- **Changed files:**
  - `bin/dev`;
  - `config/deploy.yml`: an `mcp` role, with the Rails secrets moved to the `web` role;
  - `README.md`.
- **Tests:** `test/mcp/` in the default suite. It runs the MCP application against the Rails application in-process.
- **Existing behavior:** the main application's code, routes, schema and web client are unchanged.
