#!/usr/bin/env bash
# Daily Stock Brief — n8n Workflow Installer (macOS / Linux)
# Interactive installer that:
#   1. Starts a local n8n container
#   2. Guides you to create an account
#   3. Collects your API keys (Alpaca, xAI Grok, Gmail SMTP)
#   4. Creates n8n credentials automatically
#   5. Imports the workflow ready-to-run

set -euo pipefail

N8N_URL='http://localhost:5678'
STEP=0
STEPS=9
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- UI helpers ----------
RED=$(tput setaf 1 2>/dev/null || true)
GRN=$(tput setaf 2 2>/dev/null || true)
YLW=$(tput setaf 3 2>/dev/null || true)
CYN=$(tput setaf 6 2>/dev/null || true)
GRY=$(tput setaf 8 2>/dev/null || true)
RST=$(tput sgr0 2>/dev/null || true)

title()   { printf '\n%s════════════════════════════════════════════════════════════%s\n  %s\n%s════════════════════════════════════════════════════════════%s\n' "$CYN" "$RST" "$1" "$CYN" "$RST"; }
step()    { STEP=$((STEP+1)); printf '\n%s[%d/%d] %s%s\n' "$YLW" "$STEP" "$STEPS" "$1" "$RST"; }
ok()      { printf '  %s✓ %s%s\n' "$GRN" "$1" "$RST"; }
info()    { printf '  %sℹ %s%s\n' "$GRY" "$1" "$RST"; }
err()     { printf '  %s✗ %s%s\n' "$RED" "$1" "$RST"; }

require_input() {
  local prompt="$1" var=''
  while [[ -z "$var" ]]; do
    read -r -p "  $prompt: " var
    [[ -z "$var" ]] && err 'Boş bırakılamaz'
  done
  printf '%s' "$var"
}

require_secret() {
  local prompt="$1" var=''
  while [[ -z "$var" ]]; do
    read -r -s -p "  $prompt: " var; echo
    [[ -z "$var" ]] && err 'Boş bırakılamaz'
  done
  printf '%s' "$var"
}

open_url() {
  if   command -v open >/dev/null 2>&1;     then open "$1" 2>/dev/null || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" 2>/dev/null || true
  else info "Tarayıcıda aç: $1"
  fi
}

api_post() {
  curl -fsS -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' --data "$2" "$N8N_URL$1"
}

# ---------- Setup flow ----------
clear
title 'Daily Stock Brief Installer'
cat <<EOF
  ${GRY}Bu kurulum sihirbazı:
    • Docker'da n8n container'ı başlatır
    • Alpaca + xAI Grok + Gmail credential'larını otomatik kurar
    • Workflow'u import eder, çalışmaya hazır bırakır
  Yaklaşık süre: 3-5 dakika${RST}
EOF

# 1. Docker check
step 'Docker kontrol ediliyor'
if ! command -v docker >/dev/null 2>&1; then
  err 'Docker yok. https://docker.com/products/docker-desktop adresinden indir'
  exit 1
fi
ok "Docker yüklü: $(docker --version)"
if ! docker ps >/dev/null 2>&1; then
  err 'Docker daemon kapalı. Docker Desktop başlat ve tekrar dene'
  exit 1
fi
ok 'Docker daemon çalışıyor'

# 2. Start n8n
step 'n8n container başlatılıyor'
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  err "docker-compose.yml bulunamadı: $COMPOSE_FILE"
  exit 1
fi
docker compose -f "$COMPOSE_FILE" up -d >/dev/null
ok 'Container başlatıldı'

info "n8n hazır olana kadar bekleniyor..."
ready=false
for i in $(seq 1 30); do
  if curl -fsS -m 2 "$N8N_URL/healthz" 2>/dev/null | grep -q '"ok"'; then ready=true; break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then err 'n8n 30 saniyede hazır olmadı'; exit 1; fi
ok "n8n hazır: $N8N_URL"

# 3. Account + API key
step 'n8n hesabı oluştur'
info "Tarayıcı açılıyor — email + şifre ile lokal hesap aç"
open_url "$N8N_URL"
read -r -p "  Hesabı oluşturduktan sonra Enter'e bas..." _

