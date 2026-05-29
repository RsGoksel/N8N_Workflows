#Requires -Version 5.1
<#
.SYNOPSIS
  Crypto Signal Bot — n8n Workflow Installer (Windows)
.DESCRIPTION
  Interactive installer that:
    1. Starts a local n8n container
    2. Asks for xAI Grok + Telegram bot details
    3. Auto-creates the Grok credential
    4. Guides Telegram credential creation in n8n UI (n8n public API doesn't expose telegramApi)
    5. Discovers the credential by name + auto-detects your chat_id
    6. Imports the workflow ready-to-run
#>

$ErrorActionPreference = 'Stop'
$script:N8N_URL  = 'http://localhost:5678'
$script:STEP     = 0
$script:STEPS    = 9

function Write-Title($t) {
  Write-Host ''
  Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
  Write-Host "  $t" -ForegroundColor Cyan
  Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
}
function Write-Step($t) { $script:STEP++; Write-Host ''; Write-Host "[$script:STEP/$script:STEPS] $t" -ForegroundColor Yellow }
function Write-Ok($t)   { Write-Host "  + $t" -ForegroundColor Green }
function Write-Info($t) { Write-Host "  > $t" -ForegroundColor Gray }
function Write-Err($t)  { Write-Host "  x $t" -ForegroundColor Red }
function Read-Required($l) {
  while ($true) { $v = Read-Host $l; if ($v.Trim()) { return $v.Trim() }; Write-Err 'Cannot be empty' }
}
function Read-Secret($l) {
  while ($true) {
    $s = Read-Host $l -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    $v = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    if ($v.Trim()) { return $v.Trim() }
    Write-Err 'Cannot be empty'
  }
}

Clear-Host
Write-Title 'Crypto Signal Bot Installer'
Write-Host @"
  This wizard will:
    - Start a local n8n Docker container
    - Set up the Grok LLM credential automatically
    - Help you create a Telegram bot and auto-detect your chat ID
    - Import the workflow ready to run

  ETA: ~5 minutes
"@ -ForegroundColor Gray

# 1. Docker
Write-Step 'Checking Docker'
try { $dv = docker --version; Write-Ok "Docker installed: $dv" }
catch { Write-Err 'Docker not found. Install Docker Desktop and try again.'; exit 1 }
try { docker ps | Out-Null; Write-Ok 'Docker daemon is running' }
catch { Write-Err 'Docker Desktop is not running. Start it and re-run this script.'; exit 1 }

# 2. Start n8n
Write-Step 'Starting n8n container'
$composeFile = Join-Path $PSScriptRoot 'docker-compose.yml'
if (-not (Test-Path $composeFile)) { Write-Err "docker-compose.yml not found: $composeFile"; exit 1 }
docker compose -f $composeFile up -d | Out-Null
Write-Ok 'Container starting'

Write-Info 'Waiting for n8n to be ready (up to 30s)...'
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  try { $r = Invoke-RestMethod -Uri "$script:N8N_URL/healthz" -TimeoutSec 2 -ErrorAction Stop
    if ($r.status -eq 'ok') { $ready = $true; break } } catch { Start-Sleep 1 }
}
if (-not $ready) { Write-Err "n8n didn't become ready. Check: docker logs n8n-crypto-bot"; exit 1 }
Write-Ok "n8n ready at $script:N8N_URL"

# 3. Account
Write-Step 'Create n8n account'
Write-Info 'Opening browser. Create your local account (email + password).'
Start-Process $script:N8N_URL
Write-Host ''
Write-Host '  Press Enter once your account is created...' -ForegroundColor Yellow -NoNewline
Read-Host | Out-Null

# 4. API key
Write-Step 'Get an n8n API key'
Write-Info 'Opening Settings -> n8n API'
Start-Process "$script:N8N_URL/settings/api"
Write-Host @"

  1. Click 'Create new API key'
  2. Give it a name (e.g. 'installer')
  3. Expiration: 'No expiration'
  4. Copy the key (shown ONCE!)
"@ -ForegroundColor Gray
$n8nApiKey = Read-Secret '  n8n API key'

