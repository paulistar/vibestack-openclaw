#!/bin/sh
# Entrypoint:
#  1) Sobe os backends de modelos locais INSTALADOS na imagem (Ollama e/ou LM Studio).
#  2) Registra MCP servers via `openclaw mcp set` (idempotente, valida schema).
#  3) Executa o comando principal (compose passa 'openclaw gateway ...').
set -e

# --- Backends de modelos locais (sobe o que estiver instalado) -------------
# O ./install.sh decide o que entra na imagem (build args INSTALL_OLLAMA /
# INSTALL_LMSTUDIO). Aqui apenas detectamos o que foi baixado e subimos cada um:
#   - Ollama    -> porta 11434 (comportamento de sempre).
#   - LM Studio -> daemon llmster + server OpenAI-compat na 1234.
# Portas distintas: se ambos estiverem instalados, sobem os dois sem conflito.
# Os helpers (start-ollama / start-lmstudio) sao idempotentes e tambem servem
# para (re)start manual via `docker compose exec`. Rodam em BACKGROUND para nao
# bloquear o boot do gateway — o LM Studio pode levar 1-2 min no 1o uso (extracao
# do runtime). set -e desligado em volta para que a falha de um nao derrube o boot.
set +e
if command -v ollama >/dev/null 2>&1; then start-ollama & fi
if command -v lms >/dev/null 2>&1; then start-lmstudio & fi
set -e

# HERMES_API_SERVER_KEY no .env vira API_SERVER_KEY (Hermes gateway + bridge).
if [ -z "${API_SERVER_KEY:-}" ] && [ -n "${HERMES_API_SERVER_KEY:-}" ]; then
  API_SERVER_KEY="$HERMES_API_SERVER_KEY"
  export API_SERVER_KEY
fi

# --- Bridge WhatsApp CEDO (antes dos MCPs) ---
# Critico: `openclaw mcp set` na imagem sem timeout (ou sob CPU) pode travar
# minutos/horas. Se o bridge so subir no fim do entrypoint, a Evolution recebe
# connection refused e o usuario vê silencio no WhatsApp. Subir AGORA.
start_wa_bridge() {
  WA_BRIDGE_AGENT="${WA_BRIDGE_AGENT:-hermes}"
  if [ -z "${EVOLUTION_INSTANCE_TOKEN:-}" ]; then
    echo "[entrypoint] whatsapp bridge NAO subiu (faltou EVOLUTION_INSTANCE_TOKEN) — canal inbound desligado."
    return 0
  fi
  if [ "$WA_BRIDGE_AGENT" != "openclaw" ] && [ -z "${API_SERVER_KEY:-}" ]; then
    echo "[entrypoint] whatsapp bridge NAO subiu (faltou API_SERVER_KEY no modo hermes) — canal inbound desligado."
    return 0
  fi
  (
    WA_BRIDGE_AGENT="$WA_BRIDGE_AGENT" \
    WA_BRIDGE_PORT="${WA_BRIDGE_PORT:-8765}" \
    WA_BRIDGE_UPSTREAM="${WA_BRIDGE_UPSTREAM:-http://127.0.0.1:11434}" \
    WA_BRIDGE_UPSTREAM_KEY="${API_SERVER_KEY:-ollama}" \
    WA_BRIDGE_MODEL="${WA_BRIDGE_MODEL:-llama3.2:3b}" \
    WA_BRIDGE_OPENCLAW_AGENT="${WA_BRIDGE_OPENCLAW_AGENT:-}" \
    WA_BRIDGE_ALLOWED_NUMBERS="${WA_BRIDGE_ALLOWED_NUMBERS:-}" \
    WA_BRIDGE_UPSTREAM_TIMEOUT="${WA_BRIDGE_UPSTREAM_TIMEOUT:-300}" \
    WA_BRIDGE_ACK_AFTER="${WA_BRIDGE_ACK_AFTER:-30}" \
    WA_BRIDGE_MAX_TOKENS="${WA_BRIDGE_MAX_TOKENS:-64}" \
    WA_BRIDGE_NUM_CTX="${WA_BRIDGE_NUM_CTX:-512}" \
    WA_BRIDGE_NUM_PREDICT="${WA_BRIDGE_NUM_PREDICT:-64}" \
    WA_BRIDGE_SYSTEM_PROMPT="${WA_BRIDGE_SYSTEM_PROMPT:-Responda em português, em até 2 frases curtas.}" \
    OLLAMA_NUM_CTX="${OLLAMA_NUM_CTX:-512}" \
    OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-512}" \
    WA_BRIDGE_PUBLIC_URL="${WA_BRIDGE_PUBLIC_URL:-http://openclaw-vibestack:${WA_BRIDGE_PORT:-8765}/webhook}" \
    EVOLUTION_BASE_URL="${EVOLUTION_BASE_URL:-http://evolution-go:8080}" \
    EVOLUTION_API_KEY="${EVOLUTION_API_KEY:-}" \
    EVOLUTION_INSTANCE="${EVOLUTION_INSTANCE:-vibestack}" \
    EVOLUTION_INSTANCE_TOKEN="${EVOLUTION_INSTANCE_TOKEN}" \
    EVOLUTION_PROXY_PROTOCOL="${EVOLUTION_PROXY_PROTOCOL:-http}" \
    EVOLUTION_PROXY_HOST="${EVOLUTION_PROXY_HOST:-}" \
    EVOLUTION_PROXY_PORT="${EVOLUTION_PROXY_PORT:-}" \
    EVOLUTION_PROXY_USERNAME="${EVOLUTION_PROXY_USERNAME:-}" \
    EVOLUTION_PROXY_PASSWORD="${EVOLUTION_PROXY_PASSWORD:-}" \
    EVOLUTION_IGNORE_GROUPS="${EVOLUTION_IGNORE_GROUPS:-true}" \
    EVOLUTION_IGNORE_STATUS="${EVOLUTION_IGNORE_STATUS:-true}" \
      /opt/middleware-venv/bin/python /app/middleware/whatsapp_bridge.py
  ) >/var/log/whatsapp-bridge.log 2>&1 &
  WA_BRIDGE_PID=$!
  echo "[entrypoint] whatsapp bridge iniciado CEDO em 0.0.0.0:${WA_BRIDGE_PORT:-8765} (agente=$WA_BRIDGE_AGENT, pid=$WA_BRIDGE_PID, log=/var/log/whatsapp-bridge.log)"
}
start_wa_bridge

