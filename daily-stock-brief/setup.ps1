#Requires -Version 5.1
<#
.SYNOPSIS
  Daily Stock Brief — n8n Workflow Installer
.DESCRIPTION
  Interactive installer that:
    1. Starts a local n8n container
    2. Guides you to create an account
    3. Collects your API keys (Alpaca, xAI Grok, Gmail SMTP)
    4. Creates n8n credentials automatically
    5. Imports the workflow ready-to-run
  No n8n UI clicking required after account creation.
#>

$ErrorActionPreference = 'Stop'
$script:N8N_URL  = 'http://localhost:5678'
$script:STEP     = 0
$script:STEPS    = 9

# ---------- UI helpers ----------
function Write-Title($text) {
  Write-Host ''
  Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
  Write-Host "  $text" -ForegroundColor Cyan
  Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
}

function Write-Step($text) {
  $script:STEP++
  Write-Host ''
  Write-Host "[$script:STEP/$script:STEPS] $text" -ForegroundColor Yellow
}

function Write-Ok($text)   { Write-Host "  ✓ $text" -ForegroundColor Green }
function Write-Info($text) { Write-Host "  ℹ $text" -ForegroundColor Gray }
function Write-Err($text)  { Write-Host "  ✗ $text" -ForegroundColor Red }

function Read-Required($label) {
  while ($true) {
    $val = Read-Host $label
    if ($val.Trim()) { return $val.Trim() }
    Write-Err 'Boş bırakılamaz, tekrar deneyin'
  }
}

function Read-Secret($label) {
  while ($true) {
    $sec = Read-Host $label -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $val  = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if ($val.Trim()) { return $val.Trim() }
    Write-Err 'Boş bırakılamaz'
  }
}

# ---------- Setup flow ----------
Clear-Host
Write-Title 'Daily Stock Brief Installer'
Write-Host @"
  Bu kurulum sihirbazı:
    • Docker'da n8n container'ı başlatır
    • Alpaca + xAI Grok + Gmail credential'larını otomatik kurar
    • Workflow'u import eder, çalışmaya hazır bırakır
  Yaklaşık süre: 3-5 dakika
"@ -ForegroundColor Gray

# ---------- 1. Docker check ----------
Write-Step 'Docker kontrol ediliyor'
try {
  $dv = docker --version
  Write-Ok "Docker yüklü: $dv"
} catch {
  Write-Err 'Docker yok. https://docker.com/products/docker-desktop adresinden indir, kur ve tekrar dene'
  exit 1
}
try {
  docker ps | Out-Null
  Write-Ok 'Docker daemon çalışıyor'
} catch {
  Write-Err "Docker Desktop kapalı. Başlat, sistem tepsisindeki balina yeşil olunca tekrar dene"
  exit 1
}

# ---------- 2. Start n8n ----------
Write-Step 'n8n container başlatılıyor'
$composeFile = Join-Path $PSScriptRoot 'docker-compose.yml'
if (-not (Test-Path $composeFile)) {
  Write-Err "docker-compose.yml bulunamadı: $composeFile"
  exit 1
}
docker compose -f $composeFile up -d | Out-Null
Write-Ok 'Container başlatıldı'

Write-Info 'n8n hazır olana kadar bekleniyor (30 sn''ye kadar)...'
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  try {
    $r = Invoke-RestMethod -Uri "$script:N8N_URL/healthz" -TimeoutSec 2 -ErrorAction Stop
    if ($r.status -eq 'ok') { $ready = $true; break }
  } catch { Start-Sleep 1 }
}
if (-not $ready) { Write-Err 'n8n 30 saniyede hazır olmadı. docker logs n8n-stock-brief'; exit 1 }
Write-Ok "n8n hazır: $script:N8N_URL"

# ---------- 3. Account + API key ----------
Write-Step 'n8n hesabı oluştur'
Write-Info 'Tarayıcı açılıyor — sayfada email + şifre ile hesap aç (sadece lokal)'
Start-Process $script:N8N_URL
Write-Host ''
Write-Host '  Hesabı oluşturduktan sonra Enter''e bas...' -ForegroundColor Yellow -NoNewline
Read-Host | Out-Null

Write-Step 'n8n API key oluştur'
Write-Info 'Tarayıcıda Settings → n8n API açılıyor'
Start-Process "$script:N8N_URL/settings/api"
Write-Host @"

  1. 'Create new API key' butonuna bas
  2. Bir isim ver (örn. 'installer')
  3. Expiration: 'No expiration'
  4. Key'i kopyala (bir daha gösterilmez!)
"@ -ForegroundColor Gray
$n8nApiKey = Read-Secret '  n8n API key'

