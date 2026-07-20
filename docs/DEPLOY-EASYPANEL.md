# Deploy EasyPanel — vibestack-openclaw

Projeto EasyPanel: `agenciamart-ia`  
Serviço compose: `vibestack-openclaw`  
Repo: `https://github.com/paulistar/vibestack-openclaw` (`main`)  
Compose file: **`docker-compose.easypanel.yml`** (só este)

## Não faça Deploy cego

Um Deploy EasyPanel faz `git pull` + `compose up` com **apenas** `docker-compose.easypanel.yml`.

| O que | Risco se Deploy cego |
| --- | --- |
| `.env` na VPS (`/opt/agenciamart-ia/vibestack-openclaw/.env`) | Pode ser sobrescrito / perdido se o painel não tiver os mesmos secrets |
| `docker-compose.override.yml` | **Ignorado** pelo EasyPanel — redes/env do override não entram |
| Sessão WhatsApp (volume `evolution-data`) | Em geral persiste; rebuild agressivo pode forçar novo QR |
| Bridge→Ollama | Já versionado no `easypanel.yml` (defaults). Sem isso volta Hermes lento/timeout |

## Checklist pré-Deploy

1. `main` no GitHub já tem bridge→Ollama + redes `easypanel` + aliases.
2. Secrets no EasyPanel **ou** `.env` na VPS intacto (não versionar `.env`).
3. Após Deploy: Evolution `LoggedIn`, bridge `:8765` `/health`, Ollama `llama3.2:3b`.
4. Domínios: `agencia.martstudiosbr.com.br`, `hermes.agencia.martstudiosbr.com.br`, `evo.agencia.martstudiosbr.com.br`.

## Preferência operacional (hoje)

Stack saudável sobe em `/opt/agenciamart-ia/vibestack-openclaw` com compose project `agenciamart-vibestack`.  
Se não precisa de rebuild de imagem: **não Deploy** — só `git pull` e confirmar que `.env`/volumes ficam.

## Allowlist WhatsApp

`WA_BRIDGE_ALLOWED_NUMBERS` vazio = qualquer número fala com o agente.  
Preencha no `.env` (CSV DDI+DDD+número) quando souber o(s) número(s) — ex.: `5511XXXXXXXX`.

## Provider cloud (opcional)

Sem chave cloud nos secrets locais → stack usa Ollama `llama3.2:3b`.  
Não bloqueia operação; adicionar `ATLASCLOUD_API_KEY` / similar só se quiser modelo cloud.

## Telegram (OpenClaw Diretor — prioridade)

Canal **OpenClaw nativo** → agente **`diretor`** (orquestra a agência). Não usa Evolution.
Detalhes: [AGENCY-MULTIAGENT.md](./AGENCY-MULTIAGENT.md) · [TELEGRAM-SETUP.md](./TELEGRAM-SETUP.md).

**Não** rode Hermes long-poll no mesmo `TELEGRAM_BOT_TOKEN` — o bootstrap zera o token no volume Hermes.

1. Crie o bot no [@BotFather](https://t.me/BotFather) → `/newbot` → copie o token.
2. Descubra seu user id numérico com [@userinfobot](https://t.me/userinfobot).
3. Preencha no `.env` da VPS (`/opt/agenciamart-ia/vibestack-openclaw/.env`):

```bash
TELEGRAM_BOT_TOKEN=123456789:AA...
TELEGRAM_ALLOWED_USERS=SEU_ID_NUMERICO
```

4. Rode o bootstrap da agência (grava `channels.telegram` + bind no Diretor) e reinicie só o OpenClaw (não o Evolution):

```bash
# ver docs/AGENCY-MULTIAGENT.md — bootstrap-agency-openclaw.sh
docker restart openclaw-vibestack-wa
docker exec openclaw-vibestack-wa openclaw channels status --probe
```

5. No Telegram: abra o bot → `/start` → envie uma mensagem de teste.

Placeholders também em `~/.vibestack-openclaw-easypanel.env` (local) e `.env.example`.

Legado 1-agente (Hermes Telegram): [TELEGRAM-SETUP.md](./TELEGRAM-SETUP.md). LLM Hermes/ApiProMax: [APIPROMAX.md](./APIPROMAX.md).