# Diretorio persistente de assets dos agentes (dentro do volume /root/.openclaw).
# Midia gerada/baixada (ex.: pelo higgsfield MCP) vai pra ca' e sobrevive a restart.
# Qualquer escrita fora de /root/.openclaw (/tmp, /app, cwd) e' efemera.
mkdir -p /root/.openclaw/workspace/_shared/assets /root/.openclaw/workspace/_shared/creatives /root/.openclaw/workspace/clients 2>/dev/null || true

# --- Hermes Agent CEDO (antes dos openclaw mcp set) -----------------------
# Critico: sob CPU saturada, `openclaw mcp set` pode levar minutos. Hermes
# api_server/dashboard sobe agora; MCP OpenClaw depois.
# Hermes roda ao lado do OpenClaw: api_server OpenAI-compatible na 8642,
# usando os MESMOS middlewares MCP (meta-ads, media-editor). O provider/modelo
# NAO e' configurado aqui de proposito — o usuario edita config.yaml depois
# (persistido no volume), igual faz com o openclaw.json.
#
# Telegram: prioridade = OpenClaw nativo → agente diretor. O compose ainda
# passa TELEGRAM_* no env do container (OpenClaw le). Hermes NAO deve
# long-poll o mesmo bot — zeramos o volume .env e unset no subprocesso.
HERMES_HOME="${HOME:-/root}/.hermes"
mkdir -p "$HERMES_HOME"

# P1.4 — desliga Telegram residual no volume Hermes (idempotente a cada boot).
if [ "${HERMES_DISABLE_TELEGRAM:-1}" != "0" ]; then
  HERMES_ENV_FILE="$HERMES_HOME/.env"
  if [ -f "$HERMES_ENV_FILE" ]; then
    tmp_h="$(mktemp)"
    grep -vE '^TELEGRAM_(BOT_TOKEN|ALLOWED_USERS|HOME_CHANNEL|HOME_CHANNEL_NAME)=' \
      "$HERMES_ENV_FILE" >"$tmp_h" 2>/dev/null || true
    {
      echo '# Telegram movido para OpenClaw (diretor). Hermes sem poll.'
      echo 'TELEGRAM_BOT_TOKEN='
      echo 'TELEGRAM_ALLOWED_USERS='
    } >>"$tmp_h"
    mv "$tmp_h" "$HERMES_ENV_FILE"
    chmod 600 "$HERMES_ENV_FILE" 2>/dev/null || true
    echo "[entrypoint] Hermes TELEGRAM_* zerado em $HERMES_ENV_FILE (OpenClaw Diretor e' o canal TG)"
  fi
fi

