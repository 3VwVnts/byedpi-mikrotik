# ==========================================================
#  HEALTH-CHECK: авто-восстановление контейнера после ребута
#  Требует policy: read,write,test
# ==========================================================
/system/script
add name=byedpi-healthcheck dont-require-permissions=no policy=read,write,test \
    source={
    :local containerIf "BYEDPI-TUN"
    :local containerImage "ghcr.io/3VwVnts/byedpi-tun:latest"
    :local maxFails 3
    :global byedpiFails
    :if ([:typeof $byedpiFails] = "nothing") do={ :set byedpiFails 0 }

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

    :local ok false
    :if ([:len [/container/find where interface=$containerIf and status=running]] > 0) do={
        :set ok true
    } else={
        :log warning "byedpi-hc: container not running"
    }

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
