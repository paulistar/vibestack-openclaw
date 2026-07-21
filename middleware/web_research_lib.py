"""Core de pesquisa/leitura web com proteções SSRF — sem dependência do FastMCP.

Usado por web_research_mcp.py e pelos testes unitários.
"""
from __future__ import annotations

import html as html_module
import ipaddress
import json
import os
import re
import socket
import ssl
from html.parser import HTMLParser
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote_plus, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

DEFAULT_UA = "vibestack-openclaw-web/1.0 (+agency research; respectful)"
BLOCKED_HOST_SUFFIXES = (
    ".local",
    ".localhost",
    ".internal",
    ".intranet",
)
BLOCKED_HOSTS = frozenset(
    {
        "localhost",
        "metadata.google.internal",
        "metadata.goog",
        "kubernetes.default",
        "kubernetes.default.svc",
    }
)
# Prefixo de hostnames conhecidos de metadata cloud
METADATA_HOST_PREFIXES = (
    "metadata.",
    "169.254.169.254",
)


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_csv(name: str) -> list[str]:
    raw = os.environ.get(name, "") or ""
    return [p.strip().lower() for p in raw.split(",") if p.strip()]


def config() -> dict[str, Any]:
    return {
        "timeout_sec": max(1, _env_int("WEB_FETCH_TIMEOUT_SEC", 20)),
        "max_bytes": max(1024, _env_int("WEB_FETCH_MAX_BYTES", 500_000)),
        "max_results": max(1, min(20, _env_int("WEB_SEARCH_MAX_RESULTS", 8))),
        "max_redirects": max(0, min(10, _env_int("WEB_FETCH_MAX_REDIRECTS", 5))),
        "user_agent": os.environ.get("WEB_USER_AGENT", "").strip() or DEFAULT_UA,
        "allowlist": _env_csv("WEB_URL_ALLOWLIST"),
        "denylist": _env_csv("WEB_URL_DENYLIST"),
        "provider": (os.environ.get("WEB_SEARCH_PROVIDER") or "auto").strip().lower(),
        "exa_key": os.environ.get("EXA_API_KEY", "").strip(),
        "tavily_key": os.environ.get("TAVILY_API_KEY", "").strip(),
        "brave_key": os.environ.get("BRAVE_SEARCH_API_KEY", "").strip(),
    }


# ---------------------------------------------------------------------------
# SSRF / URL policy
# ---------------------------------------------------------------------------

def _normalize_host(host: str) -> str:
    h = (host or "").strip().lower().rstrip(".")
    if h.startswith("[") and h.endswith("]"):
        h = h[1:-1]
    return h


def _host_matches_list(host: str, patterns: list[str]) -> bool:
    """Match exact host or parent domain (pattern 'example.com' bate em a.example.com)."""
    host = _normalize_host(host)
    for p in patterns:
        p = p.lstrip(".").lower()
        if not p:
            continue
        if host == p or host.endswith("." + p):
            return True
    return False