# Registro MCP: faz um merge idempotente em config.yaml, gravando so as
# entradas mcp_servers e preservando qualquer outra chave (model, provider,
# skills...) que o usuario tenha editado. Sem campo 'tools'/'enabled' o Hermes
# habilita todas as tools do server (tools/mcp_tool.py: default enabled=True,
# filtro de tools vazio). Reusa os scripts e o venv do middleware do OpenClaw.
HERMES_HOME="$HERMES_HOME" \
ACCESS_TOKEN="${ACCESS_TOKEN:-}" \
AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-}" \
BUSINESS_ID="${BUSINESS_ID:-}" \
GOOGLE_ADS_DEVELOPER_TOKEN="${GOOGLE_ADS_DEVELOPER_TOKEN:-}" \
GOOGLE_ADS_CLIENT_ID="${GOOGLE_ADS_CLIENT_ID:-}" \
GOOGLE_ADS_CLIENT_SECRET="${GOOGLE_ADS_CLIENT_SECRET:-}" \
GOOGLE_ADS_REFRESH_TOKEN="${GOOGLE_ADS_REFRESH_TOKEN:-}" \
GOOGLE_ADS_LOGIN_CUSTOMER_ID="${GOOGLE_ADS_LOGIN_CUSTOMER_ID:-}" \
GOOGLE_ADS_CUSTOMER_ID="${GOOGLE_ADS_CUSTOMER_ID:-}" \
ATLASCLOUD_API_KEY="${ATLASCLOUD_API_KEY:-}" \
B2_KEY_ID="${B2_KEY_ID:-}" \
B2_APP_KEY="${B2_APP_KEY:-}" \
B2_BUCKET="${B2_BUCKET:-}" \
B2_ENDPOINT_URL="${B2_ENDPOINT_URL:-}" \
EVOLUTION_BASE_URL="${EVOLUTION_BASE_URL:-http://evolution-go:8080}" \
EVOLUTION_API_KEY="${EVOLUTION_API_KEY:-}" \
EVOLUTION_INSTANCE_TOKEN="${EVOLUTION_INSTANCE_TOKEN:-}" \
EVOLUTION_INSTANCE="${EVOLUTION_INSTANCE:-vibestack}" \
WEB_SEARCH_PROVIDER="${WEB_SEARCH_PROVIDER:-auto}" \
EXA_API_KEY="${EXA_API_KEY:-}" \
TAVILY_API_KEY="${TAVILY_API_KEY:-}" \
BRAVE_SEARCH_API_KEY="${BRAVE_SEARCH_API_KEY:-}" \
WEB_FETCH_TIMEOUT_SEC="${WEB_FETCH_TIMEOUT_SEC:-20}" \
WEB_FETCH_MAX_BYTES="${WEB_FETCH_MAX_BYTES:-500000}" \
WEB_FETCH_MAX_REDIRECTS="${WEB_FETCH_MAX_REDIRECTS:-5}" \
WEB_SEARCH_MAX_RESULTS="${WEB_SEARCH_MAX_RESULTS:-8}" \
WEB_URL_ALLOWLIST="${WEB_URL_ALLOWLIST:-}" \
WEB_URL_DENYLIST="${WEB_URL_DENYLIST:-}" \
WEB_USER_AGENT="${WEB_USER_AGENT:-}" \
HERMES_APPROVALS_MODE="${HERMES_APPROVALS_MODE:-off}" \
/opt/hermes-agent/venv/bin/python - <<'PYEOF'
import os, sys
from pathlib import Path

try:
    import yaml
except Exception as e:  # noqa: BLE001
    print(f"[entrypoint] AVISO: PyYAML indisponivel no venv do Hermes ({e}) — pulei registro MCP")
    sys.exit(0)

home = Path(os.environ.get("HERMES_HOME", "/root/.hermes"))
cfg_path = home / "config.yaml"

cfg = {}
if cfg_path.exists():
    try:
        cfg = yaml.safe_load(cfg_path.read_text()) or {}
    except Exception as e:  # noqa: BLE001
        print(f"[entrypoint] AVISO: config.yaml do Hermes ilegivel ({e}) — preservando arquivo, abortando merge")
        sys.exit(0)
if not isinstance(cfg, dict):
    cfg = {}

PY = "/opt/middleware-venv/bin/python"
servers = cfg.setdefault("mcp_servers", {})
if not isinstance(servers, dict):
    servers = {}
    cfg["mcp_servers"] = servers

servers["meta-ads"] = {
    "command": PY,
    "args": ["/app/middleware/meta_ads_cli_mcp.py"],
    "env": {
        "ACCESS_TOKEN": os.environ.get("ACCESS_TOKEN", ""),
        "AD_ACCOUNT_ID": os.environ.get("AD_ACCOUNT_ID", ""),
        "BUSINESS_ID": os.environ.get("BUSINESS_ID", ""),
    },
}
servers["google-ads"] = {
    "command": PY,
    "args": ["/app/middleware/google_ads_cli_mcp.py"],
    "env": {
        "GOOGLE_ADS_DEVELOPER_TOKEN": os.environ.get("GOOGLE_ADS_DEVELOPER_TOKEN", ""),
        "GOOGLE_ADS_CLIENT_ID": os.environ.get("GOOGLE_ADS_CLIENT_ID", ""),
        "GOOGLE_ADS_CLIENT_SECRET": os.environ.get("GOOGLE_ADS_CLIENT_SECRET", ""),
        "GOOGLE_ADS_REFRESH_TOKEN": os.environ.get("GOOGLE_ADS_REFRESH_TOKEN", ""),
        "GOOGLE_ADS_LOGIN_CUSTOMER_ID": os.environ.get("GOOGLE_ADS_LOGIN_CUSTOMER_ID", ""),
        "GOOGLE_ADS_CUSTOMER_ID": os.environ.get("GOOGLE_ADS_CUSTOMER_ID", ""),
        "GOOGLE_ADS_USE_PROTO_PLUS": "True",
    },
}
servers["media-editor"] = {
    "command": PY,
    "args": ["/app/middleware/media_editor_mcp.py"],
    "env": {
        "B2_KEY_ID": os.environ.get("B2_KEY_ID", ""),
        "B2_APP_KEY": os.environ.get("B2_APP_KEY", ""),
        "B2_BUCKET": os.environ.get("B2_BUCKET", ""),
        "B2_ENDPOINT_URL": os.environ.get("B2_ENDPOINT_URL", ""),
    },
}
servers["whatsapp"] = {
    "command": PY,
    "args": ["/app/middleware/whatsapp_evolution_mcp.py"],
    "env": {
        "EVOLUTION_BASE_URL": os.environ.get("EVOLUTION_BASE_URL", "http://evolution-go:8080"),
        "EVOLUTION_API_KEY": os.environ.get("EVOLUTION_API_KEY", ""),
        "EVOLUTION_INSTANCE_TOKEN": os.environ.get("EVOLUTION_INSTANCE_TOKEN", ""),
        "EVOLUTION_INSTANCE": os.environ.get("EVOLUTION_INSTANCE", "vibestack"),
    },
}
servers["higgsfield"] = {
    "command": PY,
    "args": ["/app/middleware/higgsfield_cli_mcp.py"],
    # CLI le o token de ~/.higgsfield -> HOME explicito (env reduzido no spawn).
    "env": {"HOME": "/root"},
}
servers["atlascloud"] = {
    # MCP oficial da AtlasCloud, instalado global na imagem. Auth so' por env.
    "command": "/usr/local/bin/atlascloud-mcp",
    "args": [],
    "env": {"ATLASCLOUD_API_KEY": os.environ.get("ATLASCLOUD_API_KEY", "")},
}
servers["web-research"] = {
    "command": PY,
    "args": ["/app/middleware/web_research_mcp.py"],
    "env": {
        "WEB_SEARCH_PROVIDER": os.environ.get("WEB_SEARCH_PROVIDER", "auto"),
        "EXA_API_KEY": os.environ.get("EXA_API_KEY", ""),
        "TAVILY_API_KEY": os.environ.get("TAVILY_API_KEY", ""),
        "BRAVE_SEARCH_API_KEY": os.environ.get("BRAVE_SEARCH_API_KEY", ""),
        "WEB_FETCH_TIMEOUT_SEC": os.environ.get("WEB_FETCH_TIMEOUT_SEC", "20"),
        "WEB_FETCH_MAX_BYTES": os.environ.get("WEB_FETCH_MAX_BYTES", "500000"),
        "WEB_FETCH_MAX_REDIRECTS": os.environ.get("WEB_FETCH_MAX_REDIRECTS", "5"),
        "WEB_SEARCH_MAX_RESULTS": os.environ.get("WEB_SEARCH_MAX_RESULTS", "8"),
        "WEB_URL_ALLOWLIST": os.environ.get("WEB_URL_ALLOWLIST", ""),
        "WEB_URL_DENYLIST": os.environ.get("WEB_URL_DENYLIST", ""),
        "WEB_USER_AGENT": os.environ.get("WEB_USER_AGENT", ""),
    },
}

# Aprovacao de comandos: num canal headless (api_server/WhatsApp) NAO ha quem
# responda o prompt de aprovacao -> o agente TRAVA ate o timeout do bridge.
# Definimos approvals.mode (default 'off') pra auto-aprovar. So' grava se a chave
# ainda nao existe, preservando uma escolha do usuario.
approvals = cfg.get("approvals")
if not isinstance(approvals, dict):
    approvals = {}
    cfg["approvals"] = approvals
approvals.setdefault("mode", os.environ.get("HERMES_APPROVALS_MODE", "off"))

# Ollama CPU: Hermes exige model.context_length >= 64k (validacao interna).
# O num_ctx REAL do Ollama continua em OLLAMA_NUM_CTX/OLLAMA_CONTEXT_LENGTH (512).
# Nao escrever 512 em model.context_length — quebra o agente com ValueError.
try:
    # claim alto so' pra passar o gate do Hermes; inferencia real e' curta via Ollama env
    hermes_ctx = 65536
except Exception:
    hermes_ctx = 65536
model = cfg.setdefault("model", {})
if isinstance(model, dict):
    # so' seta se ausente/baixo demais; nao forcar baixo
    cur = model.get("context_length")
    try:
        cur_i = int(cur) if cur is not None else 0
    except (TypeError, ValueError):
        cur_i = 0
    if cur_i < 64000:
        model["context_length"] = hermes_ctx
    model.setdefault("max_tokens", 64)
agent = cfg.setdefault("agent", {})
if isinstance(agent, dict):
    agent.setdefault("max_turns", 6)
    agent.setdefault("gateway_timeout", 120)
    agent.setdefault("api_max_retries", 1)
aux = cfg.setdefault("auxiliary", {})
if isinstance(aux, dict):
    title = aux.setdefault("title_generation", {})
    if isinstance(title, dict):
        title.setdefault("enabled", False)
display = cfg.setdefault("display", {})
if isinstance(display, dict):
    display.setdefault("reasoning", False)
# limpa cache de auto-detect inconsistente
cache = home / "context_length_cache.yaml"
try:
    cache.write_text("{}\n")
except OSError:
    pass

tmp = cfg_path.with_suffix(".yaml.tmp")
tmp.write_text(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))
tmp.replace(cfg_path)
try:
    cfg_path.chmod(0o600)
