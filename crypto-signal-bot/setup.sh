#!/usr/bin/env bash
# Crypto Signal Bot — n8n Workflow Installer (macOS / Linux)
set -euo pipefail

N8N_URL='http://localhost:5678'
STEP=0; STEPS=9
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED=$(tput setaf 1 2>/dev/null || true)
GRN=$(tput setaf 2 2>/dev/null || true)
YLW=$(tput setaf 3 2>/dev/null || true)
CYN=$(tput setaf 6 2>/dev/null || true)
GRY=$(tput setaf 8 2>/dev/null || true)
RST=$(tput sgr0 2>/dev/null || true)

title()  { printf '\n%s════════════════════════════════════════════════════════════%s\n  %s\n%s════════════════════════════════════════════════════════════%s\n' "$CYN" "$RST" "$1" "$CYN" "$RST"; }
step()   { STEP=$((STEP+1)); printf '\n%s[%d/%d] %s%s\n' "$YLW" "$STEP" "$STEPS" "$1" "$RST"; }
ok()     { printf '  %s+ %s%s\n' "$GRN" "$1" "$RST"; }
info()   { printf '  %s> %s%s\n' "$GRY" "$1" "$RST"; }
err()    { printf '  %sx %s%s\n' "$RED" "$1" "$RST"; }

