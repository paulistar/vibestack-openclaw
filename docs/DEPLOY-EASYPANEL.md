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
