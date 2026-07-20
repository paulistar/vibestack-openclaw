# Telegram — setup (OpenClaw Diretor + legado Hermes)

**Caminho recomendado:** Telegram → **OpenClaw nativo** → agente **`diretor`**. Ver [AGENCY-MULTIAGENT.md](./AGENCY-MULTIAGENT.md).

**Legado / 1-agente:** Telegram → **Hermes** long polling (seção no final). **Não** use os dois no mesmo `TELEGRAM_BOT_TOKEN`.

Docs: [OpenClaw Telegram](https://docs.openclaw.ai/channels/telegram) · [Hermes Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram)

## Pré-requisitos (deploy atual)

- Container `openclaw-vibestack-wa` com OpenClaw gateway + Hermes
- Modelo default: **ApiProMax GPT** — ver [APIPROMAX.md](./APIPROMAX.md); Claude opcional (`apipromax-claude`)
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ALLOWED_USERS` no `.env` da VPS (OpenClaw)
- Bootstrap: canal OpenClaw → Diretor; Hermes com `TELEGRAM_*=` vazio + `env -u` no gateway (P1.4)

## O que você precisa fazer (5 min) — OpenClaw Diretor

### 1. Criar o bot

1. [@BotFather](https://t.me/BotFather) → `/newbot`
2. Copie o token

### 2. Descobrir seu user ID

[@userinfobot](https://t.me/userinfobot) → copie o número.

### 3. Colar só no `.env` do projeto (NÃO no Hermes)

```bash
# /opt/agenciamart-ia/vibestack-openclaw/.env
TELEGRAM_BOT_TOKEN=cole_aqui
TELEGRAM_ALLOWED_USERS=seu_id_numerico
```

Espelho local: `~/.vibestack-openclaw-easypanel.env` (não commitar).

### 4. Bootstrap + reinício (sem Evolution)

```bash
# ver docs/AGENCY-MULTIAGENT.md — bootstrap-agency-openclaw.sh
docker restart openclaw-vibestack-wa
# NÃO reinicie agenciamart-vibestack-evolution-go-1
docker exec openclaw-vibestack-wa openclaw channels status --probe
docker exec openclaw-vibestack-wa hermes status | grep -A2 Telegram
# esperado: Telegram ✗ not configured
```

### 5. Validar

No Telegram: abra o bot → `/start` → `oi`.  
Alimentar clientes: checklist em [PLANO-P1.md](./PLANO-P1.md) (P1.2).

## Segurança

- Sempre preencha `TELEGRAM_ALLOWED_USERS` (CSV de IDs)
- Não commite tokens

## Modo

- Default OpenClaw: **long polling** (sem URL pública)

---

## Legado — Hermes Telegram (só se NÃO usar OpenClaw no mesmo bot)

Só para stack 1-agente Hermes. Se o Diretor OpenClaw já usa o bot, **pule esta seção**.

```bash
# Volume Hermes — SOMENTE se Hermes for o único consumidor do token
docker exec -it openclaw-vibestack-wa bash -lc '
  printf "TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_ALLOWED_USERS=%s\n" \
    "COLE_TOKEN" "COLE_USER_ID" > /tmp/tg.env
  grep -v "^TELEGRAM_" /root/.hermes/.env > /tmp/h.env || true
  cat /tmp/tg.env >> /tmp/h.env
  mv /tmp/h.env /root/.hermes/.env
  chmod 600 /root/.hermes/.env
'
docker restart openclaw-vibestack-wa
```

Home channel (Hermes cron): `/sethome` ou `TELEGRAM_HOME_CHANNEL` no `.env` Hermes.

Para **voltar** ao modo Diretor: zere `TELEGRAM_*` no Hermes (bootstrap/entrypoint fazem isso) e mantenha o token só no `.env` do projeto + `openclaw.json`.
