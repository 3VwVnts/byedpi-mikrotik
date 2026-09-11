# ===== Routing table + маркировка + NAT + MSS для ByeDPI =====
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
/ip/firewall/mangle
add action=mark-connection chain=prerouting connection-mark=no-mark \
    dst-address-list=za_dpi_FWD in-interface-list=LAN \
    new-connection-mark=to_dpi passthrough=yes \
    comment="Mark bypass connections"
add action=mark-routing chain=prerouting connection-mark=to_dpi \
    in-interface-list=LAN new-routing-mark=dpi_mark \
    passthrough=no routing-mark=!dpi_mark \
    comment="Route bypass to DPI table"

# MSS clamp для ByeDPI
/ip/firewall/mangle
add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes \
    tcp-flags=syn protocol=tcp out-interface=BYEDPI-TUN \
    comment="Mangle: Fix ByeDPI MSS"