# Test n8n key
try {
  $null = Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/workflows?limit=1" -Headers @{ 'X-N8N-API-KEY' = $n8nApiKey } -ErrorAction Stop
  Write-Ok 'n8n API key geçerli'
} catch {
  Write-Err 'n8n API key geçersiz. Tekrar dene.'
  exit 1
}

# ---------- 4. Collect provider keys ----------
Write-Step 'Provider key''leri toplanıyor'

Write-Host ''
Write-Host '  [Alpaca Markets - ucretsiz]' -ForegroundColor White
Write-Info 'https://app.alpaca.markets/paper/dashboard/overview > API Keys > Generate'
$alpacaKeyId  = Read-Required '  Alpaca Key ID (PK ile baslar)'
$alpacaSecret = Read-Secret   '  Alpaca Secret'

Write-Host ''
Write-Host '  [xAI Grok - LLM]' -ForegroundColor White
Write-Info 'https://console.x.ai > API Keys > Create'
$grokKey = Read-Secret '  Grok API key (xai- ile baslar)'

Write-Host ''
Write-Host '  [Gmail SMTP]' -ForegroundColor White
Write-Info 'https://myaccount.google.com/security > 2-Step Verification > App passwords'
$gmailAddr = Read-Required '  Gmail adresi'
Write-Info "App Password'u not et — SMTP credential formuna birazdan yapıştıracaksın"
Write-Host "  (Bu adımda kaydetmiyoruz, hatırlatma için)" -ForegroundColor DarkGray

Write-Host ''
Write-Host '  [Workflow yapilandirmasi]' -ForegroundColor White
$watchlist = Read-Host '  Watchlist (Enter = AAPL,MSFT,NVDA,TSLA,GOOGL,META,AMZN,NFLX,AMD,SPY)'
if (-not $watchlist) { $watchlist = 'AAPL,MSFT,NVDA,TSLA,GOOGL,META,AMZN,NFLX,AMD,SPY' }
$recipient = Read-Host "  Mail alıcısı (Enter = $gmailAddr)"
if (-not $recipient) { $recipient = $gmailAddr }

# ---------- 5. Validate provider keys ----------
Write-Step 'Key''ler doğrulanıyor'

# Alpaca
try {
  $null = Invoke-RestMethod -Uri 'https://data.alpaca.markets/v1beta1/screener/stocks/movers?top=1' `
    -Headers @{ 'APCA-API-KEY-ID' = $alpacaKeyId; 'APCA-API-SECRET-KEY' = $alpacaSecret } -ErrorAction Stop
  Write-Ok 'Alpaca: 401 yok, geçerli'
} catch {
  Write-Err 'Alpaca auth başarısız. Key ID ve Secret''i kontrol et.'; exit 1
}

# Grok
try {
  $body = @{ model = 'grok-3-mini'; messages = @(@{ role='user'; content='OK' }); max_tokens = 4 } | ConvertTo-Json -Depth 4
  $null = Invoke-RestMethod -Uri 'https://api.x.ai/v1/chat/completions' -Method Post `
    -Headers @{ 'Authorization' = "Bearer $grokKey"; 'Content-Type' = 'application/json' } -Body $body -ErrorAction Stop
  Write-Ok 'Grok: yanıt aldı'
} catch {
  Write-Err 'Grok auth başarısız. Key''i kontrol et.'; exit 1
}

# ---------- 6. Create n8n credentials ----------
Write-Step 'n8n credential''ları oluşturuluyor'

$authHeader = @{ 'X-N8N-API-KEY' = $n8nApiKey; 'Content-Type' = 'application/json' }

function New-Credential($name, $type, $data) {
  $body = @{ name = $name; type = $type; data = $data } | ConvertTo-Json -Depth 6 -Compress
  $r = Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/credentials" -Method Post -Headers $authHeader -Body $body
  return $r.id
}

$alpacaCredId = New-Credential 'Alpaca Markets' 'httpCustomAuth' @{
  allowedDomains = '*.alpaca.markets'
  json = "{`"headers`":{`"APCA-API-KEY-ID`":`"$alpacaKeyId`",`"APCA-API-SECRET-KEY`":`"$alpacaSecret`"}}"
}
Write-Ok "Alpaca credential: $alpacaCredId"

$grokCredId = New-Credential 'xAI Grok' 'httpCustomAuth' @{
  allowedDomains = '*.x.ai'
  json = "{`"headers`":{`"Authorization`":`"Bearer $grokKey`"}}"
}
Write-Ok "Grok credential: $grokCredId"

