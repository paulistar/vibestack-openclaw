#!/usr/bin/env python3
"""Bridge inbound do WhatsApp: Evolution Go (webhook) -> agente Hermes -> resposta.

Fecha o ciclo do "canal" de WhatsApp (o envio já é coberto pelo MCP
whatsapp_evolution_mcp.py). Fluxo:

  WhatsApp -> Evolution Go (evento "Message") --webhook POST--> ESTE bridge
           -> Hermes api_server (/v1/chat/completions, sessão por número)
           -> Evolution Go (/send/text) -> WhatsApp

Roda como processo no container openclaw-vibestack (subido pelo entrypoint),
escutando em 0.0.0.0:WA_BRIDGE_PORT — alcançável pelo evolution-go via DNS do
compose (http://openclaw-vibestack:<porta>/webhook). Só stdlib (http.server +
urllib), sem dependência nova.

Formato do webhook (confirmado em pkg/whatsmeow/service/whatsmeow.go):
  {"event": "Message", "data": {"Info": {"Chat","Sender","IsFromMe","ID",...},
                                "Message": {"conversation": "..." | "extendedTextMessage": {"text": "..."}}}}

Env:
  WA_BRIDGE_PORT            porta do listener (default 8765; só rede interna do compose)
  WA_BRIDGE_UPSTREAM        base do agente (default http://127.0.0.1:8642 = Hermes api_server)
  WA_BRIDGE_UPSTREAM_KEY    Bearer do api_server (= HERMES_API_SERVER_KEY)
  WA_BRIDGE_MODEL           modelo exposto (default 'hermes-agent')
  WA_BRIDGE_SESSION_PREFIX  prefixo da sessão por contato (default 'wa')
  WA_BRIDGE_ALLOWED_NUMBERS CSV de números permitidos (vazio = todos; recomendado preencher)
  WA_BRIDGE_UPSTREAM_TIMEOUT timeout (s) da chamada ao agente (default 300 — tool calls demoram)
  EVOLUTION_BASE_URL        base do Evolution Go (default http://evolution-go:8080)
  EVOLUTION_INSTANCE_TOKEN  token da instância (apikey de envio)
"""
import json
import os
import re
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("WA_BRIDGE_PORT", "8765"))
UPSTREAM = os.environ.get("WA_BRIDGE_UPSTREAM", "http://127.0.0.1:8642").rstrip("/")
UPSTREAM_KEY = os.environ.get("WA_BRIDGE_UPSTREAM_KEY", "")
MODEL = os.environ.get("WA_BRIDGE_MODEL", "hermes-agent")
SESSION_PREFIX = os.environ.get("WA_BRIDGE_SESSION_PREFIX", "wa")
UPSTREAM_TIMEOUT = int(os.environ.get("WA_BRIDGE_UPSTREAM_TIMEOUT", "300"))
EVOLUTION_BASE_URL = os.environ.get("EVOLUTION_BASE_URL", "http://evolution-go:8080").rstrip("/")
EVOLUTION_INSTANCE_TOKEN = os.environ.get("EVOLUTION_INSTANCE_TOKEN", "")

_allowed_raw = os.environ.get("WA_BRIDGE_ALLOWED_NUMBERS", "").strip()
ALLOWED = {re.sub(r"\D", "", n) for n in _allowed_raw.split(",") if n.strip()}

# Dedup de message IDs já processados (Evolution pode reentregar). Bounded.
_seen_ids: dict[str, None] = {}
_seen_lock = threading.Lock()
_SEEN_MAX = 2000


def _log(msg: str) -> None:
    print(f"[wa-bridge] {msg}", flush=True)


