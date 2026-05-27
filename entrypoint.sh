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

# Tokens da Meta CLI: o openclaw spawna o MCP child com env reduzido, entao
# repassamos ACCESS_TOKEN/AD_ACCOUNT_ID/BUSINESS_ID explicitamente. Sem isso o
# subprocesso 'meta' devolve "No access token found" / "No ad account configured".
if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "[entrypoint] AVISO: ACCESS_TOKEN vazio — meta-ads MCP vai falhar auth. Verifique META_ACCESS_TOKEN no .env."
fi

# CLI exige 'act_' no AD_ACCOUNT_ID (ex: act_123456). Adiciona se faltar.
case "${AD_ACCOUNT_ID:-}" in
  ""|act_*) ;;
  *) AD_ACCOUNT_ID="act_${AD_ACCOUNT_ID}" ;;
esac

register_mcp meta-ads "{\"command\":\"/opt/middleware-venv/bin/python\",\"args\":[\"/app/middleware/meta_ads_cli_mcp.py\"],\"env\":{\"ACCESS_TOKEN\":\"${ACCESS_TOKEN:-}\",\"AD_ACCOUNT_ID\":\"${AD_ACCOUNT_ID:-}\",\"BUSINESS_ID\":\"${BUSINESS_ID:-}\"}}"

# Acrescente novos MCP servers aqui no mesmo padrao:
# register_mcp outro-server '{"command":"...","args":[...]}'

# --- Pixel Agents Dashboard em background ---------------------------------
# Visualizer pixel-art dos agentes OpenClaw. Le JSONL em ~/.openclaw/agents/
# e fala com o gateway in-process via http://localhost:18789.
PIXEL_AGENTS_DATA=/root/.openclaw/pixel-agents
mkdir -p "$PIXEL_AGENTS_DATA/data"

# Config: copia template default no primeiro boot; depois disso, host edita.
if [ ! -f "$PIXEL_AGENTS_DATA/dashboard.config.json" ]; then
  cp /opt/pixel-agents-dashboard/dashboard.config.default.json \
     "$PIXEL_AGENTS_DATA/dashboard.config.json"
  echo "[entrypoint] dashboard.config.json criado em $PIXEL_AGENTS_DATA"
fi

# Layout dos sprites persistido no volume via symlink.
rm -rf /opt/pixel-agents-dashboard/data 2>/dev/null || true
ln -sfn "$PIXEL_AGENTS_DATA/data" /opt/pixel-agents-dashboard/data

(
  cd /opt/pixel-agents-dashboard \
  && PIXEL_AGENTS_CONFIG="$PIXEL_AGENTS_DATA/dashboard.config.json" \
     PIXEL_AGENTS_PORT="${PIXEL_AGENTS_PORT:-5070}" \
     NODE_ENV=production \
     npm start \
) >/var/log/pixel-agents.log 2>&1 &
PIXEL_PID=$!
echo "[entrypoint] pixel-agents-dashboard iniciado (pid=$PIXEL_PID, log=/var/log/pixel-agents.log)"

exec "$@"