# SMTP credential public API'de desteklenmiyor — UI'dan oluştur
Write-Info "SMTP credential UI'dan oluşturulacak (n8n API kısıtı)"
Write-Host ''
Write-Host '  >>> Tarayıcıda credential formu açılıyor.' -ForegroundColor Cyan
Write-Host '  >>> Sol panelden Type olarak ''SMTP'' seç, sonra alanlara şunları yapıştır:' -ForegroundColor Cyan
Write-Host ''
Write-Host "      Credential Name:  Gmail SMTP   (TAM BU İSİM — script bunu bulacak)" -ForegroundColor White
Write-Host "      User:             $gmailAddr" -ForegroundColor White
Write-Host "      Password:         (Gmail App Password - clipboard'tan yapistir)" -ForegroundColor White
Write-Host "      Host:             smtp.gmail.com" -ForegroundColor White
Write-Host "      Port:             465" -ForegroundColor White
Write-Host "      SSL/TLS:          ON" -ForegroundColor White
Write-Host ''
Start-Process "$script:N8N_URL/home/credentials"
Write-Host '  ''Save'' butonuna bastıktan sonra Enter''e bas...' -ForegroundColor Yellow -NoNewline
Read-Host | Out-Null

# Auto-discover SMTP credential by name
$smtpCredId = $null
for ($i = 0; $i -lt 20; $i++) {
  try {
    $list = Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/credentials?limit=50" -Headers @{ 'X-N8N-API-KEY' = $n8nApiKey }
    $found = $list.data | Where-Object { $_.name -eq 'Gmail SMTP' -and $_.type -eq 'smtp' } | Select-Object -First 1
    if ($found) { $smtpCredId = $found.id; break }
  } catch { }
  Start-Sleep 1
}
if (-not $smtpCredId) {
  Write-Err "'Gmail SMTP' isimli SMTP credential bulunamadı. Manuel kontrol et: $script:N8N_URL/home/credentials"
  exit 1
}
Write-Ok "SMTP credential: $smtpCredId"

# ---------- 7. Import workflow ----------
Write-Step 'Workflow import ediliyor'
$templatePath = Join-Path $PSScriptRoot 'workflow.template.json'
if (-not (Test-Path $templatePath)) { Write-Err "workflow.template.json bulunamadı"; exit 1 }

$tpl = Get-Content $templatePath -Raw -Encoding UTF8
$tpl = $tpl.Replace('{{RECIPIENT_EMAIL}}', $recipient)
$tpl = $tpl.Replace('{{SMTP_FROM_EMAIL}}', $gmailAddr)
$tpl = $tpl.Replace('{{ALPACA_CRED_ID}}', $alpacaCredId)
$tpl = $tpl.Replace('{{GROK_CRED_ID}}', $grokCredId)
$tpl = $tpl.Replace('{{SMTP_CRED_ID}}', $smtpCredId)

$wf = $tpl | ConvertFrom-Json
$config = $wf.nodes | Where-Object { $_.id -eq 'config' }
$wlField = $config.parameters.assignments.assignments | Where-Object { $_.name -eq 'watchlist' }
$wlField.value = $watchlist

$payload = @{ name = $wf.name; nodes = $wf.nodes; connections = $wf.connections; settings = $wf.settings } | ConvertTo-Json -Depth 30 -Compress
$wfResp = Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/workflows" -Method Post -Headers $authHeader -Body $payload
Write-Ok "Workflow import edildi (ID: $($wfResp.id))"

# ---------- 8. Activate option ----------
Write-Step 'Aktifleştirme'
$activate = Read-Host '  Workflow''u şimdi aktive et? Pzt-Cuma 09:00''da otomatik çalışır. (E/h)'
if ($activate -match '^([Ee]|[Yy]|$)') {
  try {
    Invoke-RestMethod -Uri "$script:N8N_URL/api/v1/workflows/$($wfResp.id)/activate" -Method Post -Headers $authHeader | Out-Null
    Write-Ok 'Workflow aktif. İlk schedule yarın 09:00''da çalışır.'
  } catch {
    Write-Info 'Aktivasyon sonra UI''dan: workflow sayfasında sağ üst toggle'
  }
} else {
  Write-Info 'UI''dan açabilirsin: sağ üst toggle ile Active konumuna al'
}

# ---------- 9. Success ----------
Write-Step 'Tamamlandı'
Write-Host @"

  Workflow URL: $script:N8N_URL/workflow/$($wfResp.id)

  Hemen test etmek için:
    1. URL''yi aç
    2. Sağ alt 'Execute workflow' veya Ctrl+Enter
    3. Tüm node''lar yeşillenince posta kutunu kontrol et

  İlk schedule: yarın 09:00 (Europe/Istanbul)

"@ -ForegroundColor Green

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
