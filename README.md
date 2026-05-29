# N8N Workflows

Production-ready [n8n](https://n8n.io) workflows with **one-script installers**.
Each folder is a self-contained workflow with its own setup wizard, no manual credential clicking required (mostly).

## Workflows

| Workflow | What It Does | Stack | Cost |
|----------|-------------|-------|------|
| [daily-stock-brief](./daily-stock-brief) | Sabah 09:00'da Türkçe AI piyasa brifingi mail kutuna düşer | Alpaca + xAI Grok + Gmail | ~$0.55/yıl |

## Why This Repo

Most n8n templates on the internet are JSON files with cryptic READMEs.
You spend an hour wiring credentials, debugging node connections, and figuring out which API endpoints to use.

**This repo's deal:** Each workflow ships with:
- An interactive installer (`setup.ps1` / `setup.sh`)
- Real credentials wired automatically via n8n REST API
- A working sample output (HTML/email/Slack preview)
- Cost breakdown — no surprises
- TR + EN documentation

## Quick Start

```bash
# 1. Pick a workflow
cd daily-stock-brief

# 2. Run installer
./setup.sh        # macOS / Linux
.\setup.ps1       # Windows

# 3. Follow prompts (3-5 dakika)
```

## Requirements

- Docker Desktop (workflows run in containerized n8n)
- Provider API keys (each workflow lists what it needs)

## Contributing

PRs welcome for new workflows. Folder structure should follow:

```
workflow-name/
├── README.md                  # What it does + setup + costs
├── setup.ps1                  # Windows installer
├── setup.sh                   # Mac/Linux installer
├── docker-compose.yml         # n8n container config
├── workflow.template.json     # Workflow with credential placeholders
└── sample-output.html         # Visual preview of expected output
```

## Maintainer

[@RsGoksel](https://github.com/RsGoksel)
