# Existing Cloudflared and Caddy

Select the existing tunnel that serves the intended domain. Attach Vellum AIO to the Docker network shared by Cloudflared and Caddy, which is `proxynet` in the example template. Point the tunnel origin to Caddy's existing HTTP listener. Within Caddy, send the assistant hostname to Vellum AIO.

```caddyfile
http://assistant.example.com {
    reverse_proxy vellum-aio:7840 {
        header_up X-Forwarded-Proto https
    }
}
```

Use the HTTP example when Cloudflare terminates TLS and forwards HTTP to Caddy. If your tunnel already uses HTTPS to Caddy, add `reverse_proxy vellum-aio:7840` to the existing HTTPS site block instead. Retain the original hostname in the request to Caddy. Add the new hostname to the existing tunnel with the same origin/listener pattern as its other Caddy sites. Adjust the example to the actual hostname and listener. No host port mapping is needed when Caddy and AIO share Docker DNS.

Caddy handles WebSocket upgrades and flushes event streams. If you rely on the gateway's per-client rate limiting, configure Caddy's trusted proxy handling for the existing tunnel hop. Caddy will otherwise treat that hop as the client IP. Use your existing security policy for the Cloudflare hostname and exercise pairing, token refresh, SSE and WebSocket behavior before enforcing challenges that a native client cannot answer. [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)

From the intended hostname, verify that `/` redirects to `/assistant/`, `/assistant/__config` reports `remote-gateway`, and `/readyz` reports `ready:true`. Then pair and send a message from each target client.