step 'n8n API key oluştur'
info 'Settings → n8n API açılıyor'
open_url "$N8N_URL/settings/api"
cat <<EOF

  1. 'Create new API key' butonuna bas
  2. Bir isim ver (örn. 'installer')
  3. Expiration: 'No expiration'
  4. Key'i kopyala (bir daha gösterilmez!)

EOF
N8N_API_KEY=$(require_secret 'n8n API key')

if ! curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows?limit=1" >/dev/null 2>&1; then
  err 'n8n API key geçersiz'; exit 1
fi
ok 'n8n API key geçerli'

# 4. Provider keys
step "Provider key'leri toplanıyor"

echo
echo "  📊 Alpaca Markets (ücretsiz)"
info 'https://app.alpaca.markets/paper/dashboard/overview → API Keys → Generate'
ALPACA_KEY=$(require_input 'Alpaca Key ID (PK ile başlar)')
ALPACA_SECRET=$(require_secret 'Alpaca Secret')

echo
echo "  🤖 xAI Grok (LLM)"
info 'https://console.x.ai → API Keys → Create'
GROK_KEY=$(require_secret 'Grok API key (xai- ile başlar)')

echo
echo "  [Gmail SMTP]"
info 'https://myaccount.google.com/security > 2-Step Verification > App passwords'
GMAIL_ADDR=$(require_input 'Gmail adresi')
info "App Password'u not et - SMTP credential formuna birazdan yapistiracaksin"

echo
echo "  ⚙️  Workflow yapılandırması"
read -r -p '  Watchlist (Enter = AAPL,MSFT,NVDA,TSLA,GOOGL,META,AMZN,NFLX,AMD,SPY): ' WATCHLIST
[[ -z "$WATCHLIST" ]] && WATCHLIST='AAPL,MSFT,NVDA,TSLA,GOOGL,META,AMZN,NFLX,AMD,SPY'
read -r -p "  Mail alıcısı (Enter = $GMAIL_ADDR): " RECIPIENT
[[ -z "$RECIPIENT" ]] && RECIPIENT="$GMAIL_ADDR"

# 5. Validate
step "Key'ler doğrulanıyor"

if ! curl -fsS -H "APCA-API-KEY-ID: $ALPACA_KEY" -H "APCA-API-SECRET-KEY: $ALPACA_SECRET" \
  'https://data.alpaca.markets/v1beta1/screener/stocks/movers?top=1' >/dev/null 2>&1; then
  err 'Alpaca auth başarısız'; exit 1
fi
ok 'Alpaca: 401 yok, geçerli'

GROK_BODY='{"model":"grok-3-mini","messages":[{"role":"user","content":"OK"}],"max_tokens":4}'
if ! curl -fsS -X POST -H "Authorization: Bearer $GROK_KEY" -H 'Content-Type: application/json' \
  --data "$GROK_BODY" 'https://api.x.ai/v1/chat/completions' >/dev/null 2>&1; then
  err 'Grok auth başarısız'; exit 1
fi
ok 'Grok: yanıt aldı'

# 6. Create credentials
step "n8n credential'ları oluşturuluyor"

# escape JSON string fragments
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

