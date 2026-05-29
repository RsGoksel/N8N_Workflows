# Crypto Signal Bot

n8n workflow that scans the Binance USDT spot market every 30 minutes, asks **xAI Grok** to interpret the data, and sends **structured trading signals to your Telegram** chat or channel.

**Cost: $2–$35/year** depending on schedule frequency. Binance + Telegram are free.

## Example Output (Telegram)

```
Crypto Signals  📈 BULLISH
2026-05-29 14:30
Strong gainers led by ALLO suggest momentum-driven buying.

🟢 BTC — LONG
   Entry 67000  •  SL 65500  •  TP 70000
   Confidence: 70%
   Higher highs forming after 2-day consolidation; volume picking up.

🟢 ETH — LONG
   Entry 3400  •  SL 3280  •  TP 3650
   Confidence: 65%
   Outperforming BTC; bullish divergence on 4h.

⚪ SOL — HOLD
   Confidence: 50%
   Range-bound; wait for $180 reclaim.

🎯 Top Pick: ALLO — best risk/reward, 167% 24h pump, $123M volume.

Not financial advice. Data: Binance + xAI Grok.
```

## How It Works

```
Schedule (every 30 min) or Manual
        ↓
   Config (watchlist, chatId, language, schedule)
        ↓
   Binance 24h ticker  (HTTP GET, NO AUTH — 3,500+ tickers)
        ↓
   JS Analyze: filter clean USDT pairs by min volume → top gainers/losers + watchlist
        ↓
   Grok 3 mini  (HTTP POST → structured JSON signal)
        ↓
   JS Format → HTML for Telegram
        ↓
   Telegram sendMessage → your chat
```

## Stack

| Component | Free tier? | Notes |
|-----------|------------|-------|
| **n8n** | Yes (Docker self-host) | Workflow runtime |
| **Binance public API** | Yes | No auth needed for ticker data, 1,200 req/min |
| **xAI Grok 3 mini** | $5 free credit | ~$0.0004 per signal (cheap) |
| **Telegram Bot API** | Yes | Free unlimited, 30 msg/sec |

## Installation (5 minutes)

### Prerequisites
- **Docker Desktop** installed and running ([download](https://docker.com/products/docker-desktop))
- Two free accounts:
  - [xAI Console](https://console.x.ai/) — $5 free credit (≈ 12,000 signals)
  - A Telegram bot via [@BotFather](https://t.me/BotFather) (instant, no signup)

### Create your Telegram bot (60 sec)
1. Open Telegram → search **@BotFather** → start chat
2. Send `/newbot`
3. Pick a name and username (must end in `bot`)
4. Save the **token** BotFather gives you
5. Open the bot's chat and send it any message (so the installer can detect your chat ID)

### Run the installer

**Windows:**
```powershell
.\setup.ps1
```

**macOS / Linux:**
```bash
chmod +x setup.sh && ./setup.sh
```

The installer will:
1. Start a local n8n Docker container
2. Open the browser to create your n8n account
3. Open Settings → API to copy a key
4. Ask for your Grok key and Telegram bot token
5. Validate both with real API calls
6. **Auto-detect your Telegram chat ID** via `getUpdates`
7. Auto-create the Grok credential in n8n
8. Open the Telegram credential form (n8n's public API doesn't support `telegramApi` — 30 sec manual)
9. Auto-discover the saved Telegram credential by name
10. Substitute IDs into the workflow template and import it
11. Optionally activate it

## Customization

Open the **Config** node in the workflow editor:

| Field | Default | What it does |
|-------|---------|--------------|
| `watchlist` | 8 majors (BTC, ETH, SOL, BNB, XRP, DOGE, ADA, AVAX) | Always-included symbols regardless of volume |
| `telegramChatId` | (auto-set during install) | Where signals are delivered |
| `llmModel` | `grok-3-mini` | Switch to `grok-3` for deeper analysis (~10× cost) |
| `topMoverCount` | `5` | How many top gainers/losers to fetch |
| `minVolume24hUsd` | `10000000` | Filter out illiquid pairs ($10M default) |
| `language` | `tr` | Set to `en` for English output |

### Frequency

Open **Every 30 min** node and change `minutesInterval`:
- 5 → very aggressive (high cost, real-time feel)
- 30 → default, balance
- 60 → calmer, lower cost
- 240 → 4× per day for low-noise

### LLM provider

The Grok node uses an OpenAI-compatible Chat Completions API. To switch:

- **OpenAI**: URL → `https://api.openai.com/v1/chat/completions`, model → `gpt-4o-mini`. Body works as-is.
- **Anthropic**: URL → `https://api.anthropic.com/v1/messages`, restructure body for Claude's format.
- **Local (Ollama)**: URL → `http://localhost:11434/v1/chat/completions`, model → `llama3.1` etc.

## Cost Breakdown

Per signal: ~568 input + 380 output tokens × Grok 3 mini ($0.30/M input + $0.50/M output) = **~$0.0004 per call**.

| Schedule | Calls/year | Annual cost |
|----------|-----------|-------------|
| Every 30 min, 24/7 | 17,520 | ~$7 |
| Every hour, 24/7 | 8,760 | ~$4 |
| Every 30 min, market hours only | ~3,000 | ~$2 |
| Every 4 hours, 24/7 | 2,190 | ~$1 |

Even worst case is **less than $10/year**.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Installer: "No chats found" | Send your bot any message in Telegram before running setup |
| Installer: Grok 401 | Check the key prefix (`xai-...`) and that your xAI account has credit |
| Workflow: Grok 429 | Free credit exhausted — top up at [console.x.ai/billing](https://console.x.ai/billing) |
| Workflow: Binance 451 | Run from a non-restricted region or use a VPS proxy. Binance blocks some IPs |
| Telegram: "Bad Request" | Check that `chatId` in Config matches your actual chat ID |
| Signal JSON parse error | Grok occasionally wraps output in markdown fences — the parser strips them. If you see this, check the LLM model is `grok-3-mini` (not `grok-2` etc.) |
| Workflow runs but no Telegram msg | Make sure you SENT your bot a message first (creates the chat). If chat is empty, Telegram refuses messages |

## Selling This As a Product

If you want to monetize a packaged version:

- **Gumroad/Etsy**: bundle workflow + Loom video + customization guide → $49–149
- **Done-for-you**: install + custom watchlist + custom prompts → $199–499
- **Recurring SaaS**: host it for clients → $19–49/mo per user
- **Niche prompts**: swap the system prompt for sector-specific signals (memecoins, AI tokens, L2s, RWAs) → multiple $29 products from one template

The competitive moat is your prompt + watchlist + UX — not the workflow itself (open source).

## License

MIT — see [`../LICENSE`](../LICENSE). Use, modify, distribute, sell.