except OSError:
    pass
print(f"[entrypoint] hermes mcp 'meta-ads', 'google-ads', 'media-editor', 'whatsapp' e 'web-research' registrados em {cfg_path}")
PYEOF

# Sobe o gateway do Hermes em background. A unica plataforma que sobe sem
# token e' o api_server (is_configured=True), e ele EXIGE API_SERVER_KEY pra
# iniciar. Bind interno 0.0.0.0 (Docker publica em loopback no host); a auth
# e' garantida pela API_SERVER_KEY, entao nao precisa de socat (ao contrario do dashboard).
#
# IMPORTANTE: usar 'hermes gateway RUN' (foreground, recomendado p/ Docker) — NAO
# 'hermes gateway' sozinho nem 'start' (que e' pra servico systemd/launchd e se
# recusa dentro de container). O 'run' e' quem roda o loop do gateway COM o
# dispatcher embutido do Kanban (tick de 60s). Sem ele, as tasks ficam presas em
# 'ready' e o 'hermes gateway status' reporta "not running".
#
# Como aqui o processo PRINCIPAL do container e' o OpenClaw (nao o Hermes), o
# gateway do Hermes nao tem supervisor: se cair, ninguem reergue. Por isso o
# envolvemos num laco de AUTO-RESTART (reinicia em 5s se sair). HERMES_ACCEPT_HOOKS=1
# evita travar num prompt de hook sem TTY (canal headless, igual approvals=off).
if [ -z "${API_SERVER_KEY:-}" ]; then
  echo "[entrypoint] AVISO: API_SERVER_KEY vazio — Hermes api_server NAO vai subir. Defina HERMES_API_SERVER_KEY no .env."
