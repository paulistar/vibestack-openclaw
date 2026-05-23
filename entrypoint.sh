#!/bin/sh
# Entrypoint:
#  1) Sobe ollama serve em background.
#  2) Registra MCP servers via `openclaw mcp set` (idempotente, valida schema).
#  3) Executa o comando principal (compose passa 'openclaw gateway ...').
set -e

# --- Ollama em background --------------------------------------------------
ollama serve >/var/log/ollama.log 2>&1 &
OLLAMA_PID=$!

for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "[entrypoint] ollama pronto (pid=$OLLAMA_PID)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[entrypoint] AVISO: ollama nao respondeu em 30s — seguindo mesmo assim"
  fi
  sleep 1
done

# --- Registro de MCP servers (Infrastructure as Code via CLI) -------------
# Usa 'openclaw mcp set' que valida schema e grava em mcp.servers.{nome}.
# Idempotente — pode rodar a cada boot. Se openclaw.json nao existir, o
# wizard de configuracao do openclaw precisa rodar antes (uma vez por VPS).
register_mcp() {
  name="$1"
  json="$2"
  if openclaw mcp set "$name" "$json" >/dev/null 2>&1; then
    echo "[entrypoint] mcp '$name' registrado"
  else
    echo "[entrypoint] AVISO: falha ao registrar mcp '$name' (openclaw.json ausente? rode 'openclaw configure' uma vez)"
  fi
}

register_mcp meta-ads '{"command":"/opt/middleware-venv/bin/python","args":["/app/middleware/meta_ads_cli_mcp.py"]}'

# Acrescente novos MCP servers aqui no mesmo padrao:
# register_mcp outro-server '{"command":"...","args":[...]}'

exec "$@"
