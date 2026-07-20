# ApiProMax — providers GPT e Claude no Vibestack

Proxy OpenAI-compatible (`https://apipromax.online/v1`) usado como **default do Hermes** (legado Telegram 1-agente e, se `WA_BRIDGE_AGENT=hermes`, o canal WhatsApp).

**Telegram prioritário da stack:** OpenClaw nativo → agente **Diretor** (não Hermes). Ver [AGENCY-MULTIAGENT.md](./AGENCY-MULTIAGENT.md).

Ollama permanece como fallback opcional no `custom_providers`, não como default do Hermes.

## Variáveis (somente secrets locais / VPS)

```bash
APIPROMAX_BASE_URL=https://apipromax.online/v1
APIPROMAX_GPT_API_KEY=sk-...          # catálogo GPT
APIPROMAX_CLAUDE_API_KEY=sk-...       # catálogo Claude
APIPROMAX_DEFAULT_MODEL=gpt-5.4-mini  # default Hermes (legado TG / api_server)
```

Placeholders em `.env.example`. **Nunca** commitar keys reais.

Onde gravar:

| Local | Arquivo |
|-------|---------|
| VPS projeto | `/opt/agenciamart-ia/vibestack-openclaw/.env` |
| Hermes (volume) | `/root/.hermes/.env` + `custom_providers` em `/root/.hermes/config.yaml` |
| Mac (espelho) | `~/.vibestack-openclaw-easypanel.env` (`chmod 600`) |

## Hermes `custom_providers`

Duas entradas, **mesma** `base_url`, keys diferentes:

```yaml
model:
  provider: custom:apipromax-gpt
  default: gpt-5.4-mini
  base_url: https://apipromax.online/v1
  # api_key: (key GPT — só no volume, nunca no git)

custom_providers:
  - name: apipromax-gpt
    base_url: https://apipromax.online/v1
    api_key: sk-...   # GPT
    api_mode: chat_completions
    models:
      gpt-5.4-mini: { context_length: 128000 }
      # ... demais IDs do GET /v1/models com a key GPT
  - name: apipromax-claude
    base_url: https://apipromax.online/v1
    api_key: sk-...   # Claude
    api_mode: chat_completions
    models:
      claude-sonnet-5: { context_length: 200000 }
      # ... demais IDs do GET /v1/models com a key Claude
  - name: ollama
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama
    api_mode: chat_completions
    # fallback opcional
```

Trocar para Claude no runtime: `provider: custom:apipromax-claude` + `default: claude-sonnet-5` (ou outro ID do catálogo Claude).

## Conferir catálogo

```bash
curl -sS -H "Authorization: Bearer $APIPROMAX_GPT_API_KEY" \
  "$APIPROMAX_BASE_URL/models" | jq -r '.data[].id'

curl -sS -H "Authorization: Bearer $APIPROMAX_CLAUDE_API_KEY" \
  "$APIPROMAX_BASE_URL/models" | jq -r '.data[].id'
```

## Smoke

```bash
curl -sS "$APIPROMAX_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $APIPROMAX_GPT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"oi"}],"max_tokens":32}'

docker restart openclaw-vibestack-wa   # NÃO reinicie o Evolution
docker exec openclaw-vibestack-wa hermes status
```

Smoke Hermes (legado TG): no bot Hermes `/start` → `oi`.
Smoke OpenClaw Diretor (prioridade): `openclaw channels status --probe` + mensagem no bot OpenClaw.
