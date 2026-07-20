# Telegram — setup (OpenClaw Diretor + legado Hermes)

**Caminho recomendado (arquitetura completa):** Telegram → **OpenClaw nativo** → agente **`diretor`** (orquestra Analista/Estrategista/…). Ver [AGENCY-MULTIAGENT.md](./AGENCY-MULTIAGENT.md).

**Legado / 1-agente:** Telegram → **Hermes** long polling (abaixo). Não use os dois no mesmo `TELEGRAM_BOT_TOKEN` ao mesmo tempo.

Docs: [OpenClaw Telegram](https://docs.openclaw.ai/channels/telegram) · [Hermes Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram)

## Pré-requisitos já feitos neste deploy

- Container `openclaw-vibestack-wa` com OpenClaw gateway + Hermes
- Modelo default: **ApiProMax** (`gpt-5.4-mini`) — ver [APIPROMAX.md](./APIPROMAX.md). Ollama só como fallback
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ALLOWED_USERS` no `.env` da VPS (e secrets locais)
- Após o bootstrap da agência: canal OpenClaw ligado ao **Diretor**; token Hermes zerado no volume para evitar double-poll

## O que você precisa fazer (5 min)

### 1. Criar o bot

1. No Telegram, abra [@BotFather](https://t.me/BotFather)
2. Envie `/newbot`
3. Escolha nome e username (deve terminar em `bot`)
4. Copie o token (`123456789:AA...`)

### 2. Descobrir seu user ID

Abra [@userinfobot](https://t.me/userinfobot) e copie o número (não é o @username).

### 3. Colar na VPS

No host (`/opt/agenciamart-ia/vibestack-openclaw/.env`) **e** no volume Hermes:

```bash
# .env do projeto (compose)
TELEGRAM_BOT_TOKEN=cole_aqui
TELEGRAM_ALLOWED_USERS=seu_id_numerico

# Volume persistente (o gateway lê daqui)
docker exec -it openclaw-vibestack-wa bash -lc '
  printf "TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_ALLOWED_USERS=%s\n" \
    "COLE_TOKEN" "COLE_USER_ID" > /tmp/tg.env
  # merge sem apagar OLLAMA_* já presentes:
  grep -v "^TELEGRAM_" /root/.hermes/.env > /tmp/h.env || true
  cat /tmp/tg.env >> /tmp/h.env
  mv /tmp/h.env /root/.hermes/.env
  chmod 600 /root/.hermes/.env
'
```

Atualize também `~/.vibestack-openclaw-easypanel.env` no laptop (não commitar).

### 4. Reiniciar só o OpenClaw/Hermes (não o Evolution)

```bash
docker restart openclaw-vibestack-wa
# NÃO reinicie agenciamart-vibestack-evolution-go-1 — preserva a sessão WA
```

### 5. Home channel (obrigatório para cron / mensagens proativas)

No DM do bot, `/sethome` **ou** no volume Hermes:

```bash
# chat_id do DM = seu user id (@userinfobot)
TELEGRAM_HOME_CHANNEL=137339320
TELEGRAM_HOME_CHANNEL_NAME="Seu Nome"
```

Sem home channel, o Hermes avisa e pede `/sethome`. Se o agente estiver no meio de um turno Ollama lento, `/sethome` falha com “can't run mid-turn” — espere acabar, mande `/stop`, ou reinicie só `openclaw-vibestack-wa`.

### 6. Validar

```bash
docker exec openclaw-vibestack-wa hermes status | grep -A2 Telegram
# Telegram ✓ configured (home: <chat_id>)

# No Telegram: /start → oi
```

## Performance

Com **ApiProMax** (default), “oi” deve responder em poucos segundos. Ollama local (`llama3.2:3b` CPU) só se você voltar o provider para `custom:ollama` — aí ~30–90s sob carga.

Notas Hermes:

- `model.context_length` ≥64k (gate interno do Hermes)
- `TELEGRAM_HOME_CHANNEL` no `.env` do Hermes
- entrypoint sobe **Hermes/Telegram antes** dos `openclaw mcp set`

Se travar “typing”: `/stop` no chat, ou `docker restart openclaw-vibestack-wa` (não reinicie o Evolution).

## Modo

- Default: **long polling** (não precisa de URL pública / webhook)
- Webhook só se definir `TELEGRAM_WEBHOOK_URL` (não necessário neste VPS)

## Segurança

- Sempre preencha `TELEGRAM_ALLOWED_USERS` (CSV de IDs)
- Não commite tokens; só `.env` / secrets locais / volume Hermes
