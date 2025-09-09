#!/usr/bin/env bash
set -Eeuo pipefail

show_help() {
  cat <<'EOF'
Uso:
  recon.sh -u dominio.com          # Ejecuta contra un solo dominio
  recon.sh -l targets.txt          # Ejecuta contra varios (uno por línea; ignora vacíos y líneas que empiecen con #)
  recon.sh -h                      # Ayuda

Salidas (por target):
  results/<target>/report.md
  results/<target>/report.html

NOTA: No se generan archivos por herramienta; solo esos 2 por dominio.
EOF
  exit 1
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[!] Falta '$1' en PATH."; MISSING=1; }; }
sanitize() { echo "$1" | tr -dc 'a-zA-Z0-9._-'; }
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }

[ $# -eq 0 ] && show_help
MODE=""; INPUT=""
while getopts ":u:l:h" opt; do
  case "$opt" in
    u) MODE="single"; INPUT="$OPTARG" ;;
    l) MODE="list";   INPUT="$OPTARG" ;;
    h) show_help ;;
    *) show_help ;;
  esac
done

MISSING=0
for c in subfinder assetfinder gau dnsx httpx jq; do require_cmd "$c"; done
[ $MISSING -eq 1 ] && { echo "[!] Instalá las dependencias y reintentá."; exit 2; }

BASE_DIR="$(pwd)/results"
mkdir -p "$BASE_DIR"

