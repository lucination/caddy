# caddy-cloudflare

[Caddy](https://caddyserver.com) built with two extra modules, published as a
multi-arch Alpine image for `linux/amd64` and `linux/arm64`.

| Module | Upstream | What it does |
| --- | --- | --- |
| `dns.providers.cloudflare` | [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare) | ACME **DNS-01** challenges via the Cloudflare API — lets you issue certs for hosts that are not publicly reachable, and wildcard certs. |
| `http.handlers.replace_response` | [caddyserver/replace-response](https://github.com/caddyserver/replace-response) | String/regex substitution in response bodies as they are proxied through. |

## Images

```
ghcr.io/lucination/caddy-cloudflare:latest
docker.io/lucination/caddy-cloudflare:latest
```

Tags: `latest`, `<caddy-version>` (e.g. `2.11.4`), `<caddy-version>-alpine`, and
`sha-<short>`. Both registries carry identical multi-arch manifests.

```bash
docker run --rm ghcr.io/lucination/caddy-cloudflare:latest version
docker run --rm ghcr.io/lucination/caddy-cloudflare:latest list-modules | grep -E 'cloudflare|replace_response'
```

## Cloudflare API token

DNS-01 needs a **scoped API token** (not the Global API Key). In the Cloudflare
dashboard → My Profile → API Tokens → Create Token → *Edit zone DNS*:

- Permissions: `Zone / DNS / Edit`
- Also add `Zone / Zone / Read` — Caddy looks the zone up before writing the record.
- Zone Resources: limit it to the specific zone(s) you actually serve.

Pass it as `CF_API_TOKEN`. Keep it in a file or secret store, not in the
Caddyfile and not baked into an image.

## Caddyfile

```caddyfile
{
    email you@example.com
}

# Wildcard cert issued over DNS-01 — no port 80/443 ingress needed.
*.example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
        resolvers 1.1.1.1
    }

    @app host app.example.com
    handle @app {
        reverse_proxy upstream:8080
    }

    handle {
        respond "no such host" 404
    }
}

# replace-response rewriting an upstream that hardcodes its own origin.
docs.example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy docs-backend:3000
    replace {
        # replace-response needs the upstream uncompressed to see the body
        stream
        "http://docs-backend:3000" "https://docs.example.com"
    }
}
```

`replace` with a plain string is a literal swap; `re` makes it a regex:

```caddyfile
replace {
    re "(?i)<script[^>]*analytics[^>]*></script>" ""
}
```

> **Note:** `replace-response` can only rewrite bodies it can read. If the
> upstream returns compressed content, either add `stream` inside the `replace`
> block or send `Accept-Encoding: identity` upstream via
> `header_up Accept-Encoding identity`.

## docker compose

```yaml
services:
  caddy:
    image: ghcr.io/lucination/caddy-cloudflare:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"   # HTTP/3
    environment:
      # Read from a .env file beside the compose file; never commit the value.
      CF_API_TOKEN: ${CF_API_TOKEN:?set CF_API_TOKEN in .env}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data      # certs + ACME account keys — MUST persist
      - caddy_config:/config
volumes:
  caddy_data:
  caddy_config:
```

A ready-to-run [`docker-compose.yml`](./docker-compose.yml) is in the repo.

**Persist `/data`.** It holds your certificates and ACME account key. Losing it
means re-issuing everything and burning Let's Encrypt rate limits.

## Healthcheck

The image ships a `HEALTHCHECK` that polls Caddy's admin API on
`127.0.0.1:2019` with busybox `wget` (already in the Alpine base — no extra
packages). The admin endpoint is loopback-only by default and is not exposed
outside the container.

If you disable the admin API (`admin off`) the healthcheck will fail. In that
case override it in compose:

```yaml
healthcheck:
  test: ["CMD", "wget", "--spider", "-q", "-T", "3", "http://127.0.0.1:80/"]
```

## Building locally

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t caddy-cloudflare:dev .

# a specific Caddy version
docker buildx build --build-arg CADDY_VERSION=2.11.4 -t caddy-cloudflare:dev .
```

The builder stage pins itself to `$BUILDPLATFORM` and cross-compiles with
`GOOS`/`GOARCH` + `CGO_ENABLED=0`, so the arm64 image is compiled natively on an
amd64 host rather than under QEMU emulation. That takes the arm64 build from
"tens of minutes" to roughly the same as amd64, and produces a fully static
binary with no libc dependency.

## CI

`.github/workflows/build.yml` builds both architectures and pushes to GHCR and
Docker Hub on every push to `main`, on `v*` tags, and weekly so base-image
security fixes get picked up. After pushing, CI pulls **each architecture back
out of the registry** and asserts both modules are present in
`caddy list-modules` — a successful compile alone does not prove the plugins
were linked in.

Docker Hub pushes need repo secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

## License

This packaging is MIT. Caddy is Apache-2.0; the bundled modules are licensed by
their respective upstreams.
