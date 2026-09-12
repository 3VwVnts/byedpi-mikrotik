#!/bin/sh
# Генератор RouterOS address-list из списков antifilter.
# Запускается вручную или по cron в GitHub Actions.

set -eu

# --- Настройки ---------------------------------------------------------------
LIST_NAME="za_dpi_FWD"
OUT_DIR="dist"
OUT_FILE="${OUT_DIR}/antifilter.rsc"
TMP_FILE="$(mktemp -t antifilter.XXXXXX.lst)"
MIN_LINES=1000

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Основной источник + зеркала. Порядок важен: чем выше, тем приоритетнее.
SRC_URLS="
https://antifilter.download/list/allyouneed.lst
https://antifilter.network/download/allyouneed.lst
https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/allyouneed.lst
"

# --- Уборка ------------------------------------------------------------------
trap 'rm -f "$TMP_FILE"' EXIT INT TERM

# --- Скачивание --------------------------------------------------------------
mkdir -p "$OUT_DIR"

echo "::group::Downloading antifilter list"
DOWNLOADED=0
for SRC_URL in $SRC_URLS; do
  echo ">>> Trying: $SRC_URL"
  rc=0
  curl -f -L --retry 3 --retry-delay 2 --connect-timeout 30 \
       -A "$UA" "$SRC_URL" -o "$TMP_FILE" || rc=$?
  if [ "$rc" -eq 0 ]; then
    LINES=$(wc -l < "$TMP_FILE" | tr -d ' ')
    if [ "$LINES" -ge "$MIN_LINES" ]; then
      echo ">>> SUCCESS: $SRC_URL ($LINES lines)"
      DOWNLOADED=1
      break
    else
      echo ">>> Suspiciously small ($LINES lines), trying next source..."
    fi
  else
    echo ">>> FAILED (exit code $rc): $SRC_URL"
  fi
done
echo "::endgroup::"

if [ "$DOWNLOADED" -eq 0 ]; then
  echo "::error::Could not download from any source. Aborting."
  exit 1
fi

# --- Генерация ---------------------------------------------------------------
echo "::group::Generating RouterOS .rsc"
{
  echo "# Auto-generated antifilter list ($(date -u +%F))"
  echo "# Source: $SRC_URL"
  echo "/ip firewall address-list"
  echo ":do { remove [find list=${LIST_NAME}] } on-error={}"
  while IFS= read -r line; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    echo "add list=${LIST_NAME} address=${line}"
  done < "$TMP_FILE"
} > "$OUT_FILE"
echo "::endgroup::"

COUNT=$(grep -c '^add ' "$OUT_FILE" || true)
echo "Done. Entries: $COUNT -> $OUT_FILE"