try {
  Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/workflows?limit=1" -Headers @{ 'X-N8N-API-KEY' = $n8nApiKey } | Out-Null
  Write-Ok 'n8n API key is valid'
} catch { Write-Err 'Invalid n8n API key. Re-run the script.'; exit 1 }

# 5. Credentials collection
Write-Step 'Collecting credentials'

Write-Host ''
Write-Host '  [xAI Grok — LLM provider]' -ForegroundColor White
Write-Info 'https://console.x.ai > API Keys > Create'
$grokKey = Read-Secret '  Grok API key (starts with xai-)'

Write-Host ''
Write-Host '  [Telegram Bot]' -ForegroundColor White
Write-Info "Open Telegram > search '@BotFather' > /newbot > follow prompts"
Write-Info "Once you have the bot, send it 'hi' from YOUR account so it can find your chat_id"
$tgToken = Read-Secret '  Telegram bot token (looks like 1234:ABC-...)'

# 6. Validate keys
Write-Step 'Validating keys'

# Grok
try {
  $body = @{ model = 'grok-3-mini'; messages = @(@{ role = 'user'; content = 'ok' }); max_tokens = 4 } | ConvertTo-Json -Depth 4
  $null = Invoke-RestMethod -Uri 'https://api.x.ai/v1/chat/completions' -Method Post `
    -Headers @{ 'Authorization' = "Bearer $grokKey"; 'Content-Type' = 'application/json' } -Body $body
  Write-Ok 'Grok: responded'
} catch { Write-Err "Grok auth failed: $($_.Exception.Message)"; exit 1 }

# Telegram + chat_id discovery via getUpdates
Write-Info 'Detecting your chat ID via Telegram getUpdates...'
try {
  $tg = Invoke-RestMethod -Uri "https://api.telegram.org/bot$tgToken/getUpdates" -Method Get -TimeoutSec 10
  if (-not $tg.ok) { throw "Telegram returned ok=false" }
  $chats = @($tg.result | Where-Object { $_.message } | ForEach-Object { $_.message.chat })
  if ($chats.Count -eq 0) {
    Write-Err "No messages received by your bot yet."
    Write-Info "Open Telegram, find your bot, send it ANY message, then re-run setup."
    exit 1
  }
  $uniqueChats = $chats | Sort-Object id -Unique
  Write-Ok ("Detected {0} chat(s):" -f $uniqueChats.Count)
  $i = 0
  $uniqueChats | ForEach-Object {
    $i++
    $title = if ($_.title) { $_.title } else { "$($_.first_name) ($($_.type))" }
    Write-Host ("    [{0}] {1,-30} id={2}" -f $i, $title, $_.id) -ForegroundColor White
  }
  if ($uniqueChats.Count -eq 1) {
    $tgChatId = "$($uniqueChats[0].id)"
    Write-Ok "Using chat id: $tgChatId"
  } else {
    $sel = Read-Host "  Which chat number to send signals to? (1-$($uniqueChats.Count))"
    $idx = [int]$sel - 1
    $tgChatId = "$($uniqueChats[$idx].id)"
    Write-Ok "Using chat id: $tgChatId"
  }
} catch { Write-Err "Telegram check failed: $($_.Exception.Message)"; exit 1 }

# Workflow config
Write-Host ''
Write-Host '  [Workflow config]' -ForegroundColor White
$watchlist = Read-Host '  Watchlist (Enter = BTCUSDT,ETHUSDT,SOLUSDT,BNBUSDT,XRPUSDT,DOGEUSDT,ADAUSDT,AVAXUSDT)'
if (-not $watchlist) { $watchlist = 'BTCUSDT,ETHUSDT,SOLUSDT,BNBUSDT,XRPUSDT,DOGEUSDT,ADAUSDT,AVAXUSDT' }
$lang = Read-Host '  Language (tr / en, Enter = tr)'
if (-not $lang) { $lang = 'tr' }
$schedule = Read-Host '  Run every N minutes (Enter = 30)'
if (-not $schedule) { $schedule = '30' }

# 7. Auto-create Grok credential
Write-Step 'Creating n8n credentials'
$authHeader = @{ 'X-N8N-API-KEY' = $n8nApiKey; 'Content-Type' = 'application/json' }

$grokCred = @{
  name = 'xAI Grok'
  type = 'httpCustomAuth'
  data = @{
    allowedDomains = '*.x.ai'
    json = "{`"headers`":{`"Authorization`":`"Bearer $grokKey`"}}"
  }
} | ConvertTo-Json -Depth 4 -Compress
$grokCredId = (Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/credentials" -Method Post -Headers $authHeader -Body $grokCred).id
Write-Ok "Grok credential: $grokCredId"

# Telegram credential is `telegramApi` type — n8n public API rejects this type, must use UI
Write-Host ''
Write-Info "Telegram credential must be created via n8n UI (API limitation)."
Write-Host ''
Write-Host '  >>> A browser tab will open. In the form:' -ForegroundColor Cyan
Write-Host ''
Write-Host '      Credential Name:  Telegram Bot   (USE EXACTLY THIS NAME)' -ForegroundColor White
Write-Host '      Access Token:     (paste the same token you gave the script)' -ForegroundColor White
Write-Host ''
Start-Process "$script:N8N_URL/home/credentials"
Write-Host '  Press Enter after you click Save...' -ForegroundColor Yellow -NoNewline
Read-Host | Out-Null

# Auto-discover Telegram credential
$tgCredId = $null
for ($i = 0; $i -lt 20; $i++) {
  try {
    $list = Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/credentials?limit=50" -Headers @{ 'X-N8N-API-KEY' = $n8nApiKey }
    $found = $list.data | Where-Object { $_.name -eq 'Telegram Bot' -and $_.type -eq 'telegramApi' } | Select-Object -First 1
    if ($found) { $tgCredId = $found.id; break }
  } catch { }
  Start-Sleep 1
}
if (-not $tgCredId) {
  Write-Err "Credential named 'Telegram Bot' not found. Check at $script:N8N_URL/home/credentials"; exit 1
}
Write-Ok "Telegram credential: $tgCredId"

# 8. Import workflow
Write-Step 'Importing workflow'
$templatePath = Join-Path $PSScriptRoot 'workflow.template.json'
if (-not (Test-Path $templatePath)) { Write-Err 'workflow.template.json not found'; exit 1 }

$tpl = Get-Content $templatePath -Raw -Encoding UTF8
$tpl = $tpl.Replace('{{GROK_CRED_ID}}', $grokCredId)
$tpl = $tpl.Replace('{{TELEGRAM_CRED_ID}}', $tgCredId)
$tpl = $tpl.Replace('{{TELEGRAM_CHAT_ID}}', $tgChatId)

$wf = $tpl | ConvertFrom-Json

# Patch Config fields
$config = $wf.nodes | Where-Object { $_.id -eq 'config' }
($config.parameters.assignments.assignments | Where-Object { $_.name -eq 'watchlist' }).value = $watchlist
($config.parameters.assignments.assignments | Where-Object { $_.name -eq 'language' }).value  = $lang

# Patch schedule
$sched = $wf.nodes | Where-Object { $_.id -eq 'trig-schedule' }
$sched.parameters.rule.interval[0].minutesInterval = [int]$schedule

$payload = @{ name = $wf.name; nodes = $wf.nodes; connections = $wf.connections; settings = $wf.settings } | ConvertTo-Json -Depth 30 -Compress
$wfResp = Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/workflows" -Method Post -Headers $authHeader -Body $payload
Write-Ok "Workflow imported (ID: $($wfResp.id))"

# 9. Activate
Write-Step 'Activate?'
$ans = Read-Host "  Activate workflow now? Sends to Telegram every $schedule min. (Y/n)"
if ($ans -match '^([Yy]|$)') {
  try {
    Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/workflows/$($wfResp.id)/activate" -Method Post -Headers $authHeader | Out-Null
    Write-Ok 'Workflow activated. First signal arrives at next interval.'
  } catch { Write-Info 'Activate later via the top-right toggle.' }
}

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host @"

  All set!

    Workflow URL: $script:N8N_URL/workflow/$($wfResp.id)

  To test immediately:
    1. Open the URL above
    2. Press Ctrl+Enter (or 'Execute workflow' at bottom-right)
    3. Check your Telegram chat in ~20 sec

"@ -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
