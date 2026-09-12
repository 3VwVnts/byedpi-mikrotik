# byedpi-mikrotik

[![Build & Push multiarch](https://github.com/3VwVnts/byedpi-mikrotik/actions/workflows/build.yml/badge.svg)](https://github.com/3VwVnts/byedpi-mikrotik/actions/workflows/build.yml)
[![Generate antifilter RSC](https://github.com/3VwVnts/byedpi-mikrotik/actions/workflows/gen-rsc.yml/badge.svg)](https://github.com/3VwVnts/byedpi-mikrotik/actions/workflows/gen-rsc.yml)
[![Latest release](https://img.shields.io/github/v/release/3VwVnts/byedpi-mikrotik?display_name=tag)](https://github.com/3VwVnts/byedpi-mikrotik/releases/latest)
[![License](https://img.shields.io/github/license/3VwVnts/byedpi-mikrotik)](LICENSE)

Локальный обход блокировок на MikroTik через Docker-контейнер.
**ByeDPI** (обход DPI) + **HevSocks5Tunnel** (заворот трафика в SOCKS5).  
Whitelist через [antifilter.download](https://antifilter.download).  
Селективная маршрутизация — средствами RouterOS. **Без внешних VPS.**

Собран под **ARMv7 / ARM64 / AMD64**. Образ в `ghcr.io`, обновляется автоматически через GitHub Actions.

## Возможности

- ✅ Обход жёстких блокировок РФ (TCP/TLS)
- ✅ Whitelist-маршрутизация (только список → туннель, остальное напрямую)
- ✅ Плавный YouTube (QUIC→TCP fallback, низкая нагрузка на CPU)
- ✅ Автообновление образа и списков
- ✅ Конфигурация через ENV

## Требования

- MikroTik с поддержкой Container (RouterOS 7.x)
- Включённый `container mode`
- ~200 MB свободной RAM под tmpfs (или USB-накопитель)

---

## ⚠️ ВАЖНО: прочитайте перед установкой

Этот проект **вмешивается в ваш firewall**. Готовые `.rsc` заточены под конкретную
тестовую конфигурацию. **У вас firewall может отличаться** — не импортируйте вслепую!

Обязательно посмотрите свои правила:

```
/ip/firewall/filter/print
/ip/firewall/mangle/print
/ip/firewall/nat/print
```

Понимание вашего firewall критично для двух вещей:

1. **Default Deny** — если у вас в конце `chain=forward` стоит `action=drop`,
   то разрешающие правила для контейнера **должны стоять ВЫШЕ него**.
2. **Fasttrack** — фасттрекнутые соединения игнорируют mangle-маркировку.

---

## Архитектура обхода

```
┌─────────┐   dst в списке?   ┌──────────────┐   ByeDPI    ┌───────────┐
│  LAN    │──── да ──────────▶│  mangle mark │────────────▶│ container │──▶ Интернет
│ клиент  │                   │ routing-mark │  (обход DPI)│ (SOCKS5)  │   (обход)
└─────────┘                   └──────────────┘             └───────────┘
     │
     └──── нет ──────────────▶ обычный маршрут (напрямую, без обхода)
```

- Трафик к адресам из `za_dpi_FWD` (antifilter) → маркируется → уходит в контейнер
- Всё остальное → идёт обычным путём (ваш дефолтный шлюз)
- Контейнер = ByeDPI (SOCKS5 :1080) + HevSocks5Tunnel (TUN внутри)
- Наружу контейнер отдаёт себя как IP-шлюз через `veth` в `Bridge-Docker`

---

## Что делают правила firewall (объяснение)

### 1. Разрешения в `chain=forward` (файл `04-quic-firewall.rsc`)

```rsc
# LAN может слать трафик в контейнер
chain=forward action=accept in-interface-list=LAN out-interface=BYEDPI-TUN
# Контейнер может отвечать в LAN
chain=forward action=accept in-interface=BYEDPI-TUN out-interface-list=LAN
```

**Зачем:** если у вас строгий Default Deny (`chain=forward action=drop` в конце),
без этих правил трафик в контейнер будет **зарезан**. Эти правила ставятся ВЫШЕ drop.

### 2. NAT для контейнера (файл `03-routing.rsc`)

```rsc
chain=srcnat action=masquerade out-interface=BYEDPI-TUN
```

**Зачем:** контейнер должен видеть трафик с адреса роутера, чтобы корректно
маршрутизировать ответы обратно.

### 3. Маркировка + routing-mark (файл `03-routing.rsc`)

```rsc
# Метим соединения к адресам из whitelist
chain=prerouting action=mark-connection dst-address-list=za_dpi_FWD ...
# Направляем помеченное в отдельную таблицу маршрутизации
chain=prerouting action=mark-routing new-routing-mark=dpi_mark ...
```

**Зачем:** это сердце селективной маршрутизации — только адреса из списка идут в туннель.

### 4. Блок QUIC (файл `04-quic-firewall.rsc`)

```rsc
chain=forward protocol=udp dst-port=443 dst-address-list=za_dpi_FWD action=drop
```

**Зачем:** YouTube активно использует QUIC (UDP/443). QUIC-обход сильно грузит
слабый CPU. Проще заблокировать QUIC для bypass-адресов — браузер откатится
на TCP/443, который обходится ByeDPI **без нагрузки** и без лагов.

### 5. MSS clamp (файл `03-routing.rsc`)

```rsc
chain=forward action=change-mss new-mss=clamp-to-pmtu out-interface=BYEDPI-TUN
```

**Зачем:** предотвращает фрагментацию TLS через туннель, стабилизирует соединения.

---

## 🔧 Адаптация под ваш firewall (ОБЯЗАТЕЛЬНО)

### Проблема `place-before`

В `.rsc` разрешающие правила вставляются так:

```rsc
place-before=[find where chain=forward action=drop comment~"Default Deny"]
```

Это работает, **только если** ваше правило Default Deny имеет в комментарии
подстроку `Default Deny`. Проверьте:

```
/ip/firewall/filter/print where chain=forward action=drop
```

**Если у вас другой комментарий** — отредактируйте `.rsc`, заменив `Default Deny`
на подстроку из вашего комментария. Либо вставьте вручную:

```rsc
# узнать номер правила drop
/ip/firewall/filter/print
# вставить перед ним (допустим drop = правило N)
/ip/firewall/filter add ... place-before=N
```

**Если у вас НЕТ Default Deny** (политика forward = accept по умолчанию) —
разрешающие правила не обязательны, но не помешают. Уберите `place-before`.

### Проверка порядка mangle

Маркировка **должна стоять выше** ваших MSS-правил и любых других mangle:

```
/ip/firewall/mangle/print
```

Если `Mark bypass` / `Route bypass` оказались ниже — подвиньте вверх:

```rsc
/ip/firewall/mangle move [find comment~"Mark bypass"] destination=0
/ip/firewall/mangle move [find comment~"Route bypass"] destination=1
```

### Проверка Fasttrack

Если у вас fasttrack ловит весь LAN→WAN трафик, убедитесь, что он **не фасттрекает**
трафик в контейнер. Обычно fasttrack привязан к `out-interface-list=WAN`,
а контейнер в `Bridge-Docker` — тогда всё ок. Проверьте свой fasttrack:

```
/ip/firewall/filter/print where action=fasttrack-connection
```

---

## Быстрый старт

### 1. Форкните репозиторий

GitHub Actions соберёт образ и опубликует в `ghcr.io/ВАШ_ЛОГИН/byedpi-tun:latest`.
После первого билда сделайте пакет **Public**:
`Packages → byedpi-tun → Package settings → Change visibility → Public`

### 2. Проверьте container mode

```
/system/device-mode/print
```

Если `container: no` — включите:

```
/system/device-mode/update container=yes
```

(потребует подтверждения по инструкции MikroTik — reset button / reboot)

### 3. Настройте хранилище

- **С USB:** используйте путь USB в `root-dir` / `tmpdir`
- **Без USB (tmpfs, образ в RAM):** используется `01`/`02` .rsc с tmpfs
  > ⚠️ tmpfs = образ в ОЗУ. После перезагрузки роутера образ стирается
  > и тянется заново (нужен интернет при старте). Health-check это учитывает.

### 4. Импортируйте конфиги ПО ПОРЯДКУ

```
/import mikrotik/01-network.rsc
/import mikrotik/02-container.rsc          # заменив ВАШ_ЛОГИН
/import mikrotik/03-routing.rsc
/import mikrotik/04-quic-firewall.rsc
/import mikrotik/05-antifilter-script.rsc  # заменив ВАШ_ЛОГИН
/import mikrotik/06-healthcheck.rsc        # заменив ВАШ_ЛОГИН
```

Или всё сразу (после редактирования ВАШ_ЛОГИН):

```
/import mikrotik/setup-all.rsc
```

### 5. Наполните список и запустите

```
/system/script run update-antifilter
/container start [find interface=BYEDPI-TUN]
```

---

## Релизы и версии

Проект версионируется по [SemVer](https://semver.org/lang/ru/):

- `vX.Y.Z` — стабильные релизы. Образ публикуется с тегами `vX.Y.Z`, `vX.Y`, `vX`, `latest`.
- При ломающих изменениях (переименование ENV, изменение интерфейсов контейнера) — `MAJOR`.
- При новых фичах — `MINOR`.
- При обновлении ByeDPI/Hev и багфиксах — `PATCH`.

Готовые `.rsc` и `.sh` прикреплены к каждому релизу: [Releases](https://github.com/3VwVnts/byedpi-mikrotik/releases).

Если хочется стабильности — используйте `ghcr.io/3vwvnts/byedpi-tun:v1.0.0` вместо `:latest`.

---

## Конфигурация (ENV)

| Переменная   | Дефолт                          | Описание                                                      |
| ------------ | ------------------------------- | ------------------------------------------------------------- |
| `CMD`        | `-Kt,h -An -a5 -s1+s -s2+h -T3` | Стратегия ByeDPI (TCP)                                        |
| `QUIC`       | `REJECT`                        | `REJECT`/`0` = не туннелировать UDP; `ACCEPT` = туннелировать |
| `SOCKS_PORT` | `1080`                          | Порт SOCKS5                                                   |
| `MTU`        | `8500`                          | MTU туннеля                                                   |
| `TUN_IP`     | `172.16.0.1`                    | Внутренний IP TUN-интерфейса внутри контейнера                |

### Смена стратегии на лету

```rsc
/container/envs set [find key=CMD] value="-Kt,h -An -s1+s"
/container/stop  [find interface=BYEDPI-TUN]
/container/start [find interface=BYEDPI-TUN]
```

---

## Стратегии ByeDPI (если что-то не открывается / YouTube лагает)

```
# Скорость (минимализм)
-Kt,h -An -s1+s

# Баланс (дефолт)
-Kt,h -An -a5 -s1+s -s2+h -T3

# Пробить любой ценой (медленнее, больше нагрузка)
-Kt,h -s0+s -s3+s -s6+s -s9+s -s12+s -An -a5
```

> Стратегии DPI устаревают — следите за обновлениями ByeDPI и корректируйте `CMD`.

---

## Диагностика

```rsc
# Список наполнился?
/ip/firewall/address-list/print count-only where list=za_dpi_FWD

# Контейнер работает?
/container/print

# Логи ByeDPI
/log/print where message~"byedpi"

# Трафик идёт в туннель?
/tool/torch interface=BYEDPI-TUN

# Проверка маршрута через таблицу обхода
/ping youtube.com routing-table=dpi_mark
```

С клиента LAN:

```bash
curl -I https://www.youtube.com
```

---

## Структура проекта

```
Dockerfile                  — сборка образа
entrypoint.sh               — запуск ByeDPI + туннеля, обработка ENV
tun.yml.template            — шаблон конфига HevSocks5Tunnel
.github/workflows/
  build.yml                 — автосборка образа (multiarch)
  gen-rsc.yml               — генерация antifilter.rsc + автокоммит
  release.yml               — публикация semver-релизов (запуск по тегу)
mikrotik/
  01-network.rsc            — bridge + veth
  02-container.rsc          — tmpfs + контейнер + ENV
  03-routing.rsc            — routing table + mangle + NAT + MSS
  04-quic-firewall.rsc      — accept-правила forward + блок QUIC
  05-antifilter-script.rsc  — загрузка списка + scheduler
  06-healthcheck.rsc        — мониторинг туннеля + авто-восстановление
  setup-all.rsc             — всё одним файлом
scripts/
  gen-antifilter-rsc.sh     — генератор списка для GitHub Actions
dist/
  antifilter.rsc            — генерируется автоматически (не редактировать)
```

---

## ⚠️ Отказ от ответственности

Firewall-правила в этом репозитории **примеры**. Ваша конфигурация может отличаться.
Всегда проверяйте правила перед импортом и делайте бэкап:

```
/export file=backup-before-byedpi
/system/backup/save name=backup-before-byedpi
```

---

## 💛 Благодарность и поддержка проекта

Спасибо, что пользуетесь проектом! Если он сэкономил вам время, помог обойти блокировки или просто сделал интернет чуть свободнее — вы можете поблагодарить автора добровольным донатом. Любая поддержка, тёплое слово или звезда на GitHub мотивируют развивать проект дальше.

Это **не обязательно** и не даёт дополнительных прав или гарантий. Это просто искренняя благодарность, если проект оказался вам полезен. ❤️

| Сеть / Актив  | Адрес                                                            |
| ------------- | ---------------------------------------------------------------- |
| X Layer       | `XKO8eb329af7b4a5c52806cdf8e2fcbab468220434f`                    |
| USDT (ERC20)  | `0x3a0c0646ffcbe722d5a7c8ab734572f5eadfe204`                     |
| USDT (TRC20)  | `TG87SKh3qy3weXTJ1qYiTy9JkxGfbu1VMK`                             |
| BTC (Bitcoin) | `bc1qaustvvuqgvs8646mtfcuta4nx4tzk73a7e8t9tem0rddddyh8zaqmys6mv` |
| GRAM (TON)    | `UQAD5MNWOZj1czohZRccWfTHqpue9XG7xIrdNC_Udo2akpt6`               |

> ⚠️ Пожалуйста, перед отправкой внимательно проверьте сеть и адрес. Криптовалютные переводы необратимы. Отправляйте только те активы, которые соответствуют указанной сети.

Спасибо за поддержку! 🙏

---

## Лицензия

MIT
