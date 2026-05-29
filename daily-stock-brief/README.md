# Daily Stock Brief

A fully automated n8n workflow that emails you a **Turkish, AI-generated US stock market brief every weekday morning at 9 AM**.
**Annual cost: ~$0.55** (LLM only — everything else is free tier).

> Localization note: the workflow produces Turkish HTML. If you want English (or any other language), change the prompt in the `Build Market Summary` node — see [Customization](#customization).

## What It Does

- **09:00 Mon–Fri** (Europe/Istanbul) trigger
- Fetches **top 5 gainers + top 5 losers** from Alpaca screener API
- Snapshots your custom watchlist (10 default tickers)
- Sends both to **xAI Grok 3 mini** with an HTML-styled prompt
- Grok returns a styled email body (gradient header, color-coded tables, 3 insights, disclaimer)
- Delivered to your inbox via Gmail SMTP

[See sample output](./sample-output.html)

## Why It Exists

Most stock briefing tools cost $20–$50/month. This one is yours for ~$0.55/year, runs on your own machine, and the prompt is fully editable.

## Stack

| Component | Free tier? | Notes |
|-----------|------------|-------|
| **n8n** | Yes (self-hosted via Docker) | Workflow runtime |
| **Alpaca Markets** | Yes | Real US market data via IEX feed |
| **xAI Grok 3 mini** | $5 free credit ≈ 2,500 briefs | OpenAI-compatible API |
| **Gmail SMTP** | Yes (500 mails/day) | App Password auth |
| **Docker Desktop** | Yes | Container runtime |

## Installation (3 minutes)

### Prerequisites
- **Docker Desktop** installed and running ([download](https://docker.com/products/docker-desktop))
- Three free accounts (the script links you to each):
  - [Alpaca Markets](https://app.alpaca.markets/) — paper trading account (no card required)
  - [xAI Console](https://console.x.ai/) — $5 free credit (≈ 10 years of daily briefs)
  - Gmail with an [App Password](https://myaccount.google.com/apppasswords)

### Run the installer

**Windows:**
```powershell
.\setup.ps1
```

**macOS / Linux:**
```bash
chmod +x setup.sh && ./setup.sh
```

The wizard will:
1. Start a local n8n Docker container
2. Open your browser to create an n8n account
3. Open `Settings → API` for you to copy a key
4. Ask for your Alpaca + Grok + Gmail credentials
5. Validate each by making a real API call
6. Create the Alpaca + Grok credentials in n8n automatically
7. Open the SMTP credential form (n8n's public API doesn't support SMTP — 30 seconds of paste-and-save)
8. Auto-discover the SMTP credential by name
9. Substitute IDs into the workflow template and import it
10. Optionally activate it

### Test it

The wizard prints the workflow URL when it finishes. Open it and press **Ctrl+Enter** (or click "Execute workflow" bottom-right). All nodes should turn green within ~15 seconds and the brief should land in your inbox.

## Workflow Architecture

```
Schedule Trigger (cron: 0 9 * * 1-5, Europe/Istanbul)
        ↓
   Config (watchlist, recipient, model, top-mover count)
        ↓
   Alpaca Market Movers   (HTTP, /v1beta1/screener/stocks/movers)
        ↓
   Alpaca Watchlist Snapshots   (HTTP, /v2/stocks/snapshots?symbols=...)
        ↓
   Build Market Summary   (JS Code — formats payload + builds Grok prompt)
        ↓
   Generate Brief (Grok)   (HTTP POST api.x.ai/v1/chat/completions)
        ↓
   Extract HTML   (JS Code — pulls assistant message, strips code fences)
        ↓
   Send Brief Email   (SMTP)
```

The chain is intentionally **sequential** so each step can read previous outputs via `$('NodeName').first().json` without needing Merge nodes.

## Customization

Open the **Config** node in the workflow editor:

| Field | Default | Controls |
|-------|---------|----------|
| `watchlist` | `AAPL,MSFT,NVDA,TSLA,GOOGL,META,AMZN,NFLX,AMD,SPY` | Comma-separated tickers in the snapshot table |
| `recipientEmail` | (set during install) | Where the brief is delivered |
| `llmModel` | `grok-3-mini` | Switch to `grok-3` for deeper analysis (~10× cost) |
| `topMoverCount` | `5` | How many gainers / losers to include |

### Schedule

Edit the cron expression in the **Daily 09:00 TR** node:
- `0 9 * * 1-5` → weekdays at 9 AM (default)
- `0 9,17 * * 1-5` → twice a day (morning + close)
- `0 9 * * *` → every day including weekends

### Switch language / prompt

Open the **Build Market Summary** node. The bottom half of the JS code builds `systemPrompt` and `userPrompt` — rewrite them in your target language. The LLM follows your instructions; the rest of the pipeline doesn't care about language.

### Swap LLM provider

`Generate Turkish Brief (Grok)` is a plain HTTP node calling an OpenAI-compatible endpoint. To switch:

- **OpenAI**: Change URL to `https://api.openai.com/v1/chat/completions`, update the credential header to `Authorization: Bearer sk-...`, set `llmModel` to `gpt-4o-mini`. Body shape already matches.
- **Anthropic**: Change URL to `https://api.anthropic.com/v1/messages`, update body to Anthropic's `messages` format. Slightly more work.
- **Google Gemini**: Use `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` and Gemini's body shape (`contents` + `systemInstruction`). Note Gemini 2.5 needs `thinkingConfig: { thinkingBudget: 0 }` to avoid eating output tokens.

## Cost Breakdown

Measured token usage per execution:
- Input: ~1,500 tokens (Alpaca data + prompt)
- Output: ~2,000 tokens (HTML brief)
- Total: ~3,500 tokens × Grok 3 mini pricing ($0.30/M input + $0.50/M output)
- **Per call: ~$0.0022**

Daily runs × 250 weekdays/year = **~$0.55/year**.

Using `grok-3` for deeper analysis is ~10× more expensive — still under $6/year.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Docker not installed | Install Docker Desktop and start it |
| `n8n not ready in 30s` | Check `docker logs n8n-stock-brief` |
| Alpaca returns 401 | Ensure key starts with `PK` (paper account) and both Key ID + Secret are pasted |
| Grok returns 429 | Free credit exhausted — top up at [console.x.ai/billing](https://console.x.ai/billing) |
| Grok response empty / truncated | Increase `max_tokens` in the Grok node body, or lower `reasoning_effort` |
| SMTP auth fails | Use Gmail **App Password**, not your account password. Requires 2FA first. |
| First email lands in spam | Mark "Not spam" once — subsequent emails go to inbox |
| Workflow runs but no email | Check `Send Brief Email` node output for SMTP error details |

## File Reference

| File | Purpose |
|------|---------|
| `setup.ps1` | Windows interactive installer |
| `setup.sh` | macOS / Linux interactive installer |
| `docker-compose.yml` | n8n container definition (port 5678, Europe/Istanbul TZ) |
| `workflow.template.json` | Workflow JSON with `{{CREDENTIAL_ID}}` placeholders |
| `sample-output.html` | What the email looks like (open in browser) |
| `README.md` | This file |

## License

MIT — see [`../LICENSE`](../LICENSE). Use it, modify it, distribute it, sell it.

## Contributing

Issues and PRs welcome at [the repo](https://github.com/RsGoksel/N8N_Workflows).
