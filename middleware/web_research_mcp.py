#!/usr/bin/env python3
"""MCP server stdio — pesquisa e leitura web (infra transversal da agência).

Tools:
  web_search          — busca (Exa/Tavily/Brave se key; senão DuckDuckGo HTML)
  web_fetch           — baixa URL e devolve texto/markdown limpo
  web_research_status — provider ativo, limites, keys presentes (sem expor secrets)

Segurança: SSRF (bloqueia IPs privados/metadata), allowlist/denylist, timeout,
tamanho máximo. Ver docs/WEB-RESEARCH.md.

Env (repassados pelo entrypoint — child MCP tem env reduzido):
  WEB_SEARCH_PROVIDER, EXA_API_KEY, TAVILY_API_KEY, BRAVE_SEARCH_API_KEY,
  WEB_FETCH_TIMEOUT_SEC, WEB_FETCH_MAX_BYTES, WEB_SEARCH_MAX_RESULTS,
  WEB_URL_ALLOWLIST, WEB_URL_DENYLIST, WEB_USER_AGENT, WEB_FETCH_MAX_REDIRECTS
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

# Garante import do sibling quando spawnado pelo openclaw
_MID = Path(__file__).resolve().parent
if str(_MID) not in sys.path:
    sys.path.insert(0, str(_MID))

from mcp.server.fastmcp import FastMCP

from web_research_lib import web_fetch as _fetch
from web_research_lib import web_research_status as _status
from web_research_lib import web_search as _search

mcp = FastMCP("web-research")


@mcp.tool()
def web_search(query: str, max_results: int = 8) -> Any:
    """Pesquisa a web. Use para estratégia, SEO, concorrência, cliente, conteúdo, ops, etc.

    query: termos de busca (pt ou en).
    max_results: 1–20 (default 8).

    Retorna lista de {title, url, snippet} + provider usado.
    NÃO é tool de ads — é infraestrutura transversal. Achados estáveis de cliente
    devem ser gravados em clients/<slug>/ via agente Cliente.
    """
    return _search(query, max_results=max_results)


@mcp.tool()
def web_fetch(url: str, max_chars: int = 80000) -> Any:
    """Lê uma URL pública e devolve título + texto limpo (HTML→texto/markdown).

    url: http(s) público. Bloqueia IPs privados, metadata cloud e denylist.
    max_chars: teto do texto devolvido (default 80000).

    Limitações: páginas 100% JS / CAPTCHA / paywall podem vir vazias ou incompletas.
    Browser Playwright = fase 2 (não neste MCP).
    """
    return _fetch(url, max_chars=max_chars)


@mcp.tool()
def web_research_status() -> Any:
    """Mostra provider de search ativo, se há API keys (boolean), timeouts e allowlist.

    Não revela o valor das keys.
    """
    return _status()


if __name__ == "__main__":
    mcp.run()
