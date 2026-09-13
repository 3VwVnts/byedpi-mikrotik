# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.20

# ============ ByeDPI (статическая сборка) ============
FROM alpine:${ALPINE_VERSION} AS byedpi
ARG BYEDPI_VER=v0.17.3
RUN apk add --no-cache git make gcc musl-dev linux-headers
WORKDIR /src
RUN git clone --depth 1 --branch "${BYEDPI_VER}" https://github.com/hufrea/byedpi . \
    && make CFLAGS="-static -O2" LDFLAGS="-static" \
    && strip ciadpi

# ============ HevSocks5Tunnel (статическая сборка) ============
FROM alpine:${ALPINE_VERSION} AS tun
ARG HEV_VER=2.17.1
RUN apk add --no-cache git make gcc musl-dev linux-headers
WORKDIR /src
RUN git clone --depth 1 --branch "${HEV_VER}" --recursive \
        https://github.com/heiher/hev-socks5-tunnel . \
    && make CFLAGS="-static -O2" LDFLAGS="-static" \
    && strip bin/hev-socks5-tunnel

# ============ Статический busybox ============
FROM busybox:stable-musl AS busybox

# ============ Минимальный финальный образ (scratch) ============
FROM scratch

LABEL org.opencontainers.image.title="byedpi-tun" \
      org.opencontainers.image.description="ByeDPI + HevSocks5Tunnel в минимальном образе" \
      org.opencontainers.image.source="https://github.com/3VwVnts/byedpi-mikrotik" \
      org.opencontainers.image.licenses="MIT"

COPY --from=byedpi  /src/ciadpi                /ciadpi
COPY --from=tun     /src/bin/hev-socks5-tunnel /tun2socks
COPY --from=busybox /bin/busybox               /busybox

COPY entrypoint.sh      /entrypoint.sh
COPY tun.yml.template   /tun.yml.template

WORKDIR /
ENTRYPOINT ["/busybox", "sh", "/entrypoint.sh"]