def is_blocked_ip(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
        return True
    if ip.is_multicast or ip.is_unspecified:
        return True
    # Cloud metadata / CGNAT edge cases
    if isinstance(ip, ipaddress.IPv4Address):
        if ip in ipaddress.ip_network("169.254.0.0/16"):
            return True
        if ip in ipaddress.ip_network("100.64.0.0/10"):  # CGNAT
            return True
    return False


def resolve_and_check_host(host: str) -> tuple[bool, str]:
    """Resolve DNS e rejeita se qualquer A/AAAA for privado/metadata."""
    host = _normalize_host(host)
    if not host:
        return False, "host vazio"
    if host in BLOCKED_HOSTS:
        return False, f"host bloqueado: {host}"
    if any(host.endswith(suf) for suf in BLOCKED_HOST_SUFFIXES):
        return False, f"host interno bloqueado: {host}"
    if any(host.startswith(p) for p in METADATA_HOST_PREFIXES):
        return False, f"host de metadata bloqueado: {host}"

    # Literal IP no host
    try:
        ip = ipaddress.ip_address(host)
        if is_blocked_ip(ip):
            return False, f"IP não público: {host}"
        return True, "ok"
    except ValueError:
        pass

    try:
        infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    except socket.gaierror as e:
        return False, f"DNS falhou para {host}: {e}"

    if not infos:
        return False, f"DNS sem resultados para {host}"

    for info in infos:
        sockaddr = info[4]
        addr = sockaddr[0]
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if is_blocked_ip(ip):
            return False, f"host resolve para IP não público ({addr})"
    return True, "ok"


def validate_url(
    url: str,
    *,
    cfg: dict[str, Any] | None = None,
    skip_allowlist: bool = False,
) -> tuple[bool, str]:
    """Valida URL para fetch/search-result follow. Retorna (ok, motivo).

    skip_allowlist=True: usado só para endpoints dos providers de search
    (api.exa.ai, DuckDuckGo, etc.) — a allowlist do operador aplica-se às
    URLs pedidas pelo agente (web_fetch), não aos backends de search.
    """
    cfg = cfg or config()
    raw = (url or "").strip()
    if not raw:
        return False, "URL vazia"
    if len(raw) > 2048:
        return False, "URL longa demais"

    parsed = urlparse(raw)
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https"):
        return False, f"scheme não permitido: {scheme or '(vazio)'}"
    host = _normalize_host(parsed.hostname or "")
    if not host:
        return False, "host ausente"
    if parsed.username or parsed.password:
        return False, "URL com credenciais embutidas não permitida"

    if cfg["denylist"] and _host_matches_list(host, cfg["denylist"]):
        return False, f"host na denylist: {host}"
    if (
        not skip_allowlist
        and cfg["allowlist"]
        and not _host_matches_list(host, cfg["allowlist"])
    ):
        return False, f"host fora da allowlist: {host}"

    ok, reason = resolve_and_check_host(host)
    if not ok:
        return False, reason
    return True, "ok"


# ---------------------------------------------------------------------------
# HTTP helpers (stdlib — zero deps obrigatórias)
# ---------------------------------------------------------------------------

def _http_request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
    timeout: float = 20,
    max_bytes: int = 500_000,
    max_redirects: int = 5,
    cfg: dict[str, Any] | None = None,
    skip_allowlist: bool = False,
) -> dict[str, Any]:
    """GET/POST com limite de bytes, redirects revalidados (SSRF) e timeout."""
    cfg = cfg or config()
    current = url
    method_u = method.upper()
    data = body

    for _ in range(max_redirects + 1):
        ok, reason = validate_url(current, cfg=cfg, skip_allowlist=skip_allowlist)
        if not ok:
            return {"error": reason, "url": current, "code": "ssrf_blocked"}

        req_headers = {
            "User-Agent": cfg["user_agent"],
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.5",
            "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
        }
        if headers:
            req_headers.update(headers)

        req = Request(current, data=data, headers=req_headers, method=method_u)
        ctx = ssl.create_default_context()
        try:
            with urlopen(req, timeout=timeout, context=ctx) as resp:
                chunks: list[bytes] = []
                total = 0
                truncated = False
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > max_bytes:
                        # guarda só até o limite
                        overflow = total - max_bytes
                        chunks.append(chunk[:-overflow] if overflow < len(chunk) else b"")
                        truncated = True
                        break
                    chunks.append(chunk)
                raw = b"".join(chunks)
                charset = resp.headers.get_content_charset() or "utf-8"
                try:
                    text = raw.decode(charset, errors="replace")
                except LookupError:
                    text = raw.decode("utf-8", errors="replace")
                final_url = resp.geturl() or current
                return {
                    "ok": True,
                    "url": final_url,
                    "status": getattr(resp, "status", 200),
                    "content_type": resp.headers.get("Content-Type", ""),
                    "text": text,
                    "bytes": len(raw),
                    "truncated": truncated,
                }
        except HTTPError as e:
            # redirects manuais para revalidar host
            if e.code in (301, 302, 303, 307, 308):
                loc = e.headers.get("Location")
                if not loc:
                    return {"error": f"redirect sem Location ({e.code})", "url": current}
                current = urljoin(current, loc)
                # 303 / 302 historically → GET
                if e.code in (302, 303) or method_u == "POST":
                    method_u = "GET"
                    data = None
                continue
            try:
                err_body = e.read(min(4096, max_bytes)).decode("utf-8", errors="replace")
            except Exception:  # noqa: BLE001
                err_body = ""
            return {
                "error": f"HTTP {e.code}",
                "url": current,
                "status": e.code,
                "body_preview": err_body[:500],
            }
        except URLError as e:
            return {"error": str(e.reason or e), "url": current}
        except TimeoutError:
            return {"error": "timeout", "url": current, "code": "timeout"}
        except Exception as e:  # noqa: BLE001
            return {"error": str(e), "url": current}

    return {"error": "excedeu max_redirects", "url": current, "code": "too_many_redirects"}


