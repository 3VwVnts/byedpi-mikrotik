# Changelog

Все значимые изменения проекта документируются здесь.  
Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),  
проект придерживается [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

## [1.0.0] — 2026-09-12

Первый публичный релиз.

### Added

- Docker-образ `ghcr.io/3vwvnts/byedpi-tun` под `linux/amd64`, `linux/arm64`, `linux/arm/v7`.
- ByeDPI (обход DPI) + HevSocks5Tunnel (TUN → SOCKS5) в минимальном образе (scratch).
- Автогенерация `dist/antifilter.rsc` из multi-source списков antifilter (3 источника с fallback).
- Автопубликация образа через GitHub Actions (`build.yml`) при push в `main`.
- Набор MikroTik-скриптов `mikrotik/01-…06-…` + `setup-all.rsc` для установки одной командой.
- Health-check с авто-восстановлением контейнера после перезагрузки (tmpfs).
- Поддержка ENV: `CMD`, `QUIC`, `SOCKS_PORT`, `MTU`, `TUN_IP`.

### Notes

- Список `za_dpi_FWD` обновляется ежедневно в 02:00 UTC через `gen-rsc.yml`.
- Образ пересобирается по понедельникам в 03:00 UTC + при изменениях `Dockerfile`/`entrypoint.sh`.

[Unreleased]: https://github.com/3VwVnts/byedpi-mikrotik/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/3VwVnts/byedpi-mikrotik/releases/tag/v1.0.0
