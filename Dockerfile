# syntax=docker/dockerfile:1
#
# Caddy + caddy-dns/cloudflare + caddyserver/replace-response
#
# The builder stage is pinned to $BUILDPLATFORM and cross-compiles via
# GOOS/GOARCH. That keeps the (slow) Go compile native on the build host
# instead of running it under QEMU emulation for the arm64 target -- a
# multi-minute saving per arch, and it sidesteps emulated-toolchain flakiness.
# CGO_ENABLED=0 yields a fully static binary, so the musl runtime base needs
# no libc shims at all.

ARG CADDY_VERSION=2.11.4

FROM --platform=$BUILDPLATFORM caddy:${CADDY_VERSION}-builder-alpine AS builder

ARG TARGETOS
ARG TARGETARCH

RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    xcaddy build \
        --with github.com/caddy-dns/cloudflare \
        --with github.com/caddyserver/replace-response

FROM caddy:${CADDY_VERSION}-alpine

ARG CADDY_VERSION
LABEL org.opencontainers.image.title="caddy-cloudflare" \
      org.opencontainers.image.description="Caddy ${CADDY_VERSION} with the Cloudflare DNS (ACME DNS-01) and replace-response modules" \
      org.opencontainers.image.source="https://github.com/lucination/caddy-cloudflare" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.base.name="docker.io/library/caddy:${CADDY_VERSION}-alpine"

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Liveness via Caddy's own admin API on loopback. busybox wget ships in the
# alpine base, so this adds no packages and no attack surface.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --spider -q -T 3 http://127.0.0.1:2019/config/ || exit 1
