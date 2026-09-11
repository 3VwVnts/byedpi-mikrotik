# syntax=docker/dockerfile:1

# ============ ByeDPI (статическая сборка) ============
FROM alpine:3.20 AS byedpi
ARG BYEDPI_VER=v0.17.3
RUN apk add --no-cache git make gcc musl-dev linux-headers
WORKDIR /src
RUN git clone --depth 1 --branch ${BYEDPI_VER} https://github.com/hufrea/byedpi . \
    && make CFLAGS="-static -O2" LDFLAGS="-static" \
    && strip ciadpi

# ============ HevSocks5Tunnel (статическая сборка) ============
FROM alpine:3.20 AS tun
ARG HEV_VER=2.14.4
RUN apk add --no-cache git make gcc musl-dev linux-headers
WORKDIR /src
RUN git clone --depth 1 --branch ${HEV_VER} --recursive \
        https://github.com/heiher/hev-socks5-tunnel . \
    && make static \
    && strip bin/hev-socks5-tunnel

# ============ Минимальный финальный образ (scratch ~4-5Mb) ============
FROM scratch
COPY --from=byedpi /src/ciadpi                 /ciadpi
COPY --from=tun    /src/bin/hev-socks5-tunnel  /tun2socks
COPY --from=byedpi /bin/busybox                /busybox
COPY entrypoint.sh      /entrypoint.sh
COPY tun.yml.template   /tun.yml.template

ENTRYPOINT ["/busybox", "sh", "/entrypoint.sh"]
# trigger
