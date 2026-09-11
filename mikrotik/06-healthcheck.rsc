# ==========================================================
#  HEALTH-CHECK: проверка туннеля + авто-восстановление (tmpfs)
#  Требует policy: read,write,test
# ==========================================================
/system/script
add name=byedpi-healthcheck dont-require-permissions=no \
    policy=read,write,test source={

    # --- Настройки ---
    :local checkHost "youtube.com"
    :local containerIf "BYEDPI-TUN"
    :local maxFails 3
    :local failVarName "byedpiFails"

    # Плейсхолдер: замените на актуальный образ при деплое
    :local containerImage "ghcr.io/3VwVnts/byedpi-tun:latest"

    # --- Инициализация глобального счётчика неудач ---
    :global byedpiFails
    :if ([:typeof $byedpiFails] = "nothing") do={ :set byedpiFails 0 }

    # ---- ЭТАП 1: Проверка существования контейнера ----
    # Критично для tmpfs/root-dir: после ребута контейнер может исчезнуть
    :local cExists [:len [/container/find interface=$containerIf]]
    :if ($cExists = 0) do={
        :log warning "byedpi-hc: container '$containerIf' missing -> re-creating"
        :do {
            /container/add \
                remote-image=$containerImage \
                interface=$containerIf \
                root-dir=docker/byedpi \
                envlists=byedpi \
                start-on-boot=yes logging=yes
            :delay 10s
            /container/start [find interface=$containerIf]
            :log info "byedpi-hc: container re-created and started"
        } on-error={
            :log error "byedpi-hc: FAILED to re-create container"
        }
        # Прерываемся: даём контейнеру время подняться перед следующей проверкой
        :return
    }

    # ---- ЭТАП 2: Проверка доступности туннеля ----
    # Резолвим цель и пингуем ЧЕРЕЗ таблицу маршрутизации туннеля
    :local ok false
    :do {
        :local ip [:resolve $checkHost]
        :local res [/ping $ip count=3 routing-table=dpi_mark interval=1]
        :if ($res > 0) do={ :set ok true }
    } on-error={ :set ok false }

    # ---- ЭТАП 3: Проверка статуса контейнера ----
    :local cStatus [/container/get [find interface=$containerIf] status]
    :if ($cStatus != "running") do={
        :set ok false
        :log warning "byedpi-hc: container not running (status=$cStatus)"
    }

    # ---- ЭТАП 4: Реакция на результат ----
    :if ($ok) do={
        # Успех: сбрасываем счётчик, логируем восстановление если были сбои
        :if ($byedpiFails > 0) do={
            :log info "byedpi-hc: recovered after $byedpiFails fails"
        }
        :set byedpiFails 0
    } else={
        # Неудача: инкрементируем счётчик
        :set byedpiFails ($byedpiFails + 1)
        :log warning "byedpi-hc: check FAILED ($byedpiFails/$maxFails)"

        # При достижении порога — перезапуск
        :if ($byedpiFails >= $maxFails) do={
            :log error "byedpi-hc: max fails reached -> restarting container"
            :do {
                /container/stop [find interface=$containerIf]
                :delay 5s
                /container/start [find interface=$containerIf]
            } on-error={
                # Fallback: если stop/start не сработал, пробуем просто start
                :log warning "byedpi-hc: restart failed, trying force start"
                :do { /container/start [find interface=$containerIf] } on-error={}
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
