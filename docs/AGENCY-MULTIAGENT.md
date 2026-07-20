# Agência multi-agente (Passo 13) — OpenClaw

Setup da arquitetura completa do repo: **Diretor (orquestrador)** + 5 especialistas, spawn cruzado (`sessions_spawn`), modelos via **ApiProMax** (não Ollama como default).

Templates: [`agency/`](../agency/). Tutorial upstream: Passo 13 do README.

## O que este deploy faz

| Peça | Onde |
|------|------|
| Prompts SOUL/AGENTS/… | `/root/.openclaw/workspace/<agente>/` (volume) |
| Agentes OpenClaw | `diretor` (default), `analista`, `estrategista`, `copywriter`, `criativo`, `gestor` (+ `main` legado) |
| Subagentes | `maxSpawnDepth: 2`, `allowAgents: ["*"]`, `announceTimeoutMs: 300000` |
| Modelo | `apipromax-gpt/<APIPROMAX_DEFAULT_MODEL>` (ex.: `gpt-5.4-mini`) |
| Tools MCP | `tools.profile: coding` → meta-ads, google-ads, whatsapp, etc. |
| Telegram | **OpenClaw nativo** → bind no **Diretor** (Hermes deixa de fazer poll no mesmo bot) |
| WhatsApp | Bridge Evolution: `WA_BRIDGE_AGENT=openclaw` + `WA_BRIDGE_OPENCLAW_AGENT=diretor` |

## Bootstrap (VPS)

```bash
# No host, com o repo em /opt/agenciamart-ia/vibestack-openclaw
cd /opt/agenciamart-ia/vibestack-openclaw

# Carrega secrets (ApiProMax + Telegram) — NÃO commitar
set -a
# shellcheck disable=SC1091
source .env
set +a

docker cp scripts/bootstrap-agency-openclaw.sh openclaw-vibestack-wa:/tmp/bootstrap-agency-openclaw.sh
docker cp agency openclaw-vibestack-wa:/tmp/agency

docker exec \
  -e APIPROMAX_BASE_URL -e APIPROMAX_GPT_API_KEY -e APIPROMAX_DEFAULT_MODEL \
  -e TELEGRAM_BOT_TOKEN -e TELEGRAM_ALLOWED_USERS \
  -e AGENCY_SRC=/tmp/agency \
  openclaw-vibestack-wa bash /tmp/bootstrap-agency-openclaw.sh

# Só o OpenClaw/Hermes — NÃO reinicie o Evolution (sessão WA)
docker restart openclaw-vibestack-wa
```

> **Compose na VPS:** use sempre `docker-compose.easypanel.yml` (+ override).  
> `docker compose -f docker-compose.yml ...` faz bind em `/root/.openclaw` e **desconecta** o volume nomeado `vibestack-openclaw_openclaw-data` (onde está a config dos agentes).  
> Recreate seguro:
> ```bash
> COMPOSE_PROJECT_NAME=vibestack-openclaw \
>   docker compose -f docker-compose.easypanel.yml -f docker-compose.override.yml \
>   up -d --no-deps --force-recreate openclaw-vibestack
> ```

Validar:

```bash
docker exec openclaw-vibestack-wa openclaw agents list
docker exec openclaw-vibestack-wa openclaw config get agents.defaults.subagents
docker exec openclaw-vibestack-wa openclaw mcp list
docker exec openclaw-vibestack-wa openclaw channels status --probe
```

## Como pedir no Telegram (orquestrador)

Fale com o **mesmo bot**; quem responde é o **Diretor** (OpenClaw). Exemplos:

- `Oi — quem é você e quais especialistas você coordena?`
- `Delegue ao analista um resumo das campanhas Meta Ads (só leitura) e me traga 3 bullets.`
- `Quero uma análise crítica + recomendação de budget; se passar da alçada, me peça aprovação.`
- `Com briefing X, peça à estrategista que convoque o copywriter (3 variações) — sem publicar.`

O Diretor deve chamar `sessions_spawn` com `runtime: 'subagent'`, `agentId: 'analista'|…`, e **não** usar `sessions_yield` (não existe neste build).

## Fluxo interno

```
Você (Telegram/WA) → Diretor
  → Analista (leitura Meta)
  → Estrategista (decide; alçada 30% / R$ 200/dia)
      → Copywriter / Criativo (peças)
      → Gestor (único que escreve no Meta) — só com ordem/aprovação
```

## Hermes vs OpenClaw no Telegram

| Modo | Quando usar |
|------|-------------|
| **OpenClaw → Diretor** (recomendado aqui) | Arquitetura completa da agência + spawn |
| Hermes Telegram 1-agente | Chat rápido sem orquestração (docs/TELEGRAM-SETUP.md legado) |

Não rode os dois em long-poll no **mesmo** `TELEGRAM_BOT_TOKEN` — o bootstrap zera o token no volume Hermes.

## WhatsApp → Diretor

No `.env` (e override, se houver):

```bash
WA_BRIDGE_AGENT=openclaw
WA_BRIDGE_OPENCLAW_AGENT=diretor
```

Reinicie **só** `openclaw-vibestack-wa`.

## Pendências típicas

- `META_ACCESS_TOKEN` / `META_AD_ACCOUNT_ID` — MCP meta-ads write/read útil
- Google Ads OAuth + developer token
- B2 / Higgsfield / AtlasCloud — só se for usar o Criativo de ponta a ponta
- Pairing Telegram: se `dmPolicy` pedir, `openclaw pairing approve telegram <code>`
