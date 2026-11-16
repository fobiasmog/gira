# Spec Delta

## MODIFIED Requirements

### Requirement: Connection tokens
A connection token SHALL be issued only to the MCP server, in exchange for a valid access token of an MCP connection (spec `mcp-authorization`), presented together with the MCP server's service key. An access token SHALL count as valid for the exchange whichever of Goalner's current or previous signing keys signed it. A connection token SHALL reach the projects and access level of that connection. It SHALL expire no later than that access token, and SHALL stop authenticating when the connection ends. Every other rule of this spec SHALL apply to it as to a personal token.

#### Scenario: Exchange
- **WHEN** the MCP server presents its service key and a valid access token of Alice's read-write connection
- **THEN** it receives a connection token that expires no later than the access token, and requests with it act as Alice in all of her non-archived projects

#### Scenario: Wrong service key
- **WHEN** a request presents a valid access token with a missing or wrong service key
- **THEN** the response is HTTP 401 and no token is issued

#### Scenario: Ended connection
- **WHEN** the MCP server presents an access token of a connection that has ended
- **THEN** the response is HTTP 401 and no token is issued

#### Scenario: Disconnected while in use
- **WHEN** Alice disconnects a connection whose connection token has not yet expired
- **THEN** the next request with that connection token receives HTTP 401

#### Scenario: Read-only connection
- **WHEN** a connection token of a read-only connection is used to create a task
- **THEN** the response is HTTP 403 with the code `insufficient_scope`

#### Scenario: Not a personal token
- **WHEN** a user with connection tokens lists their API tokens
- **THEN** no connection token is listed, and connection tokens do not count toward the limit of 20

#### Scenario: Previous signing key
- **WHEN** Goalner's signing key has just been replaced, and the MCP server presents a live access token that the previous key signed
- **THEN** it receives a connection token
