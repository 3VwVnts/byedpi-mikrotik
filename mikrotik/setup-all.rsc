# ==========================================================
#  BYEDPI-MIKROTIK — ПОЛНАЯ УСТАНОВКА (v1.1.0)
#  Собрано под RB4011iGS+5HacQ2HnD / RouterOS 7.24.2
#
#  ПЕРЕД ИМПОРТОМ:
#    1. Проверьте, что container mode включён - on
#    2. Замените ВАШ_ЛОГИН на свой GitHub-логин (в 3 местах)
#    3. Сделайте бэкап: /export file=backup-before-byedpi
#
#  ВАЖНО:
#    - Правила вставляются ПЕРЕД "forward: Drop all other (Default Deny)".
#      Если у вас другой комментарий у Default Deny — замените вручную.
#    - Правила mangle вставляются в НАЧАЛО цепочки prerouting/forward.
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

# ---- 2. tmpfs + контейнер ----
/disk
add type=tmpfs tmpfs-max-size=200M slot=docker

/container/config
set registry-url=https://ghcr.io tmpdir=docker/pull

/container/envs
add list=byedpi key=QUIC       value="REJECT"
add list=byedpi key=CMD        value="-Kt,h -An -a5 -s1+s -s2+h -T3"
add list=byedpi key=SOCKS_PORT value="1080"
add list=byedpi key=MTU        value="1400"

/container
add remote-image=ghcr.io/3VwVnts/byedpi-tun:latest \
    interface=BYEDPI-TUN root-dir=docker/byedpi \
    envlists=byedpi start-on-boot=yes logging=yes \
    comment="ByeDPI + HevSocks5Tunnel"

# ---- 3. Маршрутизация ----
/routing/table
add disabled=no fib name=dpi_mark

/ip/route
add disabled=no distance=1 dst-address=0.0.0.0/0 \
    gateway=192.168.254.2%Bridge-Docker routing-table=dpi_mark \
    comment="Bypass traffic -> ByeDPI"

# ---- 4. NAT ----
# 4.1. NAT для контейнера в интернет (ВАЖНО — без этого пакеты уходят с приватным IP)
/ip/firewall/nat
add chain=srcnat action=masquerade src-address=192.168.254.0/24 out-interface-list=WAN \
    comment="NAT: ByeDPI to WAN"
# 4.2. NAT для трафика клиентов в контейнер (для корректного возврата)
add chain=srcnat action=masquerade out-interface=Bridge-Docker \
    comment="NAT: LAN to ByeDPI"

# ---- 5. Firewall: forward accept + блок QUIC ----
# Все правила вставляются ПЕРЕД вашим "forward: Drop all other (Default Deny)"
# Если у вас другое имя — замените подстроку в place-before.
/ip/firewall/filter

# 5.1. LAN -> контейнер (клиенты)
add chain=forward action=accept in-interface-list=LAN out-interface=Bridge-Docker \
    place-before=[find where comment~"Drop all other"] \
    comment="forward: LAN to ByeDPI"

# 5.2. Контейнер -> LAN (ответы клиентам)
add chain=forward action=accept in-interface=Bridge-Docker out-interface-list=LAN \
    place-before=[find where comment~"Drop all other"] \
    comment="forward: ByeDPI to LAN"

# 5.3. Контейнер -> WAN (ByeDPI идёт в интернет)
add chain=forward action=accept in-interface=Bridge-Docker out-interface-list=WAN \
    place-before=[find where comment~"Drop all other"] \
    comment="forward: ByeDPI to WAN"

# 5.4. WAN -> контейнер (ответы из интернета)
add chain=forward action=accept in-interface-list=WAN out-interface=Bridge-Docker \
    place-before=[find where comment~"Drop all other"] \
    comment="forward: WAN to ByeDPI"

# 5.5. Блок QUIC (UDP/443) для bypass-адресов -> YouTube откатится на TCP
add chain=forward protocol=udp dst-port=443 dst-address-list=za_dpi_FWD \
    action=drop \
    place-before=[find where comment~"Drop all other"] \
    comment="Block QUIC for bypass -> TCP fallback"

