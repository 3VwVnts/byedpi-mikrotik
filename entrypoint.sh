#!/busybox sh
# ByeDPI + HevSocks5Tunnel entrypoint
# Все параметры переопределяются через ENV в /container/envs

# ---- Дефолты (оптимизировано под быстрый YouTube на ARMv7) ----
: "${CMD:=-Kt,h -An -a5 -s1+s -s2+h -T3}"
: "${QUIC:=REJECT}"
: "${TUN_IP:=172.16.0.1}"
: "${SOCKS_PORT:=1080}"
: "${MTU:=8500}"

echo "[byedpi] starting ciadpi: ${CMD}"

# ---- ByeDPI (SOCKS5 на 1080) ----
/ciadpi --ip 127.0.0.1 --port "${SOCKS_PORT}" ${CMD} &
BYEDPI_PID=$!

# ---- Генерация конфига туннеля ----
/busybox sed \
    -e "s|__TUN_IP__|${TUN_IP}|g" \
    -e "s|__PORT__|${SOCKS_PORT}|g" \
    -e "s|__MTU__|${MTU}|g" \
    /tun.yml.template > /tun.yml

# ---- QUIC REJECT => не гоняем UDP через туннель (экономим CPU ARMv7) ----
if [ "$QUIC" = "REJECT" ] || [ "$QUIC" = "0" ]; then
    /busybox sed -i "s|udp: 'udp'|udp: 'tcp'|g" /tun.yml
fi

# ---- Watchdog: если ByeDPI умрёт — валим контейнер, чтобы RouterOS перезапустил ----
/busybox sh -c "while kill -0 ${BYEDPI_PID} 2>/dev/null; do sleep 5; done; echo '[byedpi] ciadpi died!'; kill 1" &

# ---- Туннель (foreground, держит контейнер) ----
exec /tun2socks /tun.yml
