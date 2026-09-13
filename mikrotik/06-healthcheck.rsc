# ==========================================================
#  HEALTH-CHECK: проверка статуса контейнера + авто-восстановление (tmpfs)
#  Требует policy: read,write,test
# ==========================================================
/system/script
add name=byedpi-healthcheck dont-require-permissions=no \
    policy=read,write,test source={

    # --- Настройки ---
    :local containerIf "BYEDPI-TUN"
    :local containerImage "ghcr.io/3VwVnts/byedpi-tun:latest"
    :local maxFails 3

    # --- Инициализация глобального счётчика неудач ---
    :global byedpiFails
    :if ([:typeof $byedpiFails] = "nothing") do={ :set byedpiFails 0 }

    # ---- ЭТАП 1: Проверка существования контейнера ----
    # Критично для tmpfs: после ребута контейнер может исчезнуть
    :local cIdx [/container/find where interface=$containerIf]
    :if ([:len $cIdx] = 0) do={
        :log warning "byedpi-hc: container '$containerIf' missing -> re-creating"
        :do {
            /container/add \
                remote-image=$containerImage \
                interface=$containerIf \
                root-dir=docker/byedpi \
                envlists=byedpi \
                start-on-boot=yes logging=yes
            :delay 10s
            /container/start [find where interface=$containerIf]
            :log info "byedpi-hc: container re-created and started"
        } on-error={
            :log error "byedpi-hc: FAILED to re-create container"
        }
        :return
    }

    # ---- ЭТАП 2: Чтение статуса контейнера (совместимо с RouterOS 7.x) ----
    :local cStatus "unknown"
    :do {
        :set cStatus [/container/get value-name=status $cIdx]
    } on-error={
        :log warning "byedpi-hc: cannot read container status"
        :set cStatus "error"
    }

    # ---- ЭТАП 3: Проверка интерфейса контейнера ----
    :local ok false
    :if ($cStatus = "running") do={
        :set ok true
    } else={
        :log warning "byedpi-hc: container not running (status=$cStatus)"
    }

    # ---- ЭТАП 4: Реакция на результат ----
    :if ($ok) do={
        :if ($byedpiFails > 0) do={
            :log info "byedpi-hc: recovered after $byedpiFails fails"
        }
        :set byedpiFails 0
    } else={
        :set byedpiFails ($byedpiFails + 1)
        :log warning "byedpi-hc: check FAILED ($byedpiFails/$maxFails)"

        :if ($byedpiFails >= $maxFails) do={
            :log error "byedpi-hc: max fails reached -> restarting container"
            :do {
                /container/stop [find where interface=$containerIf]
                :delay 5s
                /container/start [find where interface=$containerIf]
            } on-error={
                :log warning "byedpi-hc: restart failed, trying force start"
                :do { /container/start [find where interface=$containerIf] } on-error={}
            }
            :set byedpiFails 0
        }
    }
}

# --- Планировщик: проверка каждые 2 минуты ---
/system/scheduler
add name=byedpi-healthcheck interval=2m \
    on-event=byedpi-healthcheck \
    comment="ByeDPI health monitor + tmpfs recovery"
