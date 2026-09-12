#!/bin/sh
set -e

LIST_NAME="za_dpi_FWD"
SRC_URL="https://antifilter.network/download/ipsmart.lst"
OUT_DIR="dist"
OUT_FILE="${OUT_DIR}/antifilter.rsc"

mkdir -p "$OUT_DIR"

echo "Downloading antifilter ipsmart list..."
curl -f -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
     "$SRC_URL" -o /tmp/ipsmart.lst

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
  done < /tmp/ipsmart.lst
} > "$OUT_FILE"

COUNT=$(grep -c '^add ' "$OUT_FILE" || true)
echo "Done. Entries: $COUNT -> $OUT_FILE"