# ---- 6. Mangle: маркировка + MSS clamp ----
# 6.1. MSS clamp для трафика в контейнер (важно для TLS handshake)
/ip/firewall/mangle
add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes \
    tcp-flags=syn protocol=tcp out-interface=Bridge-Docker \
    place-before=0 comment="Mangle: Fix ByeDPI MSS OUT"
add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes \
    tcp-flags=syn protocol=tcp in-interface=Bridge-Docker \
    place-before=1 comment="Mangle: Fix ByeDPI MSS IN"

# 6.2. Маркировка bypass-соединений (ставим в самое начало prerouting)
add action=mark-connection chain=prerouting connection-mark=no-mark \
    dst-address-list=za_dpi_FWD in-interface-list=LAN \
    new-connection-mark=to_dpi passthrough=yes \
    place-before=0 comment="Mark bypass conn"
add action=mark-routing chain=prerouting connection-mark=to_dpi \
    in-interface-list=LAN new-routing-mark=dpi_mark \
    passthrough=no routing-mark=!dpi_mark \
    place-before=1 comment="To DPI table"

# ---- 7. DNS: DoH через IP (обход подмены DNS провайдером) ----
# Cloudflare DoH через IP 1.1.1.1 (сертификат не проверяем — работает по IP)
/ip/dns
set use-doh-server="https://1.1.1.1/dns-query" verify-doh-cert=no \
    servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes
/ip/dns/cache/flush

# ---- 9. Antifilter: автообновление списка ----
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

# ---- 10. Health-check: авто-восстановление контейнера после ребута ----
/system/script
add name=byedpi-healthcheck dont-require-permissions=no policy=read,write,test \
    source={
    :local containerIf "BYEDPI-TUN"
    :local containerImage "ghcr.io/3VwVnts/byedpi-tun:latest"
    :local maxFails 3
    :global byedpiFails
    :if ([:typeof $byedpiFails] = "nothing") do={ :set byedpiFails 0 }

    # ЭТАП 1: контейнер существует?
    :local cIdx [/container/find where interface=$containerIf]
    :if ([:len $cIdx] = 0) do={
        :log warning "byedpi-hc: container missing -> re-creating"
        :do {
            /container/add \
                remote-image=$containerImage \
                interface=$containerIf root-dir=docker/byedpi \
                envlists=byedpi start-on-boot=yes logging=yes
            :delay 10s
            /container/start [find where interface=$containerIf]
            :log info "byedpi-hc: container re-created and started"
        } on-error={ :log error "byedpi-hc: re-add failed" }
        :return
    }

    # ЭТАП 2: контейнер в статусе running?
    :local ok false
    :if ([:len [/container/find where interface=$containerIf and status=running]] > 0) do={
        :set ok true
    } else={
        :log warning "byedpi-hc: container not running"
    }

    # ЭТАП 3: реакция
    :if ($ok) do={
        :if ($byedpiFails > 0) do={
            :log info "byedpi-hc: recovered after $byedpiFails fails"
        }
        :set byedpiFails 0
    } else={
        :set byedpiFails ($byedpiFails + 1)
        :log warning "byedpi-hc: check FAILED ($byedpiFails/$maxFails)"
        :if ($byedpiFails >= $maxFails) do={
            :log error "byedpi-hc: restarting container"
            :do {
                /container/stop [find where interface=$containerIf]
                :delay 5s
                /container/start [find where interface=$containerIf]
            } on-error={
                :do { /container/start [find where interface=$containerIf] } on-error={}
            }
            :set byedpiFails 0
        }
    }
}
/system/scheduler
add name=byedpi-healthcheck interval=2m on-event=byedpi-healthcheck \
    comment="ByeDPI health monitor + tmpfs recovery"

# ---- 11. Первый запуск ----
/system/script run update-antifilter
:delay 5s
/container start [find where interface=BYEDPI-TUN]
