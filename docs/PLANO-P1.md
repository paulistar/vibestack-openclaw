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
| 3 | **P1.2** Seeds `mart-studios` / `difrare` com **dados reais** + sync volume | [x] **feito** (não opcional) |
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

## P1.2 — Clientes com dados reais (obrigatório)

### Objetivo
`clients/mart-studios/` e `clients/difrare/` utilizáveis pelo agente `cliente` **sem** depender de checklist Telegram. Gaps pontuais usam `[A CONFIRMAR]` — não template vazio.

### Feito (2026-07-20)
- [x] **Mart Studios** — PROFILE/brand/offers/history: site `martstudiosbr.com.br`, tagline, Instagram `@martstudiosbr`, TG `@chatmartstudios_bot`, domínios agência/painel/evo/hermes, e-mail `assessoria@martstudiosbr.com`, MCC Google `1455071541`, ofertas (mídia, e-com Mart Art, OpenClaw)
- [x] **Difrare** — PROFILE/brand/offers/history: `difrare.com.br`, moda feminina produção própria, Italian Plum `#533147` + Playfair/Inter, WhatsApp `(15) 98183-0000`, endereço Tietê/SP, lookbook/atacado, SKUs/preços Store API, cupom `BEMVINDA10`, stack Woo+MP+Bling+Resend
- [x] `clients/INDEX.md` atualizado (status **ativo**)
- [x] Sync volume VPS `/root/.openclaw/workspace/clients/` (via bootstrap `CLIENTS_SRC` / cópia)
- [x] Confirmação: agente `cliente` consegue ler os arquivos no path do container

### Ainda `[A CONFIRMAR]` (pontual — não bloqueia P1.2)
- Mart: `act_` Meta; Customer ID Google próprio; fee comercial; número WhatsApp DDI
- Difrare: `act_` Meta; Google Ads Customer ID; tabela atacado; alvos CPA/ROAS; UGC/avaliações públicas

Telegram “Mais info …” continua válido para **completar gaps**, não para preencher o perfil do zero.

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

- `4fbddec` — `feat: plano P1 — Hermes TG off, Claude OpenClaw, seeds e docs MCP` (em `origin/main`)
- `31a6de0` — `docs: fechar PLANO-P1 com commit 4fbddec e status VPS`
- *(P1.2 dados reais)* — `clients/mart-studios` + `clients/difrare` + `PLANO-P1.md`

## Deploy VPS (fechamento)

- [x] `git pull` em `/opt/agenciamart-ia/vibestack-openclaw` → `4fbddec`
- [x] Recreate só `openclaw-vibestack` (easypanel + override) — Evolution **não** tocado (`agenciamart-vibestack-evolution-go-1` Up)
- [x] Bootstrap: providers `apipromax-gpt` + `apipromax-claude`; clients sync (`mart-studios`, `difrare`)
- [x] Confirmação: Hermes Telegram `✗ not configured`; OpenClaw TG `@chatmartstudios_bot` polling
- [ ] Pós-P1.2: `git pull` + sync `clients/` no volume (sem recreate Evolution)
