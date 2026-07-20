# ApiProMax — providers GPT e Claude no Vibestack

Proxy OpenAI-compatible (`https://apipromax.online/v1`).

**OpenClaw (prioridade):** bootstrap registra `apipromax-gpt` + `apipromax-claude` em `openclaw.json`. Default = GPT (`gpt-5.4-mini`), Claude opcional.

**Hermes (legado / api_server):** mesmas keys em `custom_providers`. Telegram da agência **não** usa Hermes — ver [TELEGRAM-SETUP.md](./TELEGRAM-SETUP.md).

Ollama permanece como fallback opcional, não como default.

## Variáveis (somente secrets locais / VPS)

```bash
APIPROMAX_BASE_URL=https://apipromax.online/v1
APIPROMAX_GPT_API_KEY=sk-...          # catálogo GPT
APIPROMAX_CLAUDE_API_KEY=sk-...       # catálogo Claude
APIPROMAX_DEFAULT_MODEL=gpt-5.4-mini  # default GPT (OpenClaw + Hermes)
APIPROMAX_CLAUDE_MODEL=claude-sonnet-5
OPENCLAW_DEFAULT_PROVIDER=apipromax-gpt   # ou apipromax-claude
```

Catálogo Claude conhecido (2026-07): `claude-sonnet-5`, `claude-opus-4-7`, `claude-opus-4-8`, `claude-fable-5`.

Placeholders em `.env.example`. **Nunca** commitar keys reais. Compose (`docker-compose.yml` / `easypanel.yml`) passa as vars para o container.

Onde gravar:

| Local | Arquivo |
|-------|---------|
| VPS projeto | `/opt/agenciamart-ia/vibestack-openclaw/.env` |
| Hermes (volume) | `/root/.hermes/.env` + `custom_providers` em `/root/.hermes/config.yaml` |
| Mac (espelho) | `~/.vibestack-openclaw-easypanel.env` (`chmod 600`) |

## OpenClaw providers

Após `scripts/bootstrap-agency-openclaw.sh`:

- `apipromax-gpt/<APIPROMAX_DEFAULT_MODEL>` — default
- `apipromax-claude/<APIPROMAX_CLAUDE_MODEL>` — se `APIPROMAX_CLAUDE_API_KEY` estiver set

Trocar default no runtime:

```bash
docker exec openclaw-vibestack-wa openclaw models set apipromax-claude/claude-sonnet-5
# ou re-rodar bootstrap com OPENCLAW_DEFAULT_PROVIDER=apipromax-claude
```

## Hermes `custom_providers`

Duas entradas, **mesma** `base_url`, keys diferentes:

```yaml
model:
  provider: custom:apipromax-gpt
  default: gpt-5.4-mini
  base_url: https://apipromax.online/v1

custom_providers:
  - name: apipromax-gpt
    base_url: https://apipromax.online/v1
    api_key: sk-...   # GPT
    api_mode: chat_completions
    models:
      gpt-5.4-mini: { context_length: 128000 }
  - name: apipromax-claude
    base_url: https://apipromax.online/v1
    api_key: sk-...   # Claude
    api_mode: chat_completions
    models:
      claude-sonnet-5: { context_length: 200000 }
  - name: ollama
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama
    api_mode: chat_completions
```

## Conferir catálogo

```bash
# No host com .env carregado, ou via python no container
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

curl -sS "$APIPROMAX_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $APIPROMAX_CLAUDE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-5","messages":[{"role":"user","content":"oi"}],"max_tokens":32}'

docker restart openclaw-vibestack-wa   # NÃO reinicie o Evolution
docker exec openclaw-vibestack-wa openclaw models status
```

Smoke OpenClaw Diretor (prioridade): `openclaw channels status --probe` + mensagem no `@chatmartstudios_bot`.