else
  # -p default: FIXA o gateway no profile 'default'. Sem isso, o gateway sobe sob
  # o profile ATIVO no boot — e se alguem deu 'hermes profile use <cargo>' antes de
  # reiniciar, o gateway (e o api_server 8642) subiria sob o profile errado, e
  # 'hermes gateway status' (no profile default) acusaria "not running". O board do
  # Kanban e' compartilhado (/root/.hermes/kanban.db), entao um unico gateway default
  # ja' despacha tasks de QUALQUER assignee (spawna o profile de cada task).
  HERMES_GATEWAY_PROFILE="${HERMES_GATEWAY_PROFILE:-default}"
  # Telegram e' do OpenClaw Diretor. O compose ainda injeta TELEGRAM_* no
  # container (OpenClaw precisa), mas o processo Hermes NAO deve herdar —
  # evita double-poll no mesmo botToken. Volume /root/.hermes/.env tambem
  # fica com TELEGRAM_*= vazio (bootstrap-agency).
  (
    while true; do
      env -u TELEGRAM_BOT_TOKEN -u TELEGRAM_ALLOWED_USERS \
        -u TELEGRAM_HOME_CHANNEL -u TELEGRAM_HOME_CHANNEL_NAME \
        -u TELEGRAM_WEBHOOK_URL \
      HERMES_HOME="$HERMES_HOME" \
      API_SERVER_HOST=0.0.0.0 \
      API_SERVER_PORT="${HERMES_API_PORT:-8642}" \
      HERMES_ACCEPT_HOOKS=1 \
        hermes -p "$HERMES_GATEWAY_PROFILE" gateway run
      echo "[entrypoint] AVISO: 'hermes gateway run' (profile=$HERMES_GATEWAY_PROFILE) saiu (code $?) — reiniciando em 5s"
      sleep 5
    done
  ) >/var/log/hermes.log 2>&1 &
  HERMES_PID=$!
  echo "[entrypoint] hermes gateway run (auto-restart) iniciado em 0.0.0.0:${HERMES_API_PORT:-8642} (pid=$HERMES_PID, log=/var/log/hermes.log)"
  echo "[entrypoint] Hermes: TELEGRAM_* unset no processo (poll so OpenClaw Diretor)."
  echo "[entrypoint] LEMBRE: configure o provider/modelo do Hermes (docker exec -it <cont> hermes model) — o build nao baka provider."
fi

# Dashboard web do Hermes (Vite/React) — a "pagina web" de gestao/chat.
# IMPORTANTE: bind em 127.0.0.1 (loopback) dentro do container, NAO 0.0.0.0.
# O dashboard tem defesas de DNS-rebinding/Origin/Host no WebSocket que ficam
# rigidas em bind nao-loopback: com 0.0.0.0 a pagina HTTP carrega mas o WS da
# aba Chat e' rejeitado ("WebSocket connection failed"). Em loopback o servidor
# trata a conexao como local/confiavel e o WS passa (a pagina usa o token
# embutido — sem precisar de --insecure). Publicamos via socat (TCP-puro, o
# WebSocket passa transparente).
#
# --tui: habilita a aba "Chat" embutida (PTY que spawna `hermes --tui`); sem ela
# o dashboard so' mostra config/sessoes. O ui-tui ja' vem pre-buildado na imagem.
HERMES_WEB_PUBLIC_PORT="${HERMES_WEB_PORT:-9119}"
HERMES_WEB_INTERNAL_PORT="${HERMES_WEB_INTERNAL_PORT:-9120}"
(
  HERMES_HOME="$HERMES_HOME" \
    hermes dashboard --host 127.0.0.1 --port "$HERMES_WEB_INTERNAL_PORT" --no-open --tui
) >/var/log/hermes-web.log 2>&1 &
HERMES_WEB_PID=$!
echo "[entrypoint] hermes dashboard iniciado em 127.0.0.1:$HERMES_WEB_INTERNAL_PORT (pid=$HERMES_WEB_PID, chat-tab=on, log=/var/log/hermes-web.log)"

