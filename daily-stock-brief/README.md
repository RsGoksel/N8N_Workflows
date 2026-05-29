# Daily Stock Brief — Installer

Her sabah 9'da, ABD piyasasının Türkçe AI özetini e-postana atan n8n otomasyonu.
**Aylık maliyet ~$0.05** (sadece LLM, geri kalan free).

## 30 Saniyede Ne Yapar

- 09:00 (TR saati, Pzt-Cuma) tetiklenir
- Alpaca'dan top 5 kazanan + top 5 kaybeden + sizin watchlist'iniz
- xAI Grok ile Türkçe HTML brief üretir (gradient header, renkli tablolar, 3 maddelik içgörü)
- Gmail SMTP ile mail kutunuza atar

[Örnek çıktı](./sample-output.html)

## Kurulum (3 dakika)

### 1. Gereksinimler
- **Docker Desktop** — https://docker.com/products/docker-desktop (çalışır durumda)
- **3 ücretsiz hesap:**
  - [Alpaca Markets](https://app.alpaca.markets/) (paper trading hesabı, kart gerekmez)
  - [xAI Console](https://console.x.ai/) ($5 ücretsiz kredi yeterli, yıllık ~$0.55 maliyet)
  - Gmail (App Password kullanacaksınız)

### 2. Kurulumu çalıştır

**Windows:**
```powershell
.\setup.ps1
```

**macOS / Linux:**
```bash
chmod +x setup.sh && ./setup.sh
```

Sihirbaz seni adım adım yönlendirecek:
1. Docker container'ı başlatır
2. n8n hesabı + API key oluşturmanı ister (tarayıcı açar)
3. Provider key'lerini sorar (sırayla yapıştır)
4. Alpaca + Grok credential'larını otomatik kurar
5. SMTP credential için tarayıcıda formu açar (n8n API SMTP'yi desteklemiyor, 30 sn manuel)
6. Workflow'u import eder, aktive eder

**SMTP adımı için:** Tarayıcı `Credentials > New` sayfasını açar. Type olarak "SMTP" seçersin, alanları yapıştırırsın, Save. Script credential'ı otomatik bulup workflow'a bağlar.

### 3. Test

Kurulum biter bitmez tarayıcıda workflow URL'i açılır. **Ctrl+Enter** ile manuel test çalıştır — birkaç saniye içinde mail kutunda olmalı.

## Özelleştirme

`Config` node'unu aç (workflow editöründe):
- `watchlist`: takip edilen hisseler (virgülle ayır)
- `recipientEmail`: hedef e-posta
- `topMoverCount`: kaç gainer/loser (default 5)
- `llmModel`: Grok modeli (default `grok-3-mini`, premium için `grok-3`)

Schedule değiştir (`Daily 09:00 TR` node):
- Cron: `0 9 * * 1-5` → her gün 9 için `0 9 * * *`, sabah-akşam için `0 9,17 * * 1-5`

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| Docker yok | Docker Desktop kur ve başlat |
| n8n 30 sn'de hazır olmadı | `docker logs n8n-stock-brief` ile logları gör |
| Alpaca auth fail | Paper account key'i kullandığından emin ol (PK ile başlar) |
| Grok rate limit | $5 free kredi bitmiş olabilir, [console.x.ai/billing](https://console.x.ai/billing) |
| SMTP auth fail | App password kullandığından emin ol, normal Gmail şifresi olmaz |
| Mail spam'e düşüyor | İlk mail için Gmail'de "Not spam" işaretle |

## Mimari

```
Schedule (cron 09:00 TR)
        ↓
   Config (watchlist, model, email)
        ↓
   Alpaca Movers (top gainers + losers)
        ↓
   Alpaca Snapshots (watchlist)
        ↓
   Build Market Summary (JS: format + prompt)
        ↓
   Grok 3 mini (HTML üretimi, ~$0.002/call)
        ↓
   Extract HTML (clean output)
        ↓
   Gmail SMTP (HTML email)
```

## Maliyet

| Bileşen | Free tier yeterli mi? |
|---------|------------------------|
| Docker / n8n | Evet (lokal) |
| Alpaca Movers + Snapshots | Evet (IEX-only feed) |
| xAI Grok | $5 credit ≈ 2500 brief = ~10 yıl |
| Gmail SMTP | Evet (500 mail/gün) |

## Lisans

MIT — istediğin gibi modifiye et, dağıt, sat.