ALPACA_CRED_PAYLOAD=$(cat <<JSON
{"name":"Alpaca Markets","type":"httpCustomAuth","data":{"allowedDomains":"*.alpaca.markets","json":"{\"headers\":{\"APCA-API-KEY-ID\":\"$(esc "$ALPACA_KEY")\",\"APCA-API-SECRET-KEY\":\"$(esc "$ALPACA_SECRET")\"}}"}}
JSON
)
ALPACA_CRED_ID=$(api_post '/api/v1/credentials' "$ALPACA_CRED_PAYLOAD" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ok "Alpaca credential: $ALPACA_CRED_ID"

GROK_CRED_PAYLOAD=$(cat <<JSON
{"name":"xAI Grok","type":"httpCustomAuth","data":{"allowedDomains":"*.x.ai","json":"{\"headers\":{\"Authorization\":\"Bearer $(esc "$GROK_KEY")\"}}"}}
JSON
)
GROK_CRED_ID=$(api_post '/api/v1/credentials' "$GROK_CRED_PAYLOAD" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ok "Grok credential: $GROK_CRED_ID"

# SMTP credential public API'de desteklenmiyor - UI'dan oluştur
info "SMTP credential UI'dan olusturulacak (n8n API kisiti)"
cat <<EOF

  >>> Tarayicida credential formu aciliyor.
  >>> Sol panelden Type olarak 'SMTP' sec, sonra alanlara sunlari yapistir:

      Credential Name:  Gmail SMTP   (TAM BU ISIM - script bunu bulacak)
      User:             $GMAIL_ADDR
      Password:         (Gmail App Password)
      Host:             smtp.gmail.com
      Port:             465
      SSL/TLS:          ON

EOF
open_url "$N8N_URL/home/credentials"
read -r -p "  'Save' butonuna bastiktan sonra Enter'e bas..." _

# Auto-discover SMTP credential by name
SMTP_CRED_ID=''
for i in $(seq 1 20); do
  LIST=$(curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/credentials?limit=50" 2>/dev/null || echo '')
  SMTP_CRED_ID=$(printf '%s' "$LIST" | python3 -c '
import json, sys
try:
  d = json.load(sys.stdin)
  for c in d.get("data", []):
    if c.get("name") == "Gmail SMTP" and c.get("type") == "smtp":
      print(c["id"]); break
except: pass
' 2>/dev/null || true)
  [[ -n "$SMTP_CRED_ID" ]] && break
  sleep 1
done
if [[ -z "$SMTP_CRED_ID" ]]; then
  err "'Gmail SMTP' isimli SMTP credential bulunamadi. Manuel: $N8N_URL/home/credentials"
  exit 1
fi
ok "SMTP credential: $SMTP_CRED_ID"

# 7. Import workflow
step 'Workflow import ediliyor'
TEMPLATE="$SCRIPT_DIR/workflow.template.json"
[[ ! -f "$TEMPLATE" ]] && { err "workflow.template.json bulunamadı"; exit 1; }

WORKFLOW_JSON=$(sed \
  -e "s|{{RECIPIENT_EMAIL}}|$(esc "$RECIPIENT")|g" \
  -e "s|{{SMTP_FROM_EMAIL}}|$(esc "$GMAIL_ADDR")|g" \
  -e "s|{{ALPACA_CRED_ID}}|$(esc "$ALPACA_CRED_ID")|g" \
  -e "s|{{GROK_CRED_ID}}|$(esc "$GROK_CRED_ID")|g" \
  -e "s|{{SMTP_CRED_ID}}|$(esc "$SMTP_CRED_ID")|g" \
  -e "s|AAPL,MSFT,NVDA,TSLA,GOOGL,META,AMZN,NFLX,AMD,SPY|$(esc "$WATCHLIST")|g" \
  "$TEMPLATE")

# Send only name, nodes, connections, settings (strip metadata)
PAYLOAD=$(printf '%s' "$WORKFLOW_JSON" | python3 -c '
import json, sys
w = json.load(sys.stdin)
out = {"name": w["name"], "nodes": w["nodes"], "connections": w["connections"], "settings": w.get("settings", {})}
print(json.dumps(out))
' 2>/dev/null || printf '%s' "$WORKFLOW_JSON")

WF_RESP=$(api_post '/api/v1/workflows' "$PAYLOAD")
WF_ID=$(printf '%s' "$WF_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ok "Workflow import edildi (ID: $WF_ID)"

# 8. Activate option
step 'Aktifleştirme'
read -r -p '  Workflow'\''u şimdi aktive et? Pzt-Cuma 09:00 (E/h): ' ACTIVATE
if [[ -z "$ACTIVATE" || "$ACTIVATE" =~ ^[EeYy] ]]; then
  if curl -fsS -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$WF_ID/activate" >/dev/null 2>&1; then
    ok "Workflow aktif"
  else
    info "Aktivasyon sonra UI'dan: sağ üst toggle"
  fi
else
  info "UI'dan açabilirsin: sağ üst toggle ile Active konumuna al"
fi

# 9. Done
step 'Tamamlandı'
cat <<EOF

  ${GRN}Workflow URL: $N8N_URL/workflow/$WF_ID${RST}

  Hemen test etmek için:
    1. URL'yi aç
    2. Sağ alt 'Execute workflow' veya Ctrl+Enter
    3. Tüm node'lar yeşillenince posta kutunu kontrol et

  İlk schedule: yarın 09:00 (Europe/Istanbul)

EOF
printf '%s════════════════════════════════════════════════════════════%s\n' "$CYN" "$RST"