# ---------------------------------------------------------------------------
# HTML → texto limpo
# ---------------------------------------------------------------------------

class _TextExtractor(HTMLParser):
    SKIP = frozenset({"script", "style", "noscript", "svg", "iframe", "template"})

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip_depth = 0
        self._parts: list[str] = []
        self.title = ""
        self._in_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        t = tag.lower()
        if t in self.SKIP:
            self._skip_depth += 1
            return
        if self._skip_depth:
            return
        if t == "title":
            self._in_title = True
        if t in ("p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article"):
            self._parts.append("\n")
        if t == "li":
            self._parts.append("- ")

    def handle_endtag(self, tag: str) -> None:
        t = tag.lower()
        if t in self.SKIP and self._skip_depth:
            self._skip_depth -= 1
            return
        if t == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        text = data.strip()
        if not text:
            return
        if self._in_title:
            self.title += text + " "
            return
        self._parts.append(text + " ")


def html_to_text(html: str, *, max_chars: int = 80_000) -> dict[str, str]:
    """Extrai título + texto limpo de HTML (stdlib)."""
    # tenta html2text se instalado
    try:
        import html2text  # type: ignore

        h = html2text.HTML2Text()
        h.ignore_links = False
        h.ignore_images = True
        h.body_width = 0
        md = h.handle(html or "")
        title_m = re.search(r"<title[^>]*>(.*?)</title>", html or "", re.I | re.S)
        title = html_module.unescape(title_m.group(1).strip()) if title_m else ""
        text = re.sub(r"\n{3,}", "\n\n", md).strip()
        if len(text) > max_chars:
            text = text[:max_chars] + "\n…[truncado]"
        return {"title": title, "text": text}
    except Exception:  # noqa: BLE001
        pass

    parser = _TextExtractor()
    try:
        parser.feed(html or "")
        parser.close()
    except Exception:  # noqa: BLE001
        # HTML quebrado — fallback bruto
        stripped = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html or "")
        stripped = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", stripped)
        stripped = re.sub(r"(?s)<[^>]+>", " ", stripped)
        text = html_module.unescape(re.sub(r"\s+", " ", stripped)).strip()
        if len(text) > max_chars:
            text = text[:max_chars] + " …[truncado]"
        return {"title": "", "text": text}

    title = parser.title.strip()
    text = re.sub(r"[ \t]+", " ", "".join(parser._parts))
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if len(text) > max_chars:
        text = text[:max_chars] + "\n…[truncado]"
    return {"title": title, "text": text}


# ---------------------------------------------------------------------------
# Search providers
# ---------------------------------------------------------------------------

def _pick_provider(cfg: dict[str, Any]) -> str:
    pref = cfg["provider"]
    if pref in ("exa", "tavily", "brave", "ddg", "duckduckgo"):
        if pref in ("ddg", "duckduckgo"):
            return "ddg"
        key_map = {"exa": "exa_key", "tavily": "tavily_key", "brave": "brave_key"}
        if cfg.get(key_map[pref]):
            return pref
        return "ddg"  # fallback silencioso se key ausente
    # auto
    if cfg["exa_key"]:
        return "exa"
    if cfg["tavily_key"]:
        return "tavily"
    if cfg["brave_key"]:
        return "brave"
    return "ddg"


