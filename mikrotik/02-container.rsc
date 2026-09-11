# ===== ВНИМАНИЕ: перед запуском включить container mode =====
#   /system/device-mode/update container=yes
#   (потребует физического подтверждения — reset/power по инструкции RouterOS)

# ===== tmpfs (образ живёт в RAM! макс 200MB) =====
/disk
add type=tmpfs tmpfs-max-size=200M slot=docker

# ===== Реестр (ghcr.io) + tmpdir в tmpfs =====
/container/config
set registry-url=https://ghcr.io tmpdir=docker/pull

# ===== ENV (замените стратегию при необходимости) =====
/container/envs
add list=byedpi key=QUIC       value="REJECT"
add list=byedpi key=CMD        value="-Kt,h -An -a5 -s1+s -s2+h -T3"
add list=byedpi key=SOCKS_PORT value="1080"
add list=byedpi key=MTU        value="8500"

# ===== Контейнер (ЗАМЕНИТЕ ВАШ_ЛОГИН!) =====
/container
add remote-image=ghcr.io/3VwVnts/byedpi-tun:latest \
    interface=BYEDPI-TUN \
    root-dir=docker/byedpi \
    envlists=byedpi \
    start-on-boot=yes \
    logging=yes \
    comment="ByeDPI + HevSocks5Tunnel"
