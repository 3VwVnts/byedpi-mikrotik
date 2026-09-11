# ==========================================================
#  BYEDPI-MIKROTIK  —  ПОЛНАЯ УСТАНОВКА
#  Собрано под RB4011iGS+5HacQ2HnD / RouterOS 7.24.2
#
#  ПЕРЕД ИМПОРТОМ:
#    1. container mode проверить что включен - on
#    2. Замените ВАШ_ЛОГИН на свой GitHub-логин (в 3 местах!)
#    3. Сделайте бэкап: /export file=backup-before-byedpi
# ==========================================================

# ---- 1. Сеть: bridge + veth для контейнера ----
/interface/bridge
add name=Bridge-Docker port-cost-mode=long comment="ByeDPI container bridge"

/ip/address
add address=192.168.254.1/24 interface=Bridge-Docker network=192.168.254.0

/interface/veth
add address=192.168.254.2/24 gateway=192.168.254.1 name=BYEDPI-TUN

/interface/bridge/port
add bridge=Bridge-Docker interface=BYEDPI-TUN

# ---- 2. tmpfs + контейнер (образ живёт в RAM, ~200MB) ----
/disk
add type=tmpfs tmpfs-max-size=200M slot=docker

/container/config
set registry-url=https://ghcr.io tmpdir=docker/pull

/container/envs
add list=byedpi key=QUIC       value="REJECT"
add list=byedpi key=CMD        value="-Kt,h -An -a5 -s1+s -s2+h -T3"
add list=byedpi key=SOCKS_PORT value="1080"
add list=byedpi key=MTU        value="8500"

/container
add remote-image=ghcr.io/3VwVnts/byedpi-tun:latest \
    interface=BYEDPI-TUN root-dir=docker/byedpi \
    envlists=byedpi start-on-boot=yes logging=yes \
    comment="ByeDPI + HevSocks5Tunnel"

# ---- 3. Маршрутизация: таблица + маркировка + NAT + MSS ----
/routing/table
add disabled=no fib name=dpi_mark

/ip/route
add disabled=no distance=1 dst-address=0.0.0.0/0 \
    gateway=192.168.254.2%Bridge-Docker routing-table=dpi_mark \
    comment="Bypass traffic -> ByeDPI"

# NAT для контейнера
/ip/firewall/nat
add chain=srcnat action=masquerade out-interface=BYEDPI-TUN \
    comment="NAT: LAN to ByeDPI"

# Маркировка bypass-соединений
# ВАЖНО: ставим ВЫШЕ ваших MSS-правил mangle (3-6)
/ip/firewall/mangle
add action=mark-connection chain=prerouting connection-mark=no-mark \
    dst-address-list=za_dpi_FWD in-interface-list=LAN \
    new-connection-mark=to_dpi passthrough=yes \
    place-before=[find where chain=forward comment~"Fix L2TP MSS Out"] \
    comment="Mark bypass conn"
add action=mark-routing chain=prerouting connection-mark=to_dpi \
    in-interface-list=LAN new-routing-mark=dpi_mark \
    passthrough=no routing-mark=!dpi_mark \
    place-before=[find where chain=forward comment~"Fix L2TP MSS Out"] \
    comment="To DPI table"

# MSS clamp для ByeDPI
add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes \
    tcp-flags=syn protocol=tcp out-interface=BYEDPI-TUN \
    comment="Mangle: Fix ByeDPI MSS"

# ---- 4. Firewall: разрешения forward + блок QUIC ----
# Все правила вставляем ПЕРЕД вашим "Drop all other (Default Deny)"
/ip/firewall/filter
add chain=forward action=accept in-interface-list=LAN out-interface=BYEDPI-TUN \
    place-before=[find where chain=forward action=drop comment~"Drop all other"] \
    comment="forward: LAN to ByeDPI"
add chain=forward action=accept in-interface=BYEDPI-TUN out-interface-list=LAN \
    place-before=[find where chain=forward action=drop comment~"Drop all other"] \
    comment="forward: ByeDPI to LAN"

