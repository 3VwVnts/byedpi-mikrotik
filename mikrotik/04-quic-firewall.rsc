# ===== Firewall: разрешения для ByeDPI + блок QUIC =====

/ip/firewall/filter
add chain=forward action=accept in-interface-list=LAN out-interface=BYEDPI-TUN \
    place-before=[find where chain=forward action=drop comment~"Default Deny"] \
    comment="forward: LAN to ByeDPI"
add chain=forward action=accept in-interface=BYEDPI-TUN out-interface-list=LAN \
    place-before=[find where chain=forward action=drop comment~"Default Deny"] \
    comment="forward: ByeDPI to LAN"

# Блок QUIC -> YouTube откатится на TCP (обходится ByeDPI)
add chain=forward protocol=udp dst-port=443 dst-address-list=za_dpi_FWD \
    action=drop \
    place-before=[find where chain=forward action=drop comment~"Default Deny"] \
    comment="Block QUIC for bypass (smooth YouTube via TCP)"