socat \
  TCP-LISTEN:"$HERMES_WEB_PUBLIC_PORT",fork,reuseaddr \
  TCP:127.0.0.1:"$HERMES_WEB_INTERNAL_PORT" \
  >/var/log/hermes-web-socat.log 2>&1 &
HERMES_WEB_SOCAT_PID=$!
echo "[entrypoint] socat bridge 0.0.0.0:$HERMES_WEB_PUBLIC_PORT -> 127.0.0.1:$HERMES_WEB_INTERNAL_PORT (pid=$HERMES_WEB_SOCAT_PID)"

# Bridge WhatsApp e Hermes ja' subiram CEDO — ver start_wa_bridge / Hermes acima.

# --- Registro de MCP servers OpenClaw (depois do Hermes/Telegram) ---------
# Usa 'openclaw mcp set' que valida schema e grava em mcp.servers.{nome}.
# Idempotente — pode rodar a cada boot. Se openclaw.json nao existir, o
# wizard de configuracao do openclaw precisa rodar antes (uma vez por VPS).
# Roda DEPOIS do Hermes para nao atrasar Telegram sob CPU saturada.
#
# Critico: montar o JSON via Python (json.dumps), NUNCA por interpolacao shell.
# Tokens longos / caracteres especiais quebram o JSON embutido em aspas e o
# `openclaw mcp set` pode gravar ACCESS_TOKEN="" mesmo com env do container OK.
# Volume openclaw-data sobrevive a recreate — um registro vazio antigo fica
# "preso" se o set falhar/timeout sem sobrescrever.
register_mcp() {
  name="$1"
  json="$2"
  # timeout: sob CPU saturada (ex.: Ollama CPU) o `openclaw mcp set` pode travar
  # e impedir o gateway OpenClaw de subir. Prefira falhar o MCP a bloquear o boot.
  if timeout 90 openclaw mcp set "$name" "$json" >/dev/null 2>&1; then
    echo "[entrypoint] mcp '$name' registrado"
  else
    echo "[entrypoint] AVISO: falha/timeout ao registrar mcp '$name' (openclaw.json ausente ou host sobrecarregado)"
  fi
}

# Tokens da Meta CLI: o openclaw spawna o MCP child com env reduzido, entao
# repassamos ACCESS_TOKEN/AD_ACCOUNT_ID/BUSINESS_ID explicitamente. Sem isso o
# subprocesso 'meta' devolve "No access token found" / "No ad account configured".
if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "[entrypoint] AVISO: ACCESS_TOKEN vazio — meta-ads MCP vai falhar auth. Verifique META_ACCESS_TOKEN no .env."
fi

# CLI exige 'act_' no AD_ACCOUNT_ID (ex: act_123456). Adiciona se faltar.
# AD_ACCOUNT_ID vazio e' OK (list_ad_accounts / list_businesses nao dependem dele).
case "${AD_ACCOUNT_ID:-}" in
  ""|act_*) ;;
  *) AD_ACCOUNT_ID="act_${AD_ACCOUNT_ID}" ;;
esac

META_MCP_JSON="$(ACCESS_TOKEN="${ACCESS_TOKEN:-}" AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-}" BUSINESS_ID="${BUSINESS_ID:-}" python3 - <<'PY'
import json, os
print(json.dumps({
    "command": "/opt/middleware-venv/bin/python",
    "args": ["/app/middleware/meta_ads_cli_mcp.py"],
    "env": {
        "ACCESS_TOKEN": os.environ.get("ACCESS_TOKEN", ""),
        "AD_ACCOUNT_ID": os.environ.get("AD_ACCOUNT_ID", ""),
        "BUSINESS_ID": os.environ.get("BUSINESS_ID", ""),
    },
}, ensure_ascii=False))
PY
)"
register_mcp meta-ads "$META_MCP_JSON"
# Verifica se o token chegou no openclaw.json (volume pode ter ficado com stub vazio).
python3 - <<'PY'
import json, os
from pathlib import Path
p = Path("/root/.openclaw/openclaw.json")
want = len(os.environ.get("ACCESS_TOKEN", "") or "")
if not p.exists():
    raise SystemExit(0)
try:
    d = json.loads(p.read_text())
    got = len((((d.get("mcp") or {}).get("servers") or {}).get("meta-ads") or {}).get("env", {}).get("ACCESS_TOKEN") or "")
except Exception as e:  # noqa: BLE001
    print(f"[entrypoint] AVISO: nao consegui ler openclaw.json pos meta-ads ({e})")
    raise SystemExit(0)
if want and got != want:
    print(f"[entrypoint] AVISO: meta-ads ACCESS_TOKEN no openclaw.json len={got} (container len={want}) — MCP child sem auth")
elif want:
    print(f"[entrypoint] meta-ads ACCESS_TOKEN ok (len={got})")