req_input()  { local p="$1" v=''; while [[ -z "$v" ]]; do read -r -p "  $p: " v; [[ -z "$v" ]] && err 'Cannot be empty'; done; printf '%s' "$v"; }
req_secret() { local p="$1" v=''; while [[ -z "$v" ]]; do read -r -s -p "  $p: " v; echo; [[ -z "$v" ]] && err 'Cannot be empty'; done; printf '%s' "$v"; }
open_url()   {
  if   command -v open >/dev/null 2>&1;     then open "$1" 2>/dev/null || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" 2>/dev/null || true
  else info "Open in browser: $1"; fi
}
api_post() { curl -fsS -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' --data "$2" "$N8N_URL$1"; }
esc()      { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

clear
title 'Crypto Signal Bot Installer'
cat <<EOF
  ${GRY}This wizard will:
    - Start a local n8n Docker container
    - Set up the Grok LLM credential automatically
    - Help you create a Telegram bot and auto-detect your chat ID
    - Import the workflow ready to run
  ETA: ~5 minutes${RST}
EOF

step 'Checking Docker'
command -v docker >/dev/null 2>&1 || { err 'Docker not found'; exit 1; }
ok "Docker installed: $(docker --version)"
docker ps >/dev/null 2>&1 || { err 'Docker daemon not running'; exit 1; }
ok 'Docker daemon running'

step 'Starting n8n container'
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
[[ -f "$COMPOSE_FILE" ]] || { err "docker-compose.yml not found"; exit 1; }
docker compose -f "$COMPOSE_FILE" up -d >/dev/null
ok 'Container starting'

info 'Waiting for n8n...'
ready=false
for i in $(seq 1 30); do
  curl -fsS -m 2 "$N8N_URL/healthz" 2>/dev/null | grep -q '"ok"' && { ready=true; break; }
  sleep 1
done
[[ "$ready" == true ]] || { err "n8n not ready"; exit 1; }
ok "n8n ready: $N8N_URL"

step 'Create n8n account'
info 'Browser opening — create a local account'
open_url "$N8N_URL"
read -r -p "  Press Enter once your account is created..." _

step 'Get n8n API key'
open_url "$N8N_URL/settings/api"
cat <<EOF

  1. Click 'Create new API key'
  2. Name it (e.g. 'installer')
  3. Expiration: 'No expiration'
  4. Copy the key (shown ONCE!)
EOF
N8N_API_KEY=$(req_secret 'n8n API key')
curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows?limit=1" >/dev/null 2>&1 || { err 'Invalid n8n API key'; exit 1; }
ok 'n8n API key valid'

step 'Collecting credentials'
echo; echo "  [xAI Grok — LLM]"
info 'https://console.x.ai > API Keys > Create'
GROK_KEY=$(req_secret 'Grok API key (xai-)')

echo; echo "  [Telegram Bot]"
info "Telegram > '@BotFather' > /newbot > save the token"
info "Then send your bot ANY message from your account so it can see your chat_id"
TG_TOKEN=$(req_secret 'Telegram bot token')

step 'Validating keys'
GROK_BODY='{"model":"grok-3-mini","messages":[{"role":"user","content":"ok"}],"max_tokens":4}'
curl -fsS -X POST -H "Authorization: Bearer $GROK_KEY" -H 'Content-Type: application/json' \
  --data "$GROK_BODY" 'https://api.x.ai/v1/chat/completions' >/dev/null 2>&1 \
  || { err 'Grok auth failed'; exit 1; }
ok 'Grok responded'

info 'Detecting your Telegram chat ID via getUpdates...'
TG_RESP=$(curl -fsS "https://api.telegram.org/bot$TG_TOKEN/getUpdates" 2>/dev/null || true)
if [[ -z "$TG_RESP" ]] || ! printf '%s' "$TG_RESP" | grep -q '"ok":true'; then
  err 'Telegram API call failed — bad token?'; exit 1
fi

# Parse chats from getUpdates
CHAT_IDS=$(printf '%s' "$TG_RESP" | python3 -c '
import json, sys
try:
  d = json.load(sys.stdin)
  seen = {}
  for u in d.get("result", []):
    msg = u.get("message") or u.get("channel_post")
    if not msg: continue
    chat = msg.get("chat", {})
    cid = chat.get("id")
    if cid is None or cid in seen: continue
    title = chat.get("title") or f"{chat.get(\"first_name\",\"?\")} ({chat.get(\"type\",\"?\")})"
    seen[cid] = title
  for cid, t in seen.items(): print(f"{cid}|{t}")
' 2>/dev/null || true)

if [[ -z "$CHAT_IDS" ]]; then
  err 'No chats found. Send your bot ANY message in Telegram, then re-run setup.'
  exit 1
fi

CHATS=()
while IFS= read -r line; do CHATS+=("$line"); done <<< "$CHAT_IDS"
ok "Found ${#CHATS[@]} chat(s):"
i=0
for c in "${CHATS[@]}"; do
  i=$((i+1))
  cid="${c%%|*}"; cname="${c#*|}"
  printf '    [%d] %-30s id=%s\n' "$i" "$cname" "$cid"
done

if [[ "${#CHATS[@]}" -eq 1 ]]; then
  TG_CHAT_ID="${CHATS[0]%%|*}"
else
  read -r -p "  Pick chat number (1-${#CHATS[@]}): " sel
  TG_CHAT_ID="${CHATS[$((sel-1))]%%|*}"
fi
ok "Using chat id: $TG_CHAT_ID"

echo; echo "  [Workflow config]"
read -r -p '  Watchlist (Enter = default 8 majors): ' WATCHLIST
[[ -z "$WATCHLIST" ]] && WATCHLIST='BTCUSDT,ETHUSDT,SOLUSDT,BNBUSDT,XRPUSDT,DOGEUSDT,ADAUSDT,AVAXUSDT'
read -r -p '  Language (tr / en, Enter = tr): ' LANG
[[ -z "$LANG" ]] && LANG='tr'
read -r -p '  Run every N minutes (Enter = 30): ' SCHED
[[ -z "$SCHED" ]] && SCHED='30'

step 'Creating n8n credentials'
GROK_CRED="{\"name\":\"xAI Grok\",\"type\":\"httpCustomAuth\",\"data\":{\"allowedDomains\":\"*.x.ai\",\"json\":\"{\\\"headers\\\":{\\\"Authorization\\\":\\\"Bearer $(esc "$GROK_KEY")\\\"}}\"}}"
GROK_CRED_ID=$(api_post '/api/v1/credentials' "$GROK_CRED" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ok "Grok credential: $GROK_CRED_ID"

# Telegram credential via UI
info "Telegram credential must be created via UI (API limitation)"
cat <<EOF

  >>> Browser opens — in the form:

      Credential Name:  Telegram Bot   (USE EXACTLY THIS NAME)
      Access Token:     (paste your bot token)

EOF
open_url "$N8N_URL/home/credentials"
read -r -p "  Press Enter after clicking Save..." _

TG_CRED_ID=''
for i in $(seq 1 20); do
  LIST=$(curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/credentials?limit=50" 2>/dev/null || echo '')
  TG_CRED_ID=$(printf '%s' "$LIST" | python3 -c '
import json, sys
try:
  d = json.load(sys.stdin)
  for c in d.get("data", []):
    if c.get("name") == "Telegram Bot" and c.get("type") == "telegramApi":
      print(c["id"]); break
except: pass
' 2>/dev/null || true)
  [[ -n "$TG_CRED_ID" ]] && break
  sleep 1
done
[[ -n "$TG_CRED_ID" ]] || { err "Credential 'Telegram Bot' not found at $N8N_URL/home/credentials"; exit 1; }
ok "Telegram credential: $TG_CRED_ID"

step 'Importing workflow'
TEMPLATE="$SCRIPT_DIR/workflow.template.json"
[[ -f "$TEMPLATE" ]] || { err 'workflow.template.json missing'; exit 1; }

WF=$(sed \
  -e "s|{{GROK_CRED_ID}}|$(esc "$GROK_CRED_ID")|g" \
  -e "s|{{TELEGRAM_CRED_ID}}|$(esc "$TG_CRED_ID")|g" \
  -e "s|{{TELEGRAM_CHAT_ID}}|$(esc "$TG_CHAT_ID")|g" \
  "$TEMPLATE")

PAYLOAD=$(printf '%s' "$WF" | python3 -c "
import json, sys
w = json.load(sys.stdin)
for n in w['nodes']:
    if n['id'] == 'config':
        for a in n['parameters']['assignments']['assignments']:
            if a['name'] == 'watchlist': a['value'] = '$WATCHLIST'
            if a['name'] == 'language':  a['value'] = '$LANG'
    if n['id'] == 'trig-schedule':
        n['parameters']['rule']['interval'][0]['minutesInterval'] = int('$SCHED')
out = {'name': w['name'], 'nodes': w['nodes'], 'connections': w['connections'], 'settings': w.get('settings', {})}
print(json.dumps(out))
")

WF_RESP=$(api_post '/api/v1/workflows' "$PAYLOAD")
WF_ID=$(printf '%s' "$WF_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ok "Workflow imported (ID: $WF_ID)"

step 'Activate?'
read -r -p "  Activate workflow now? Will send to Telegram every $SCHED min (Y/n): " ANS
if [[ -z "$ANS" || "$ANS" =~ ^[Yy] ]]; then
  curl -fsS -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$WF_ID/activate" >/dev/null 2>&1 \
    && ok 'Workflow activated' \
    || info 'Activate later via top-right toggle'
fi

cat <<EOF

${GRN}════════════════════════════════════════════════════════════${RST}

  All set!

    Workflow URL: $N8N_URL/workflow/$WF_ID

  To test immediately:
    1. Open the URL above
    2. Press Ctrl+Enter (or 'Execute workflow' bottom-right)
    3. Check your Telegram chat in ~20 sec

${GRN}════════════════════════════════════════════════════════════${RST}

EOF
