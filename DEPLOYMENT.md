# Deployment

Steps on the production server that the repository cannot do for you. The
settings of both roles and the nginx routes of the MCP server are in the
[README](README.md), under "MCP server", "Running it".

## nginx: drop the service key header

nginx must remove `X-Goalner-Service-Key` from every request it forwards to
the web role.

### Why

The API reads this header to tell requests that came through the MCP server
from direct ones. That is how an agent token issued for MCP only, or for the
API only, is enforced. The header's value is `MCP_SERVICE_KEY`, the same key
that guards the connection token exchange at `/internal/`.

The MCP server reaches the web role over the private network
(`GOALNER_API_URL: http://kamal-proxy`) and never passes nginx. Everything
else arrives through nginx. So once nginx drops the header, only the MCP
server can present the key.

Without this step, `/api` accepts the header from the internet:

- a leaked key, together with an MCP-only agent token, lets its holder call
  the API directly;
- the holder of a single-channel agent token can test guesses of the key,
  because a wrong key is answered with `invalid_service_key`.

### The change

In the `server` block of goalner.com, find each `location` that proxies to
the web role (the one that sends "everything else" to kamal-proxy) and add
the last line:

```nginx
location / {
    # ... the lines you already have: proxy_pass, Host and so on ...

    # Only the MCP server may present the service key, and it does not pass nginx.
    proxy_set_header X-Goalner-Service-Key "";
}
```

An empty value makes nginx leave the header out of the forwarded request.

Check two things in the same file:

- **The line is inside the `location`,** next to its other `proxy_set_header`
  lines. nginx inherits `proxy_set_header` from the `server` level only into
  locations that set no headers of their own. A line at the `server` level
  alone is ignored by any location that sets `Host`.
- **`underscores_in_headers` is off.** That is the default, so the directive
  should not appear at all. With it on, a request can carry
  `X_Goalner_Service_Key`, which the application reads as the same header and
  which the line above does not drop.

The `/mcp` and `/.well-known/oauth-protected-resource` locations need no
change. The MCP server ignores this header on incoming requests and sends its
own.

Then test the configuration and reload:

```sh
sudo nginx -t && sudo systemctl reload nginx
```

### When

Before the first release that has agents, or at any time after it. No outside
caller has a reason to send this header, so dropping it breaks nothing. Done
first, the API never reads the key from the internet.

### Verify

The check needs agent tokens, so it runs once agents are deployed. From a
machine outside the server, with an agent token issued for one channel and a
made-up key:

```sh
curl -s https://goalner.com/api/me \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -H "X-Goalner-Service-Key: made-up"
```

| Token | Before the nginx change | After |
|---|---|---|
| API only | 401, `invalid_service_key` | 200, the agent's profile |
| MCP only | 401, `invalid_service_key` | 401, `invalid_token` |

`invalid_service_key` in the answer means the header still reaches the
application.

Then confirm that MCP is unaffected: an MCP-only agent token still lists
tools at `https://goalner.com/mcp`.

### What this relies on

All outside traffic reaches the web role through nginx. If kamal-proxy's port
can be reached from the internet directly, a request can go around nginx with
the header. Confirm that the port listens on localhost only or is closed by
the firewall.
