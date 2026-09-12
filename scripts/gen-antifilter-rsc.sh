#!/bin/sh
set -e

LIST_NAME="za_dpi_FWD"
OUT_DIR="dist"
OUT_FILE="${OUT_DIR}/antifilter.rsc"
TMP_FILE="/tmp/ipsmart.lst"

SRC_URLS="
https://antifilter.download/list/allyouneed.lst
https://antifilter.network/download/allyouneed.lst
https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/allyouneed.lst
"

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

mkdir -p "$OUT_DIR"

echo "Downloading antifilter list..."
DOWNLOADED=0
for SRC_URL in $SRC_URLS; do
  echo ">>> Trying: $SRC_URL"
  if curl -f -L --retry 3 --retry-delay 2 --connect-timeout 30 \
       -A "$UA" "$SRC_URL" -o "$TMP_FILE"; then
    echo ">>> SUCCESS: $SRC_URL"
    DOWNLOADED=1
    break
  else
    echo ">>> FAILED (exit code $?): $SRC_URL"
  fi
done

if [ "$DOWNLOADED" -eq 0 ]; then
  echo "ERROR: Could not download from any source. Aborting."
  exit 1
fi

if [ ! -s "$TMP_FILE" ]; then
  echo "ERROR: Downloaded file is empty. Aborting."
  exit 1
fi

LINES=$(wc -l < "$TMP_FILE" | tr -d ' ')
echo "Downloaded $LINES lines"

echo "Generating RouterOS .rsc..."
{
  echo "# Auto-generated antifilter list ($(date -u +%F))"
  echo "/ip firewall address-list"
  echo ":do { remove [find list=${LIST_NAME}] } on-error={}"
  while IFS= read -r line; do
    case "$line" in
      ""|"#"*) continue ;;
    esac
    echo "add list=${LIST_NAME} address=${line}"
  done < "$TMP_FILE"
} > "$OUT_FILE"

COUNT=$(grep -c '^add ' "$OUT_FILE" || true)
echo "Done. Entries: $COUNT -> $OUT_FILE"
