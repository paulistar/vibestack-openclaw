#!/usr/bin/env bash
# Bootstrap Passo 13 — agentes da agência no OpenClaw (idempotente).
# Roda DENTRO do container openclaw-vibestack-wa (ou via: docker exec ... bash /path).
#
# Pré-requisitos:
#   - openclaw.json já existe (gateway já subiu ao menos 1x)
#   - pasta agency/ acessível (AGENCY_SRC)
#   - APIPROMAX_* no ambiente (modelo default; NÃO depende de Ollama)
#
# Uso:
#   AGENCY_SRC=/opt/.../agency bash scripts/bootstrap-agency-openclaw.sh
#   # ou:
#   docker exec -e APIPROMAX_GPT_API_KEY -e APIPROMAX_CLAUDE_API_KEY \
#     -e APIPROMAX_BASE_URL -e APIPROMAX_DEFAULT_MODEL \
#     -e TELEGRAM_BOT_TOKEN -e TELEGRAM_ALLOWED_USERS \
#     openclaw-vibestack-wa bash /app/scripts/bootstrap-agency-openclaw.sh
set -euo pipefail

AGENCY_SRC="${AGENCY_SRC:-/opt/agenciamart-ia/vibestack-openclaw/agency}"
CLIENTS_SRC="${CLIENTS_SRC:-/opt/agenciamart-ia/vibestack-openclaw/clients}"
OPENCLAW_HOME="${OPENCLAW_HOME:-/root/.openclaw}"
WS_ROOT="${OPENCLAW_HOME}/workspace"
BASE_URL="${APIPROMAX_BASE_URL:-https://apipromax.online/v1}"
API_KEY="${APIPROMAX_GPT_API_KEY:-}"
CLAUDE_KEY="${APIPROMAX_CLAUDE_API_KEY:-}"
CLAUDE_MODEL_ID="${APIPROMAX_CLAUDE_MODEL:-claude-sonnet-5}"
# Default provider: apipromax-gpt | apipromax-claude
DEFAULT_PROVIDER="${OPENCLAW_DEFAULT_PROVIDER:-apipromax-gpt}"
if [[ "$DEFAULT_PROVIDER" == "apipromax-claude" ]]; then
  MODEL_ID="${APIPROMAX_CLAUDE_MODEL:-claude-sonnet-5}"
  PROVIDER_ID="apipromax-claude"
else
  MODEL_ID="${APIPROMAX_DEFAULT_MODEL:-gpt-5.4-mini}"
  PROVIDER_ID="apipromax-gpt"
fi
MODEL_REF="${PROVIDER_ID}/${MODEL_ID}"
TELEGRAM_OWNER="${TELEGRAM_ALLOWED_USERS:-}"
SKIP_TELEGRAM="${SKIP_TELEGRAM:-0}"
SKIP_HERMES_TG_DISABLE="${SKIP_HERMES_TG_DISABLE:-0}"

AGENTS=(diretor cliente analista estrategista copywriter criativo gestor)

log() { printf '[bootstrap-agency] %s\n' "$*"; }
die() { printf '[bootstrap-agency] ERRO: %s\n' "$*" >&2; exit 1; }

command -v openclaw >/dev/null || die "openclaw CLI não encontrado"
[[ -d "$AGENCY_SRC/diretor" ]] || die "AGENCY_SRC inválido: $AGENCY_SRC (falta diretor/)"
[[ -f "$OPENCLAW_HOME/openclaw.json" ]] || die "falta $OPENCLAW_HOME/openclaw.json — rode o gateway/configure antes"
[[ -n "$API_KEY" ]] || die "APIPROMAX_GPT_API_KEY vazio — configure ApiProMax antes (docs/APIPROMAX.md)"
if [[ "$DEFAULT_PROVIDER" == "apipromax-claude" && -z "$CLAUDE_KEY" ]]; then
  die "OPENCLAW_DEFAULT_PROVIDER=apipromax-claude mas APIPROMAX_CLAUDE_API_KEY vazio"
fi

mkdir -p "$WS_ROOT/_shared/assets" "$WS_ROOT/_shared/creatives" "$WS_ROOT/clients"

# --- 0) clients/ → workspace (memória de contas do agente cliente) -----------
# Remove nest acidente (ex.: docker cp clients …/workspace/clients → clients/clients).
if [[ -d "$WS_ROOT/clients/clients" ]]; then
  log "removendo nest inválido $WS_ROOT/clients/clients"
  rm -rf "$WS_ROOT/clients/clients"
fi
if [[ -d "$CLIENTS_SRC" ]]; then
  log "sincronizando clients/ → $WS_ROOT/clients"
  # Copia templates/seeds; não apaga history local se existir só no volume.
  # Usa rsync se disponível para não recriar nest; senão cp -a dos conteúdos.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude 'clients' "$CLIENTS_SRC"/ "$WS_ROOT/clients/"
  else
    cp -a "$CLIENTS_SRC"/. "$WS_ROOT/clients/"
    [[ -d "$WS_ROOT/clients/clients" ]] && rm -rf "$WS_ROOT/clients/clients"
  fi