run_recon() {
  local target_raw="$1"
  local target; target="$(sanitize "$target_raw")"
  [ -z "$target" ] && return 0

  echo -e "\n======================================="
  echo "Target: $target"
  echo "======================================="

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN   # limpia aunque falle algo

  # 1) Subdominios (subfinder + assetfinder)
  subfinder -silent -d "$target" -o "$tmp/subfinder.txt" || true
  assetfinder --subs-only "$target" | sort -u > "$tmp/assetfinder.txt" || true
  cat "$tmp/subfinder.txt" "$tmp/assetfinder.txt" 2>/dev/null | sort -u > "$tmp/subs.txt" || true
  local count_subs; count_subs=$(wc -l < "$tmp/subs.txt" 2>/dev/null || echo 0)

  # 2) DNS (dnsx)
  dnsx -silent -l "$tmp/subs.txt" -o "$tmp/resolved.txt" || true
  local count_dns; count_dns=$(wc -l < "$tmp/resolved.txt" 2>/dev/null || echo 0)

  # 3) HTTP vivos (httpx JSON → HTML tabla)
  httpx -silent -l "$tmp/resolved.txt" \
    -status-code -title -tech-detect -follow-redirects -no-color -json \
    -o "$tmp/httpx.json" || true

  jq -r '.url' "$tmp/httpx.json" 2>/dev/null | sed '/^$/d' | sort -u > "$tmp/alive_urls.txt" || true
  local count_alive; count_alive=$(wc -l < "$tmp/alive_urls.txt" 2>/dev/null || echo 0)

  # 4) URLs históricas (gau)
  gau "$target" | sort -u > "$tmp/urls.txt" || true
  local count_urls; count_urls=$(wc -l < "$tmp/urls.txt" 2>/dev/null || echo 0)

  # 5) Otros (no resueltos / resueltos sin HTTP)
  comm -23 <(sort -u "$tmp/subs.txt" || true) <(sort -u "$tmp/resolved.txt" || true) > "$tmp/unresolved.txt" || true
  awk -F/ '{print $3}' "$tmp/alive_urls.txt" 2>/dev/null | sed '/^$/d' | sort -u > "$tmp/alive_hosts.txt" || true
  comm -23 <(sort -u "$tmp/resolved.txt" || true) <(sort -u "$tmp/alive_hosts.txt" || true) > "$tmp/resolved_no_http.txt" || true

  # 6) Salidas finales (solo 2 archivos por dominio)
  local out_dir="${BASE_DIR}/${target}"
  mkdir -p "$out_dir"

  # -- Markdown
  {
    echo "# Recon Report – ${target}"
    echo
    echo "## Resumen"
    echo "- Subdominios: ${count_subs}"
    echo "- DNS OK: ${count_dns}"
    echo "- HTTP vivos: ${count_alive}"
    echo "- URLs (gau): ${count_urls}"
    echo
    echo "## Subdominios (subfinder + assetfinder)"
    if [ -s "$tmp/subs.txt" ]; then cat "$tmp/subs.txt"; else echo "_(sin resultados)_"; fi
    echo
    echo "## Subdominios vivos (httpx)"
    if [ -s "$tmp/alive_urls.txt" ]; then cat "$tmp/alive_urls.txt"; else echo "_(sin resultados)_"; fi
    echo
    echo "## URLs (gau)"
    if [ -s "$tmp/urls.txt" ]; then cat "$tmp/urls.txt"; else echo "_(sin resultados)_"; fi
    echo
    echo "## Otros"
    echo "- No resueltos (DNS): $(wc -l < "$tmp/unresolved.txt" 2>/dev/null || echo 0)"
    [ -s "$tmp/unresolved.txt" ] && sed 's/^/  - /' "$tmp/unresolved.txt"
    echo "- Resueltos sin HTTP vivo: $(wc -l < "$tmp/resolved_no_http.txt" 2>/dev/null || echo 0)"
    [ -s "$tmp/resolved_no_http.txt" ] && sed 's/^/  - /' "$tmp/resolved_no_http.txt"
    echo
    echo "_Generado: $(date -u +"%Y-%m-%d %H:%M:%S UTC")_"
  } > "${out_dir}/report.md"

  # -- HTML
  {
    echo '<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    echo "<title>Recon Report – ${target}</title>"
    cat <<'CSS'
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,sans-serif;margin:24px;line-height:1.45}
  h1{margin:0 0 8px 0} .muted{color:#666}
  .card{border:1px solid #e5e7eb;border-radius:12px;padding:16px;margin:16px 0;box-shadow:0 1px 2px rgba(0,0,0,.04)}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #e5e7eb;padding:8px;text-align:left;vertical-align:top}
  th{background:#f8fafc}
  details{margin:8px 0}
  code,pre{background:#f6f8fa;border:1px solid #e5e7eb;border-radius:8px;padding:8px;display:block;overflow:auto;white-space:pre-wrap}
  a{color:#0366d6;text-decoration:none} a:hover{text-decoration:underline}
</style>
CSS
    echo "</head><body>"
    echo "<h1>Recon Report – ${target}</h1>"
    echo "<div class=\"muted\">Generado: $(date -u +"%Y-%m-%d %H:%M:%S UTC")</div>"

    # Resumen
    echo '<div class="card"><strong>Resumen</strong><br>'
    echo "Subdominios: ${count_subs} · DNS OK: ${count_dns} · HTTP vivos: ${count_alive} · URLs: ${count_urls}"
    echo '</div>'

    # Subdominios
    echo '<div class="card"><h3>Subdominios (subfinder + assetfinder)</h3>'
    if [ -s "$tmp/subs.txt" ]; then
      echo "<pre>$(html_escape < "$tmp/subs.txt")</pre>"
    else
      echo "<em>(sin resultados)</em>"
    fi
    echo '</div>'

    # HTTP vivos (tabla)
    echo '<div class="card"><h3>Subdominios vivos (httpx)</h3>'
    if [ -s "$tmp/httpx.json" ] && [ -s "$tmp/alive_urls.txt" ]; then
      echo '<table><thead><tr><th>URL</th><th>Status</th><th>Title</th><th>Tech</th></tr></thead><tbody>'
      jq -r '
        . as $o |
        [
          ($o.url // ""),
          ( ($o.status_code|tostring) // "" ),
          ( ($o.title // "") | gsub("\n"; " ") ),
          ( ($o.technologies // []) | map(.name) | unique | join(", ") )
        ] | @tsv
      ' "$tmp/httpx.json" 2>/dev/null | while IFS=$'\t' read -r url code title tech; do
        echo "<tr><td><a href=\"$(printf %s "$url" | html_escape)\" target=\"_blank\">$(printf %s "$url" | html_escape)</a></td><td>$(printf %s "$code" | html_escape)</td><td>$(printf %s "$title" | html_escape)</td><td>$(printf %s "$tech" | html_escape)</td></tr>"
      done
      echo '</tbody></table>'
    else
      echo "<em>(sin resultados)</em>"
    fi
    echo '</div>'

    # URLs (gau)
    echo '<div class="card"><h3>URLs (gau)</h3>'
    if [ -s "$tmp/urls.txt" ]; then
      echo "<details><summary>Ver URLs (${count_urls})</summary>"
      echo "<pre>$(html_escape < "$tmp/urls.txt")</pre>"
      echo "</details>"
    else
      echo "<em>(sin resultados)</em>"
    fi
    echo '</div>'

    # Otros
    echo '<div class="card"><h3>Otros</h3>'
    local nr rh
    nr=$(wc -l < "$tmp/unresolved.txt" 2>/dev/null || echo 0)
    rh=$(wc -l < "$tmp/resolved_no_http.txt" 2>/dev/null || echo 0)
    echo "<p>No resueltos (DNS): ${nr}</p>"
    if [ -s "$tmp/unresolved.txt" ]; then echo "<pre>$(html_escape < "$tmp/unresolved.txt")</pre>"; fi
    echo "<p>Resueltos sin HTTP vivo: ${rh}</p>"
    if [ -s "$tmp/resolved_no_http.txt" ]; then echo "<pre>$(html_escape < "$tmp/resolved_no_http.txt")</pre>"; fi
    echo '</div>'

    echo '</body></html>'
  } > "${out_dir}/report.html"

  rm -rf "$tmp"; trap - RETURN
  echo "→ Generado: ${out_dir}/report.md"
  echo "→ Generado: ${out_dir}/report.html"
}

if [ "$MODE" = "single" ]; then
  run_recon "$INPUT"
elif [ "$MODE" = "list" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # *** macOS BSD sed: usar clases POSIX en vez de \s ***
    line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    run_recon "$line"
  done < "$INPUT"
else
  show_help
fi

