# ===== Сеть для контейнера: bridge + veth =====
/interface/bridge
add name=Bridge-Docker port-cost-mode=short

/ip/address
add address=192.168.254.1/24 interface=Bridge-Docker network=192.168.254.0

/interface/veth
add address=192.168.254.2/24 gateway=192.168.254.1 name=BYEDPI-TUN

/interface/bridge/port
add bridge=Bridge-Docker interface=BYEDPI-TUN