else
  log "aviso: CLIENTS_SRC ausente ($CLIENTS_SRC) — pulando sync de clients/"
fi
# Agente cliente grava via Telegram — garantir write no volume
chmod -R u+rwX "$WS_ROOT/clients" 2>/dev/null || true
if touch "$WS_ROOT/clients/.write-test" 2>/dev/null; then
  rm -f "$WS_ROOT/clients/.write-test"
  log "clients/ write OK ($WS_ROOT/clients)"
else
  log "AVISO: sem write em $WS_ROOT/clients — agente cliente não conseguirá gravar"
fi

# --- 1) Model providers ApiProMax (GPT + Claude) + defaults ------------------
log "configurando providers ApiProMax (default ${MODEL_REF})"
TMP_PATCH="$(mktemp)"
python3 - "$TMP_PATCH" "$BASE_URL" "$API_KEY" "${APIPROMAX_DEFAULT_MODEL:-gpt-5.4-mini}" \
  "$CLAUDE_KEY" "$CLAUDE_MODEL_ID" "$MODEL_REF" <<'PY'
import json, sys
out, base, gpt_key, gpt_mid, claude_key, claude_mid, mref = sys.argv[1:8]

def model_entry(mid, ctx=128000, max_tok=8192):
    return {
        "id": mid,
        "name": mid,
        "reasoning": False,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": ctx,
        "maxTokens": max_tok,
    }

providers = {
    "apipromax-gpt": {
        "baseUrl": base,
        "apiKey": gpt_key,
        "api": "openai-completions",
        "models": [model_entry(gpt_mid, 128000, 8192)],
    },
}
if claude_key.strip():
    providers["apipromax-claude"] = {
        "baseUrl": base,
        "apiKey": claude_key,
        "api": "openai-completions",
        "models": [model_entry(claude_mid, 200000, 8192)],
    }

patch = {
  "tools": {"profile": "coding"},
  "models": {
    "mode": "merge",
    "providers": providers,
  },
  "agents": {
    "defaults": {
      "model": {"primary": mref},
      "subagents": {
        "maxSpawnDepth": 2,
        "allowAgents": ["*"],
        "announceTimeoutMs": 300000,
        "maxConcurrent": 8,
        "archiveAfterMinutes": 60,
      },
    },
  },
}
with open(out, "w") as f:
  json.dump(patch, f)
print("providers:", ", ".join(providers.keys()))
print("default:", mref)
PY
openclaw config patch --file "$TMP_PATCH"
rm -f "$TMP_PATCH"
openclaw models set "$MODEL_REF" || log "aviso: models set falhou (pode já estar setado)"
if [[ -n "$CLAUDE_KEY" ]]; then
  log "provider apipromax-claude registrado (modelo ${CLAUDE_MODEL_ID}) — default continua ${MODEL_REF}"
else
  log "aviso: APIPROMAX_CLAUDE_API_KEY vazio — só apipromax-gpt registrado"
fi

# --- 2) Workspaces + agents.add ---------------------------------------------
agent_exists() {
  local id="$1"
  if openclaw agents list 2>/dev/null | grep -qE -- "- ${id}( |$)"; then
    echo yes
  else
    echo no
  fi
}

for id in "${AGENTS[@]}"; do
  src="$AGENCY_SRC/$id"
  dest="$WS_ROOT/$id"
  mkdir -p "$dest"
  for f in IDENTITY.md SOUL.md USER.md TOOLS.md AGENTS.md; do
    if [[ -f "$src/$f" ]]; then
      cp -f "$src/$f" "$dest/$f"
    fi
  done
  if [[ ! -f "$dest/IDENTITY.md" ]]; then
    printf '# Identity\n\n- nome: %s\n- emoji: 🤖\n' "$id" >"$dest/IDENTITY.md"
  fi

  if [[ "$(agent_exists "$id")" != "yes" ]]; then
    log "criando agente $id"
    openclaw agents add "$id" \
      --workspace "$dest" \
      --model "$MODEL_REF" \
      --non-interactive \
      --json || die "falha ao criar agente $id"
  else
    log "agente $id já existe — atualizando workspace/prompts"
  fi
  openclaw agents set-identity --agent "$id" --workspace "$dest" --from-identity --json || \
    log "aviso: set-identity $id falhou (IDENTITY.md pode estar fora do schema)"
done

# Agente cliente: atalho clients/ dentro do workspace (mesmo volume de _shared)
if [[ -d "$WS_ROOT/clients" ]]; then
  ln -sfn ../clients "$WS_ROOT/cliente/clients" 2>/dev/null || true
  # Garante que o workspace do agente resolve o symlink com write
  if [[ -L "$WS_ROOT/cliente/clients" ]] || [[ -d "$WS_ROOT/cliente/clients" ]]; then
    touch "$WS_ROOT/cliente/clients/.write-test" 2>/dev/null && \
      rm -f "$WS_ROOT/cliente/clients/.write-test" && \
      log "cliente/clients symlink write OK" || \
      log "AVISO: write via cliente/clients falhou"
  fi