def _search_exa(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    payload = json.dumps(
        {
            "query": query,
            "numResults": cfg["max_results"],
            "type": "auto",
            "contents": {"text": False},
        }
    ).encode("utf-8")
    resp = _http_request(
        "https://api.exa.ai/search",
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-api-key": cfg["exa_key"],
        },
        body=payload,
        timeout=cfg["timeout_sec"],
        max_bytes=cfg["max_bytes"],
        max_redirects=2,
        cfg=cfg,
        skip_allowlist=True,
    )
    if not resp.get("ok"):
        return {"error": resp.get("error", "exa failed"), "provider": "exa", "detail": resp}
    try:
        data = json.loads(resp["text"])
    except json.JSONDecodeError as e:
        return {"error": f"exa JSON inválido: {e}", "provider": "exa"}
    results = []
    for item in data.get("results") or []:
        results.append(
            {
                "title": item.get("title") or "",
                "url": item.get("url") or "",
                "snippet": (item.get("summary") or item.get("text") or "")[:400],
            }
        )
    return {"ok": True, "provider": "exa", "query": query, "results": results[: cfg["max_results"]]}


def _search_tavily(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    payload = json.dumps(
        {
            "api_key": cfg["tavily_key"],
            "query": query,
            "max_results": cfg["max_results"],
            "include_answer": False,
        }
    ).encode("utf-8")
    resp = _http_request(
        "https://api.tavily.com/search",
        method="POST",
        headers={"Content-Type": "application/json"},
        body=payload,
        timeout=cfg["timeout_sec"],
        max_bytes=cfg["max_bytes"],
        max_redirects=2,
        cfg=cfg,
        skip_allowlist=True,
    )
    if not resp.get("ok"):
        return {"error": resp.get("error", "tavily failed"), "provider": "tavily", "detail": resp}
    try:
        data = json.loads(resp["text"])
    except json.JSONDecodeError as e:
        return {"error": f"tavily JSON inválido: {e}", "provider": "tavily"}
    results = []
    for item in data.get("results") or []:
        results.append(
            {
                "title": item.get("title") or "",
                "url": item.get("url") or "",
                "snippet": (item.get("content") or "")[:400],
            }
        )
    return {"ok": True, "provider": "tavily", "query": query, "results": results[: cfg["max_results"]]}


def _search_brave(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    url = "https://api.search.brave.com/res/v1/web/search?q=" + quote_plus(query)
    resp = _http_request(
        url,
        method="GET",
        headers={
            "Accept": "application/json",
            "X-Subscription-Token": cfg["brave_key"],
        },
        timeout=cfg["timeout_sec"],
        max_bytes=cfg["max_bytes"],
        max_redirects=2,
        cfg=cfg,
        skip_allowlist=True,
    )
    if not resp.get("ok"):
        return {"error": resp.get("error", "brave failed"), "provider": "brave", "detail": resp}
    try:
        data = json.loads(resp["text"])
    except json.JSONDecodeError as e:
        return {"error": f"brave JSON inválido: {e}", "provider": "brave"}
    results = []
    for item in (data.get("web") or {}).get("results") or []:
        results.append(
            {
                "title": item.get("title") or "",
                "url": item.get("url") or "",
                "snippet": (item.get("description") or "")[:400],
            }
        )
    return {"ok": True, "provider": "brave", "query": query, "results": results[: cfg["max_results"]]}


def _unwrap_ddg_url(href: str) -> str:
    """DuckDuckGo HTML usa /l/?uddg=<urlencoded>."""
    if not href:
        return ""
    if "uddg=" in href:
        parsed = urlparse(urljoin("https://duckduckgo.com", href))
        qs = parse_qs(parsed.query)
        if "uddg" in qs and qs["uddg"]:
            return qs["uddg"][0]
    if href.startswith("//"):
        return "https:" + href
    return href


def _search_ddg_lite(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    """DuckDuckGo Lite HTML — costuma funcionar melhor em VPS/datacenter que /html/."""
    url = "https://lite.duckduckgo.com/lite/?q=" + quote_plus(query)
    resp = _http_request(
        url,
        method="GET",
        timeout=cfg["timeout_sec"],
        max_bytes=cfg["max_bytes"],
        max_redirects=3,
        cfg=cfg,
        skip_allowlist=True,
    )
    if not resp.get("ok"):
        return {"error": resp.get("error", "ddg-lite failed"), "provider": "ddg-lite", "detail": resp}
    page = resp.get("text") or ""
    if "anomaly-modal" in page.lower() or "captcha" in page.lower()[:2000]:
        return {
            "error": "DuckDuckGo Lite pediu CAPTCHA",
            "provider": "ddg-lite",
            "hint": "Configure EXA_API_KEY / TAVILY_API_KEY / BRAVE_SEARCH_API_KEY.",
        }

    results: list[dict[str, str]] = []
    # href=... class='result-link'>title</a>
    for m in re.finditer(
        r"href=(['\"])([^'\"]+)\1[^>]*class=(['\"])result-link\3[^>]*>(.*?)</a>",
        page,
        re.I | re.S,
    ):
        href = html_module.unescape(m.group(2))
        title = html_module.unescape(re.sub(r"<[^>]+>", "", m.group(4)))
        title = re.sub(r"\s+", " ", title).strip()
        final = _unwrap_ddg_url(href)
        if not final.startswith("http"):
            continue
        if "duckduckgo.com" in final:
            continue
        results.append({"title": title, "url": final, "snippet": ""})
        if len(results) >= cfg["max_results"]:
            break

    snippets = re.findall(
        r"class=(['\"])result-snippet\1[^>]*>(.*?)</td>",
        page,
        re.I | re.S,
    )
    for i, sn in enumerate(snippets):
        if i >= len(results):
            break
        clean = html_module.unescape(re.sub(r"<[^>]+>", " ", sn[1] if isinstance(sn, tuple) else sn))
        results[i]["snippet"] = re.sub(r"\s+", " ", clean).strip()[:400]

    if not results:
        return {"error": "ddg-lite sem resultados parseáveis", "provider": "ddg-lite"}
    return {
        "ok": True,
        "provider": "ddg-lite",
        "query": query,
        "results": results,
        "note": "DuckDuckGo Lite (sem key). Prefira Exa/Tavily/Brave para produção.",
    }


def _search_wikipedia(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    """OpenSearch Wikipedia (pt+en) — fallback mínimo sem key."""
    results: list[dict[str, str]] = []
    for lang in ("pt", "en"):
        url = (
            f"https://{lang}.wikipedia.org/w/api.php?action=opensearch&search="
            + quote_plus(query)
            + f"&limit={cfg['max_results']}&namespace=0&format=json"
        )
        resp = _http_request(
            url,
            method="GET",
            timeout=cfg["timeout_sec"],
            max_bytes=100_000,
            max_redirects=2,
            cfg=cfg,
            skip_allowlist=True,
        )
        if not resp.get("ok"):
            continue
        try:
            data = json.loads(resp["text"])
        except json.JSONDecodeError:
            continue
        # [query, [titles], [descs], [urls]]
        if not isinstance(data, list) or len(data) < 4:
            continue
        titles, descs, urls = data[1], data[2], data[3]
        for i, u in enumerate(urls):
            if not u:
                continue
            results.append(
                {
                    "title": (titles[i] if i < len(titles) else u) or u,
                    "url": u,
                    "snippet": (descs[i] if i < len(descs) else "") or "",
                }
            )
            if len(results) >= cfg["max_results"]:
                break
        if results:
            break
    if not results:
        return {"error": "wikipedia sem resultados", "provider": "wikipedia"}
    return {
        "ok": True,
        "provider": "wikipedia",
        "query": query,
        "results": results[: cfg["max_results"]],
        "note": "Fallback Wikipedia OpenSearch (sem key) — só enciclopédia, não web geral.",
    }


def _search_ddg_api(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    """Instant Answer API (sem key) — cobertura limitada."""
    url = (
        "https://api.duckduckgo.com/?q="
        + quote_plus(query)
        + "&format=json&no_html=1&skip_disambig=1"
    )
    resp = _http_request(
        url,
        method="GET",
        timeout=cfg["timeout_sec"],
        max_bytes=min(cfg["max_bytes"], 200_000),
        max_redirects=2,
        cfg=cfg,
        skip_allowlist=True,
    )
    if not resp.get("ok"):
        return {"error": resp.get("error", "ddg-api failed"), "provider": "ddg-api"}
    try:
        data = json.loads(resp["text"])
    except json.JSONDecodeError as e:
        return {"error": f"ddg-api JSON inválido: {e}", "provider": "ddg-api"}

    results: list[dict[str, str]] = []
    abstract = (data.get("AbstractText") or "").strip()
    abs_url = (data.get("AbstractURL") or "").strip()
    heading = (data.get("Heading") or "").strip()
    if abs_url and abstract:
        results.append({"title": heading or abs_url, "url": abs_url, "snippet": abstract[:400]})

    for item in data.get("Results") or []:
        u = (item.get("FirstURL") or "").strip()
        t = re.sub(r"<[^>]+>", "", item.get("Text") or "")
        if u:
            results.append({"title": t[:120] or u, "url": u, "snippet": t[:400]})
        if len(results) >= cfg["max_results"]:
            break

    for topic in data.get("RelatedTopics") or []:
        if len(results) >= cfg["max_results"]:
            break
        if isinstance(topic, dict) and topic.get("FirstURL"):
            u = topic["FirstURL"]
            t = re.sub(r"<[^>]+>", "", topic.get("Text") or "")
            results.append({"title": t[:120] or u, "url": u, "snippet": t[:400]})
        elif isinstance(topic, dict) and isinstance(topic.get("Topics"), list):
            for sub in topic["Topics"]:
                if len(results) >= cfg["max_results"]:
                    break
                if not isinstance(sub, dict) or not sub.get("FirstURL"):
                    continue
                u = sub["FirstURL"]
                t = re.sub(r"<[^>]+>", "", sub.get("Text") or "")
                results.append({"title": t[:120] or u, "url": u, "snippet": t[:400]})

    if not results:
        return {"error": "ddg-api sem resultados", "provider": "ddg-api"}
    return {
        "ok": True,
        "provider": "ddg-api",
        "query": query,
        "results": results[: cfg["max_results"]],
        "note": "DuckDuckGo Instant Answer (sem key) — cobertura limitada vs Exa/Tavily/Brave.",
    }


def _search_ddg(query: str, cfg: dict[str, Any]) -> dict[str, Any]:
    """Busca sem API key: Lite → Instant Answer → HTML → Wikipedia."""
    errors: list[str] = []

    lite = _search_ddg_lite(query, cfg)
    if lite.get("ok"):
        return lite
    errors.append(f"lite: {lite.get('error')}")

    api = _search_ddg_api(query, cfg)
    if api.get("ok"):
        return api
    errors.append(f"api: {api.get('error')}")

    url = "https://html.duckduckgo.com/html/?q=" + quote_plus(query)
    resp = _http_request(
        url,
        method="GET",
        timeout=cfg["timeout_sec"],
        max_bytes=cfg["max_bytes"],
        max_redirects=3,
        cfg=cfg,
        skip_allowlist=True,
    )
    if resp.get("ok"):
        page = resp.get("text") or ""
        if "anomaly-modal" not in page.lower() and "captcha" not in page.lower()[:2000]:
            results: list[dict[str, str]] = []
            for m in re.finditer(
                r'<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
                page,
                re.I | re.S,
            ):
                href = html_module.unescape(m.group(1))
                title = re.sub(r"<[^>]+>", "", m.group(2))
                title = html_module.unescape(re.sub(r"\s+", " ", title)).strip()
                final = _unwrap_ddg_url(href)
                if not final.startswith("http"):
                    continue
                results.append({"title": title, "url": final, "snippet": ""})
                if len(results) >= cfg["max_results"]:
                    break
            snippets = re.findall(
                r'<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
                page,
                re.I | re.S,
            )
            for i, sn in enumerate(snippets):
                if i >= len(results):
                    break
                clean = html_module.unescape(re.sub(r"<[^>]+>", " ", sn))
                results[i]["snippet"] = re.sub(r"\s+", " ", clean).strip()[:400]
            if results:
                return {
                    "ok": True,
                    "provider": "ddg-html",
                    "query": query,
                    "results": results,
                    "note": "Fallback HTML sem API key — qualidade/estabilidade limitadas vs Exa/Tavily/Brave.",
                }
        else:
            errors.append("html: CAPTCHA")
    else:
        errors.append(f"html: {resp.get('error')}")

    wiki = _search_wikipedia(query, cfg)
    if wiki.get("ok"):
        wiki["note"] = (
            "Fallbacks DDG falharam; Wikipedia OpenSearch. "
            "Configure EXA/TAVILY/BRAVE para busca web geral. "
            + "; ".join(errors)
        )
        return wiki

    return {
        "error": "Todos os fallbacks sem-key falharam",
        "provider": "ddg",
        "hint": "Configure EXA_API_KEY, TAVILY_API_KEY ou BRAVE_SEARCH_API_KEY no .env.",
        "attempts": errors,
        "wikipedia_error": wiki.get("error"),
    }


def web_search(query: str, *, max_results: int | None = None) -> dict[str, Any]:
    q = (query or "").strip()
    if not q:
        return {"error": "query vazia"}
    if len(q) > 500:
        return {"error": "query longa demais (max 500)"}

    cfg = config()
    if max_results is not None:
        cfg = {**cfg, "max_results": max(1, min(20, int(max_results)))}

    provider = _pick_provider(cfg)
    runners = {
        "exa": _search_exa,
        "tavily": _search_tavily,
        "brave": _search_brave,
        "ddg": _search_ddg,
    }
    result = runners[provider](q, cfg)
    # se provider pago falhar e não for ddg, tenta ddg
    if not result.get("ok") and provider != "ddg":
        fallback = _search_ddg(q, cfg)
        if fallback.get("ok"):
            fallback["note"] = f"Provider {provider} falhou ({result.get('error')}); usei ddg."
            fallback["primary_error"] = result.get("error")
            return fallback
        result["fallback_error"] = fallback.get("error")
    return result


def web_fetch(url: str, *, max_chars: int | None = None) -> dict[str, Any]:
    cfg = config()
    ok, reason = validate_url(url, cfg=cfg)
    if not ok:
        return {"error": reason, "url": url, "code": "ssrf_blocked"}

    resp = _http_request(
        url.strip(),
        method="GET",
        timeout=cfg["timeout_sec"],
        max_bytes=cfg["max_bytes"],
        max_redirects=cfg["max_redirects"],
        cfg=cfg,
    )
    if not resp.get("ok"):
        return {
            "error": resp.get("error", "fetch failed"),
            "url": url,
            "detail": {k: v for k, v in resp.items() if k != "text"},
        }

    ctype = (resp.get("content_type") or "").lower()
    text_raw = resp.get("text") or ""
    title = ""
    text_out = text_raw

    if "html" in ctype or text_raw.lstrip()[:100].lower().startswith(("<!doctype", "<html")):
        extracted = html_to_text(text_raw, max_chars=max_chars or 80_000)
        title = extracted["title"]
        text_out = extracted["text"]
    else:
        limit = max_chars or 80_000
        if len(text_out) > limit:
            text_out = text_out[:limit] + "\n…[truncado]"

    # Nunca ecoar Authorization headers / cookies do processo
    return {
        "ok": True,
        "url": resp.get("url") or url,
        "status": resp.get("status"),
        "content_type": resp.get("content_type"),
        "title": title,
        "text": text_out,
        "bytes_read": resp.get("bytes"),
        "truncated": bool(resp.get("truncated")),
        "memory_hint": (
            "Se o conteúdo for fato estável de um cliente (site, ICP, oferta, tom), "
            "peça ao agente Cliente para gravar em clients/<slug>/ (PROFILE/brand/offers/history)."
        ),
    }


def web_research_status() -> dict[str, Any]:
    cfg = config()
    provider = _pick_provider(cfg)
    return {
        "ok": True,
        "provider_active": provider,
        "provider_preference": cfg["provider"],
        "keys_present": {
            "exa": bool(cfg["exa_key"]),
            "tavily": bool(cfg["tavily_key"]),
            "brave": bool(cfg["brave_key"]),
        },
        "timeout_sec": cfg["timeout_sec"],
        "max_bytes": cfg["max_bytes"],
        "max_results": cfg["max_results"],
        "allowlist_count": len(cfg["allowlist"]),
        "denylist_count": len(cfg["denylist"]),
        "browser": "fase2_opcional",
        "note": "Search sem key usa DuckDuckGo HTML (limites/CAPTCHA). Fetch é HTTP→texto.",
    }
