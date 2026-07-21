# Agência multi-agente (Passo 13) — OpenClaw

Setup da arquitetura completa do repo: **Diretor (orquestrador)** + 5 especialistas, spawn cruzado (`sessions_spawn`), modelos via **ApiProMax** (não Ollama como default).

Templates: [`agency/`](../agency/). Tutorial upstream: Passo 13 do README.

## O que este deploy faz

| Peça | Onde |
|------|------|
| Prompts SOUL/AGENTS/… | `/root/.openclaw/workspace/<agente>/` (volume) |
| Agentes OpenClaw | `diretor` (default), `cliente`, `analista`, `estrategista`, `copywriter`, `criativo`, `gestor` (+ `main` legado) |
| Contexto de clientes | `clients/<slug>/` → `/root/.openclaw/workspace/clients/` — ver [CLIENTES.md](./CLIENTES.md) |
| Subagentes | `maxSpawnDepth: 2`, `allowAgents: ["*"]`, `announceTimeoutMs: 300000` |
| Modelo | Default `apipromax-gpt/<APIPROMAX_DEFAULT_MODEL>`; opcional `apipromax-claude/<APIPROMAX_CLAUDE_MODEL>` (ver [APIPROMAX.md](./APIPROMAX.md), [PLANO-P1.md](./PLANO-P1.md)) |
| Tools MCP | `tools.profile: coding` → meta-ads, google-ads, whatsapp, **web-research**, etc. |
| Telegram | **OpenClaw nativo** → bind no **Diretor** (Hermes deixa de fazer poll no mesmo bot) |
| WhatsApp | Bridge Evolution: `WA_BRIDGE_AGENT=openclaw` + `WA_BRIDGE_OPENCLAW_AGENT=diretor` |

## Web research (transversal)

MCP `web-research`: `web_search` + `web_fetch` (+ status). Serve **qualquer** frente da agência — não é tool de ads. Segurança SSRF + allowlist; memória em `clients/<slug>/` quando for fato de cliente. Guia: [WEB-RESEARCH.md](./WEB-RESEARCH.md).

No Telegram: *"Pesquise o site do cliente X e atualize a memória"* → Diretor usa search/fetch e spawna **Cliente** para gravar.

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
docker cp clients openclaw-vibestack-wa:/tmp/clients

docker exec \
  -e APIPROMAX_BASE_URL -e APIPROMAX_GPT_API_KEY -e APIPROMAX_CLAUDE_API_KEY \
  -e APIPROMAX_DEFAULT_MODEL -e APIPROMAX_CLAUDE_MODEL \
  -e OPENCLAW_DEFAULT_PROVIDER \
  -e TELEGRAM_BOT_TOKEN -e TELEGRAM_ALLOWED_USERS \
  -e AGENCY_SRC=/tmp/agency \
  -e CLIENTS_SRC=/tmp/clients \
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
- `Pro cliente mart-studios, consulte o agente cliente e me diga ICP + tom.` (ver [CLIENTES.md](./CLIENTES.md))
- `Temos um cliente novo: …` — o Diretor spawna `cliente` para **gravar** em `clients/<slug>/` (Telegram-first; ver [CLIENTES.md](./CLIENTES.md)).

O Diretor deve chamar `sessions_spawn` com `runtime: 'subagent'`, `agentId: 'cliente'|'analista'|…`, e **não** usar `sessions_yield` (não existe neste build). Em tarefa de cliente, **`cliente` vem antes** dos demais (ler ou escrever).

## Fluxo interno

```
Você (Telegram/WA) → Diretor
  → Cliente (lê contexto / **escreve** novo-update / valida marca-ICP)  ← obrigatório em tarefa de cliente
  → Analista (leitura Meta)
  → Estrategista (decide; alçada 30% / R$ 200/dia)
      → Copywriter / Criativo (peças)
      → Gestor (único que escreve no Meta) — só com ordem/aprovação
  → Cliente valida entregas → Diretor responde
```

## Hermes vs OpenClaw no Telegram

| Modo | Quando usar |
|------|-------------|
| **OpenClaw → Diretor** (recomendado aqui) | Arquitetura completa da agência + spawn |
| Hermes Telegram 1-agente | Chat rápido sem orquestração (docs/TELEGRAM-SETUP.md legado) |

Não rode os dois em long-poll no **mesmo** `TELEGRAM_BOT_TOKEN`. O bootstrap zera o token no volume Hermes; o entrypoint também faz **unset** de `TELEGRAM_*` no processo `hermes gateway run` (o compose ainda passa o token ao container para o OpenClaw). Plano: [PLANO-P1.md](./PLANO-P1.md) P1.4.

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