fi

# Diretor = default (orquestrador). Edita openclaw.json diretamente (arrays do
# config patch substituem a lista inteira — perigoso sem merge manual).
log "marcando diretor como default no openclaw.json"
python3 - "$OPENCLAW_HOME/openclaw.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
agents = data.setdefault("agents", {})
lst = agents.setdefault("list", [])
if not isinstance(lst, list):
    lst = []
    agents["list"] = lst
by = {a.get("id"): a for a in lst if isinstance(a, dict) and a.get("id")}
needed = {
    "diretor": "/root/.openclaw/workspace/diretor",
    "cliente": "/root/.openclaw/workspace/cliente",
    "analista": "/root/.openclaw/workspace/analista",
    "estrategista": "/root/.openclaw/workspace/estrategista",
    "copywriter": "/root/.openclaw/workspace/copywriter",
    "criativo": "/root/.openclaw/workspace/criativo",
    "gestor": "/root/.openclaw/workspace/gestor",
}
for aid, ws in needed.items():
    entry = by.get(aid) or {"id": aid}
    entry["id"] = aid
    entry.setdefault("workspace", ws)
    entry.setdefault("agentDir", f"/root/.openclaw/agents/{aid}/agent")
    entry["default"] = aid == "diretor"
    by[aid] = entry
if "main" in by:
    by["main"]["default"] = False
    by["main"].setdefault("workspace", "/root/.openclaw/workspace")
order = ["diretor", "main", "cliente", "analista", "estrategista", "copywriter", "criativo", "gestor"]
out = []
seen = set()
for oid in order:
    if oid in by:
        out.append(by.pop(oid))
        seen.add(oid)
out.extend(by.values())
agents["list"] = out
p.write_text(json.dumps(data, indent=2) + "\n")
print("agents.list =", [a["id"] + ("*" if a.get("default") else "") for a in out])
PY

# --- 3) Telegram nativo OpenClaw → Diretor ----------------------------------
if [[ "$SKIP_TELEGRAM" != "1" && -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  log "configurando canal Telegram OpenClaw → diretor"
  ALLOW_JSON='[]'
  if [[ -n "$TELEGRAM_OWNER" ]]; then
    ALLOW_JSON="$(python3 -c 'import json,os; print(json.dumps([x.strip() for x in os.environ["TELEGRAM_OWNER"].split(",") if x.strip()]))' )"
  fi
  export TELEGRAM_OWNER
  openclaw config patch --stdin <<EOF
{
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "allowFrom": ${ALLOW_JSON},
      "botToken": "${TELEGRAM_BOT_TOKEN}"
    }
  }
}
EOF
  openclaw agents bind --agent diretor --bind telegram:default --json || \
    openclaw agents bind --agent diretor --bind telegram --json || \
    log "aviso: bind telegram→diretor falhou (verifique openclaw agents bindings)"
else
  log "pulando Telegram OpenClaw (SKIP_TELEGRAM=1 ou TELEGRAM_BOT_TOKEN vazio)"
fi

# --- 4) Desliga Telegram no Hermes (evita double-poll no mesmo bot) ----------
if [[ "$SKIP_HERMES_TG_DISABLE" != "1" ]]; then
  HERMES_ENV="${HERMES_DATA_DIR:-/root/.hermes}/.env"
  if [[ -f "$HERMES_ENV" ]]; then
    log "desabilitando TELEGRAM_* no Hermes (.env) para liberar o bot ao OpenClaw"
    tmp="$(mktemp)"
    grep -vE '^TELEGRAM_(BOT_TOKEN|ALLOWED_USERS|HOME_CHANNEL|HOME_CHANNEL_NAME)=' "$HERMES_ENV" >"$tmp" || true
    {
      echo '# Telegram = OpenClaw Diretor apenas. Hermes SEM poll (P1.4).'
      echo '# Nao preencha TELEGRAM_* aqui — o entrypoint tambem unsets no processo.'
      echo 'TELEGRAM_BOT_TOKEN='
      echo 'TELEGRAM_ALLOWED_USERS='
      echo 'TELEGRAM_HOME_CHANNEL='
      echo 'TELEGRAM_HOME_CHANNEL_NAME='
    } >>"$tmp"
    mv "$tmp" "$HERMES_ENV"
    chmod 600 "$HERMES_ENV"
  fi
fi

# --- 5) Validação ------------------------------------------------------------
log "validando"
openclaw config get agents.defaults.subagents || true
openclaw agents list || true
openclaw models status 2>&1 | head -40 || true
openclaw mcp list 2>&1 | head -20 || true

log "OK — reinicie o gateway (docker restart openclaw-vibestack-wa) para aplicar Telegram/Hermes."
log "NÃO reinicie o Evolution (preserva sessão WhatsApp)."