# Блок QUIC -> YouTube откатится на TCP (обходится ByeDPI без нагрузки на CPU)
add chain=forward protocol=udp dst-port=443 dst-address-list=za_dpi_FWD \
    action=drop \
    place-before=[find where chain=forward action=drop comment~"Drop all other"] \
    comment="Block QUIC for bypass -> TCP fallback"

# ---- 5. Antifilter: автообновление списка ----
/system/script
add name=update-antifilter dont-require-permissions=no policy=read,write,test,ftp \
    source={
    :do {
        /tool/fetch \
            url="https://raw.githubusercontent.com/3VwVnts/byedpi-mikrotik/main/dist/antifilter.rsc" \
            mode=https dst-path=antifilter.rsc
        :delay 3s
        /import file-name=antifilter.rsc
        :log info "antifilter: imported OK"
    } on-error={ :log error "antifilter: update failed" }
}
/system/scheduler
add name=antifilter-update interval=1d start-time=04:00:00 \
    on-event=update-antifilter comment="Daily antifilter refresh"

# ---- 6. Health-check: мониторинг + авто-восстановление (tmpfs) ----
/system/script
add name=byedpi-healthcheck dont-require-permissions=no policy=read,write,test,ftp \
    source={
    :local checkHost "youtube.com"
    :local containerIf "BYEDPI-TUN"
    :local maxFails 3
    :global byedpiFails
    :if ([:typeof $byedpiFails] = "nothing") do={ :set byedpiFails 0 }

    # Контейнер существует? (tmpfs мог стереть после ребута)
    :local cExists [:len [/container/find interface=$containerIf]]
    :if ($cExists = 0) do={
        :log warning "byedpi-hc: container missing -> re-adding"
        :do {
            /container/add \
                remote-image=ghcr.io/3VwVnts/byedpi-tun:latest \
                interface=$containerIf root-dir=docker/byedpi \
                envlists=byedpi start-on-boot=yes logging=yes
            :delay 10s
            /container/start [find interface=$containerIf]
        } on-error={ :log error "byedpi-hc: re-add failed" }
        :return
    }

    # Проверка туннеля через таблицу dpi_mark
    :local ok false
    :do {
        :local ip [:resolve $checkHost]
        :local res [/ping $ip count=3 routing-table=dpi_mark interval=1]
        :if ($res > 0) do={ :set ok true }
    } on-error={ :set ok false }
    :local cStatus [/container/get [find interface=$containerIf] status]
    :if ($cStatus != "running") do={ :set ok false }

    :if ($ok) do={
        :set byedpiFails 0
    } else={
        :set byedpiFails ($byedpiFails + 1)
        :log warning "byedpi-hc: FAILED ($byedpiFails/$maxFails)"
        :if ($byedpiFails >= $maxFails) do={
            :log error "byedpi-hc: restarting container"
            :do {
                /container/stop [find interface=$containerIf]
                :delay 5s
                /container/start [find interface=$containerIf]
            } on-error={ :do { /container/start [find interface=$containerIf] } on-error={} }
            :set byedpiFails 0
        }
    }
}
/system/scheduler
add name=byedpi-healthcheck interval=2m on-event=byedpi-healthcheck \
    comment="ByeDPI health monitor + tmpfs recovery"

# ---- 7. Первый запуск: список + контейнер ----
/system/script run update-antifilter
:delay 5s
/container start [find interface=BYEDPI-TUN]

# ==========================================================
#  ГОТОВО. Проверьте порядок правил:
#    /ip/firewall/mangle/print   (Mark/Route bypass ДОЛЖНЫ быть выше MSS)
#    /ip/firewall/filter/print   (accept + QUIC ДОЛЖНЫ быть выше правила 17)
#  Диагностика:
#    /container/print
#    /log/print where message~"byedpi"
#    /ip/firewall/address-list/print count-only where list=za_dpi_FWD
# ==========================================================