def _seen(msg_id: str) -> bool:
    """True se msg_id já foi visto (e registra). Evita processar reentregas."""
    if not msg_id:
        return False
    with _seen_lock:
        if msg_id in _seen_ids:
            return True
        _seen_ids[msg_id] = None
        if len(_seen_ids) > _SEEN_MAX:
            for k in list(_seen_ids)[: _SEEN_MAX // 2]:
                _seen_ids.pop(k, None)
    return False


def _digits(jid: str) -> str:
    """Extrai o número (só dígitos) de um JID '5511...@s.whatsapp.net' ou '...:device@...'."""
    head = re.split(r"[:@]", str(jid or ""), 1)[0]
    return re.sub(r"\D", "", head)


def _extract(data: dict) -> tuple[str, str, str] | None:
    """Devolve (number, text, msg_id) de um evento Message inbound; None se deve ignorar.

    Defensivo quanto a casing (Info/info, IsFromMe/isFromMe, Message/message).
    """
    info = data.get("Info") or data.get("info") or {}
    msg = data.get("Message") or data.get("message") or {}

    from_me = info.get("IsFromMe", info.get("isFromMe", info.get("fromMe", False)))
    if from_me:
        return None  # mensagem nossa (eco do envio)

    chat = str(info.get("Chat") or info.get("chat") or "")
    if "@g.us" in chat or "@broadcast" in chat or "status@" in chat:
        return None  # grupos e status: fora do canal 1:1

    sender = info.get("Sender") or info.get("sender") or chat
    number = _digits(sender)
    if not number:
        return None

    text = msg.get("conversation") or msg.get("Conversation")
    if not text:
        ext = msg.get("extendedTextMessage") or msg.get("ExtendedTextMessage") or {}
        text = ext.get("text") or ext.get("Text")
    if not text:
        # mídia/áudio/etc. sem texto — fora do escopo (só texto por enquanto)
        return None

    msg_id = str(info.get("ID") or info.get("Id") or info.get("id") or "")
    return number, str(text), msg_id


def _ask_agent(number: str, text: str) -> str:
    """Manda o texto pro agente (Hermes api_server) com sessão por contato; retorna a resposta."""
    if not UPSTREAM_KEY:
        return "(bridge sem WA_BRIDGE_UPSTREAM_KEY configurada)"
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": text}],
        "stream": False,
    }).encode("utf-8")
    req = urllib.request.Request(
        f"{UPSTREAM}/v1/chat/completions",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {UPSTREAM_KEY}",
            # Continuidade de conversa por número (api_server: X-Hermes-Session-Id).
            "X-Hermes-Session-Id": f"{SESSION_PREFIX}:{number}",
        },
    )
    with urllib.request.urlopen(req, timeout=UPSTREAM_TIMEOUT) as resp:
        out = json.loads(resp.read().decode("utf-8"))
    try:
        return out["choices"][0]["message"]["content"] or "(resposta vazia)"
    except (KeyError, IndexError, TypeError):
        return "(nao consegui interpretar a resposta do agente)"


def _send_whatsapp(number: str, text: str) -> None:
    """Envia a resposta de volta pelo Evolution Go (/send/text)."""
    body = json.dumps({"number": number, "text": text}).encode("utf-8")
    req = urllib.request.Request(
        f"{EVOLUTION_BASE_URL}/send/text",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "apikey": EVOLUTION_INSTANCE_TOKEN},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        resp.read()


def _process(number: str, text: str) -> None:
    """Worker: pergunta ao agente e responde no WhatsApp. Roda fora do request HTTP."""
    try:
        _log(f"in  <- {number}: {text[:80]!r}")
        reply = _ask_agent(number, text)
        _send_whatsapp(number, reply)
        _log(f"out -> {number}: {reply[:80]!r}")
    except urllib.error.HTTPError as e:
        _log(f"ERRO HTTP {e.code} processando {number}: {e.read()[:200]!r}")
    except Exception as e:  # noqa: BLE001
        _log(f"ERRO processando {number}: {e}")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # silencia o log padrao ruidoso do http.server
        pass

    def _ok(self, code: int = 200) -> None:
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def do_GET(self):
        # Health check simples.
        self._ok()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        # Responde 200 IMEDIATAMENTE — o agente pode demorar (tool calls);
        # assim o Evolution nao expira/reentrega o webhook.
        self._ok()
        try:
            payload = json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            return
        if str(payload.get("event") or payload.get("Event") or "").lower() != "message":
            return
        data = payload.get("data") or payload.get("Data") or {}
        extracted = _extract(data)
        if not extracted:
            return
        number, text, msg_id = extracted
        if _seen(msg_id):
            return
        if ALLOWED and number not in ALLOWED:
            _log(f"ignorado (fora da allowlist): {number}")
            return
        threading.Thread(target=_process, args=(number, text), daemon=True).start()


def main() -> None:
    if not EVOLUTION_INSTANCE_TOKEN:
        _log("AVISO: EVOLUTION_INSTANCE_TOKEN vazio — nao vou conseguir responder no WhatsApp.")
    if not ALLOWED:
        _log("AVISO: WA_BRIDGE_ALLOWED_NUMBERS vazio — QUALQUER numero que mandar msg fala com o agente.")
    _log(f"escutando em 0.0.0.0:{PORT} (webhook POST /webhook) -> agente {UPSTREAM} -> {EVOLUTION_BASE_URL}")
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