elif not want:
    print("[entrypoint] meta-ads ACCESS_TOKEN ausente no container")
PY

# Google Ads: MCP sobre o SDK oficial (google-ads). Auth OAuth2 lida pelo
# load_from_env() -> repassamos as GOOGLE_ADS_* explicitamente (env reduzido no
# spawn do child). Sem refresh_token as tools devolvem erro (nao derruba o boot).
if [ -z "${GOOGLE_ADS_DEVELOPER_TOKEN:-}" ] || [ -z "${GOOGLE_ADS_REFRESH_TOKEN:-}" ]; then
  echo "[entrypoint] AVISO: GOOGLE_ADS_DEVELOPER_TOKEN/REFRESH_TOKEN vazio — google-ads MCP vai falhar auth. Rode 'googleads auth' e preencha o .env."
fi
GOOGLE_MCP_JSON="$(python3 - <<'PY'
import json, os
print(json.dumps({
    "command": "/opt/middleware-venv/bin/python",
    "args": ["/app/middleware/google_ads_cli_mcp.py"],
    "env": {
        "GOOGLE_ADS_DEVELOPER_TOKEN": os.environ.get("GOOGLE_ADS_DEVELOPER_TOKEN", ""),
        "GOOGLE_ADS_CLIENT_ID": os.environ.get("GOOGLE_ADS_CLIENT_ID", ""),
        "GOOGLE_ADS_CLIENT_SECRET": os.environ.get("GOOGLE_ADS_CLIENT_SECRET", ""),
        "GOOGLE_ADS_REFRESH_TOKEN": os.environ.get("GOOGLE_ADS_REFRESH_TOKEN", ""),
        "GOOGLE_ADS_LOGIN_CUSTOMER_ID": os.environ.get("GOOGLE_ADS_LOGIN_CUSTOMER_ID", ""),
        "GOOGLE_ADS_CUSTOMER_ID": os.environ.get("GOOGLE_ADS_CUSTOMER_ID", ""),
        "GOOGLE_ADS_USE_PROTO_PLUS": "True",
    },
}, ensure_ascii=False))
PY
)"
register_mcp google-ads "$GOOGLE_MCP_JSON"

# media-editor: ffmpeg envelopado em tools + Backblaze B2 (S3-compatible) como
# storage canonico de seeds e derivacoes. Consumido pelo agente Criativo.
if [ -z "${B2_BUCKET:-}" ] || [ -z "${B2_KEY_ID:-}" ] || [ -z "${B2_APP_KEY:-}" ]; then
  echo "[entrypoint] AVISO: B2_BUCKET/B2_KEY_ID/B2_APP_KEY vazios — media-editor MCP vai recusar operacoes. Configure no .env."
fi
MEDIA_MCP_JSON="$(python3 - <<'PY'
import json, os
print(json.dumps({
    "command": "/opt/middleware-venv/bin/python",
    "args": ["/app/middleware/media_editor_mcp.py"],
    "env": {
        "B2_KEY_ID": os.environ.get("B2_KEY_ID", ""),
        "B2_APP_KEY": os.environ.get("B2_APP_KEY", ""),
        "B2_BUCKET": os.environ.get("B2_BUCKET", ""),
        "B2_ENDPOINT_URL": os.environ.get("B2_ENDPOINT_URL", ""),
    },
}, ensure_ascii=False))
PY
)"
register_mcp media-editor "$MEDIA_MCP_JSON"

# whatsapp: envia mensagens via Evolution Go (whatsmeow), que roda como servico
# separado no compose. O middleware alcanca a API em http://evolution-go:8080
# (DNS de servico do compose). EVOLUTION_API_KEY = global (admin/create);
# EVOLUTION_INSTANCE_TOKEN = token da instancia (send/qr/status).
if [ -z "${EVOLUTION_API_KEY:-}" ]; then
  echo "[entrypoint] AVISO: EVOLUTION_API_KEY vazio — whatsapp MCP vai falhar. Configure no .env."
fi
WA_MCP_JSON="$(python3 - <<'PY'
import json, os
print(json.dumps({
    "command": "/opt/middleware-venv/bin/python",
    "args": ["/app/middleware/whatsapp_evolution_mcp.py"],
    "env": {
        "EVOLUTION_BASE_URL": os.environ.get("EVOLUTION_BASE_URL", "http://evolution-go:8080"),
        "EVOLUTION_API_KEY": os.environ.get("EVOLUTION_API_KEY", ""),
        "EVOLUTION_INSTANCE_TOKEN": os.environ.get("EVOLUTION_INSTANCE_TOKEN", ""),
        "EVOLUTION_INSTANCE": os.environ.get("EVOLUTION_INSTANCE", "vibestack"),
    },
}, ensure_ascii=False))
PY
)"
register_mcp whatsapp "$WA_MCP_JSON"

