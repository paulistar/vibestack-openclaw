# Plano P1 — auditoria (ordenado)

Última atualização: 2026-07-20  
Ambiente: repo local + VPS `/opt/agenciamart-ia/vibestack-openclaw`  
Secrets local: `~/.vibestack-openclaw-easypanel.env`  
Deploy: `docker-compose.easypanel.yml` + `docker-compose.override.yml` — **nunca** dropar Evolution.

## Legenda

- [x] feito
- [ ] pendente
- [!] bloqueado (precisa input/keys do usuário)

---

## Ordem de execução

| # | Item | Status |
|---|------|--------|
| 1 | **P1.4** Limpar/desativar Telegram no Hermes; só OpenClaw Diretor no TG | [x] |
| 2 | **P1.3** Provider Claude (`apipromax-claude`) no OpenClaw | [x] código / deploy |
| 3 | **P1.2** Seeds `mart-studios` / `difrare` + ingestão Telegram | [x] seeds / [ ] dados finais via bot |
| 4 | **P1.1** Keys Meta / Google / B2 (MCPs) | [x] docs+example / [!] **AGUARDANDO KEYS** |

---

## P1.4 — Telegram só no OpenClaw Diretor

### Objetivo
Evitar double-poll: Hermes **não** long-poll o mesmo `TELEGRAM_BOT_TOKEN` do Diretor.

### Feito
- [x] VPS: `hermes status` → Telegram `✗ not configured`
- [x] VPS: OpenClaw `channels status --probe` → `@chatmartstudios_bot` → Diretor
- [x] Volume Hermes: `TELEGRAM_BOT_TOKEN=` / `TELEGRAM_ALLOWED_USERS=` vazios
- [x] Entrypoint: zera `TELEGRAM_*` no `.env` Hermes a cada boot (`HERMES_DISABLE_TELEGRAM=1`)
- [x] Entrypoint: `hermes gateway run` sobe com `env -u TELEGRAM_*` (compose ainda passa token pro OpenClaw)
- [x] Docs: `TELEGRAM-SETUP.md` (caminho Diretor primeiro; Hermes só legado)

### Validar após recreate
```bash
docker exec openclaw-vibestack-wa hermes status | grep -A2 Telegram
docker exec openclaw-vibestack-wa openclaw channels status --probe
```

---

## P1.3 — Claude no OpenClaw (ApiProMax)

### Objetivo
Registrar `apipromax-claude` (key ProMax Claude já existe nos secrets).

### Feito
- [x] `APIPROMAX_CLAUDE_API_KEY` no `.env` VPS + secrets local
- [x] Bootstrap registra GPT + Claude; default GPT
- [x] Compose passa `APIPROMAX_*` / `OPENCLAW_DEFAULT_PROVIDER`
- [x] Docs: `APIPROMAX.md`, `AGENCY-MULTIAGENT.md`, `.env.example`
- [ ] Smoke chat Claude pós-bootstrap (opcional): `openclaw models set apipromax-claude/claude-sonnet-5`

Modelos Claude no catálogo: `claude-sonnet-5`, `claude-opus-4-7`, `claude-opus-4-8`, `claude-fable-5`.

---

## P1.2 — Seeds + ingestão Telegram

### Feito
- [x] Seeds `mart-studios` / `difrare` utilizáveis (baseline + TODOs claros)
- [x] `clients/INDEX.md` + checklist abaixo
- [x] Sync via bootstrap `CLIENTS_SRC` → workspace

### Ainda via Telegram (usuário)
- [ ] Completar IDs ads, ofertas e brand finais no bot

### Checklist — mandar ao Diretor (@chatmartstudios_bot)

**Mart Studios**
```
Mais info mart-studios:
- Contato principal: (nome + WhatsApp/Telegram)
- Meta Ad Account ID: act_…
- Google Ads Customer ID: …
- Oferta principal: nome, preço, CTA, URL
- Cores / tipografia / o que NÃO usar em criativos
```

**Difrare**
```
Mais info difrare:
- Site oficial / Instagram
- Segmento + ticket médio
- ICP: quem, dor, objeção
- Meta Ad Account ID + Google Ads Customer ID
- Ofertas ativas (promessa, preço, CTA, landing)
- O que NÃO vender agora
- Tom: 2 frases OK + 2 proibidas
- Claims / disclaimers se aplicável
```

---

## P1.1 — Keys Meta / Google / B2 (MCPs)

### Feito (repo)
- [x] Placeholders + comentários em `.env.example`
- [x] Entrypoint registra MCPs e avisa se keys vazias
- [x] Docs de onde colar secrets

### VPS / secrets — status 2026-07-20

| Var | Local | VPS | Status |
|-----|-------|-----|--------|
| `META_ACCESS_TOKEN` | EMPTY | EMPTY | [!] **AGUARDANDO KEYS** |
| `META_AD_ACCOUNT_ID` | EMPTY | EMPTY | [!] **AGUARDANDO KEYS** |
| `GOOGLE_ADS_*` (dev/client/secret/refresh/customer) | EMPTY | EMPTY | [!] **AGUARDANDO KEYS** |
| `B2_KEY_ID` / `B2_APP_KEY` / `B2_BUCKET` | EMPTY | EMPTY | [!] **AGUARDANDO KEYS** |

> Etapa **parada** até o usuário fornecer as keys. Não inventar tokens.

### Quando as keys chegarem
1. Colar em VPS `.env` + `~/.vibestack-openclaw-easypanel.env` (`chmod 600`)
2. Recreate **só** `openclaw-vibestack` (easypanel+override) — **não** Evolution
3. Validar `openclaw mcp list` + smoke

---

## Deploy cuidadoso

```bash
cd /opt/agenciamart-ia/vibestack-openclaw
git pull

COMPOSE_PROJECT_NAME=vibestack-openclaw \
  docker compose -f docker-compose.easypanel.yml -f docker-compose.override.yml \
  up -d --no-deps --force-recreate openclaw-vibestack

# Bootstrap (Claude + clients) — ver AGENCY-MULTIAGENT.md
# NÃO: docker compose down / restart evolution
```

---

## Commits desta rodada

*(preenchido após push)*