# higgsfield: envelopa o CLI 'higgsfield' (geracao de imagem/video, soul-id) como
# tools tipados. O CLI le o token de ~/.higgsfield -> passamos HOME=/root explicito
# porque o openclaw spawna o MCP child com env reduzido. Auth: o aluno roda uma vez
# `docker exec -it <cont> higgsfield auth login` (OAuth no navegador); o token fica
# no volume /root/.higgsfield e sobrevive a restart/rebuild.
HIGGS_MCP_JSON="$(python3 - <<'PY'
import json
print(json.dumps({
    "command": "/opt/middleware-venv/bin/python",
    "args": ["/app/middleware/higgsfield_cli_mcp.py"],
    "env": {"HOME": "/root"},
}, ensure_ascii=False))
PY
)"
register_mcp higgsfield "$HIGGS_MCP_JSON"

# atlascloud: MCP server OFICIAL da AtlasCloud (hub de 300+ modelos img/video/LLM).
# Instalado global na imagem (bin /usr/local/bin/atlascloud-mcp). Auth so' por env
# ATLASCLOUD_API_KEY — repassada explicitamente porque o openclaw spawna o child
# com env reduzido. Sem login nem volume: a chave no .env ja' sobrevive a restart.
if [ -z "${ATLASCLOUD_API_KEY:-}" ]; then
  echo "[entrypoint] AVISO: ATLASCLOUD_API_KEY vazio — atlascloud MCP vai falhar auth. Configure no .env."
fi
ATLAS_MCP_JSON="$(python3 - <<'PY'
import json, os
print(json.dumps({
    "command": "/usr/local/bin/atlascloud-mcp",
    "args": [],
    "env": {"ATLASCLOUD_API_KEY": os.environ.get("ATLASCLOUD_API_KEY", "")},
}, ensure_ascii=False))
PY
)"
register_mcp atlascloud "$ATLAS_MCP_JSON"

# web-research: search + fetch HTTP (infra transversal — nao e' feature de ads).
# Keys opcionais (Exa/Tavily/Brave); sem key usa DuckDuckGo HTML como fallback.
# SSRF + allowlist/denylist via env. Docs: docs/WEB-RESEARCH.md
WEB_MCP_JSON="$(python3 - <<'PY'
import json, os
print(json.dumps({
    "command": "/opt/middleware-venv/bin/python",
    "args": ["/app/middleware/web_research_mcp.py"],
    "env": {
        "WEB_SEARCH_PROVIDER": os.environ.get("WEB_SEARCH_PROVIDER", "auto"),
        "EXA_API_KEY": os.environ.get("EXA_API_KEY", ""),
        "TAVILY_API_KEY": os.environ.get("TAVILY_API_KEY", ""),
        "BRAVE_SEARCH_API_KEY": os.environ.get("BRAVE_SEARCH_API_KEY", ""),
        "WEB_FETCH_TIMEOUT_SEC": os.environ.get("WEB_FETCH_TIMEOUT_SEC", "20"),
        "WEB_FETCH_MAX_BYTES": os.environ.get("WEB_FETCH_MAX_BYTES", "500000"),
        "WEB_FETCH_MAX_REDIRECTS": os.environ.get("WEB_FETCH_MAX_REDIRECTS", "5"),
        "WEB_SEARCH_MAX_RESULTS": os.environ.get("WEB_SEARCH_MAX_RESULTS", "8"),
        "WEB_URL_ALLOWLIST": os.environ.get("WEB_URL_ALLOWLIST", ""),
        "WEB_URL_DENYLIST": os.environ.get("WEB_URL_DENYLIST", ""),
        "WEB_USER_AGENT": os.environ.get("WEB_USER_AGENT", ""),
    },
}, ensure_ascii=False))
PY
)"
register_mcp web-research "$WEB_MCP_JSON"
# Confirma que o server entrou no openclaw.json (nao precisa de key pra subir).
# Nega tools nativas web_* do OpenClaw — a agencia usa MCP web-research__* (SSRF + DDG).
python3 - <<'PY'
import json
from pathlib import Path
p = Path("/root/.openclaw/openclaw.json")
if not p.exists():
    raise SystemExit(0)
try:
    d = json.loads(p.read_text())
    srv = (((d.get("mcp") or {}).get("servers") or {}).get("web-research") or {})
    args = srv.get("args") or []
    if "/app/middleware/web_research_mcp.py" in args:
        print("[entrypoint] web-research mcp ok (script no openclaw.json)")
    else:
        print("[entrypoint] AVISO: web-research ausente ou args inesperados no openclaw.json")
    tools = d.setdefault("tools", {})
    if not isinstance(tools, dict):
        tools = {}
        d["tools"] = tools
    deny = tools.get("deny")
    if not isinstance(deny, list):
        deny = []
    changed = False
    for name in ("web_search", "web_fetch"):
        if name not in deny:
            deny.append(name)
            changed = True
    if changed or tools.get("deny") != deny:
        tools["deny"] = deny
        p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
        print("[entrypoint] tools.deny inclui web_search/web_fetch nativos (use web-research__*)")
    else:
        print("[entrypoint] tools.deny web_search/web_fetch ja configurado")
except Exception as e:  # noqa: BLE001
    print(f"[entrypoint] AVISO: nao consegui ler/patch openclaw.json pos web-research ({e})")
PY

# Acrescente novos MCP servers aqui no mesmo padrao (JSON via python3 json.dumps):
# register_mcp outro-server "$(python3 - <<'PY'
# import json; print(json.dumps({...}))
# PY
# )"

exec "$@"
