# Web research (MCP `web-research`)

Infraestrutura **transversal** da agência: qualquer frente pode pesquisar e ler a web (estratégia, cliente, SEO, conteúdo, comercial, ops, criativo, admin). **Não** é feature de Meta/Google Ads.

## Tools

| Tool | Função |
|------|--------|
| `web_search` | Busca → `{title, url, snippet}[]` + provider |
| `web_fetch` | URL → título + texto limpo (HTML→texto/markdown) |
| `web_research_status` | Provider ativo, keys presentes (boolean), limites |

No OpenClaw **obrigatório** usar o prefixo MCP: `web-research__web_search`, `web-research__web_fetch`, `web-research__web_research_status`.

O OpenClaw também expõe tools nativas `web_search` / `web_fetch` — **não use** para a agência (o nativo exige provider configurado e falha com “disabled or no provider”; o MCP tem SSRF + fallback DDG). O entrypoint aplica `tools.deny` nas nativas quando possível.

## Config (`.env`)

```bash
WEB_SEARCH_PROVIDER=auto   # auto|exa|tavily|brave|ddg
EXA_API_KEY=               # opcional
TAVILY_API_KEY=            # opcional
BRAVE_SEARCH_API_KEY=      # opcional
WEB_FETCH_TIMEOUT_SEC=20
WEB_FETCH_MAX_BYTES=500000
WEB_FETCH_MAX_REDIRECTS=5
WEB_SEARCH_MAX_RESULTS=8
WEB_URL_ALLOWLIST=         # CSV; vazio = qualquer host público
WEB_URL_DENYLIST=          # CSV sempre bloqueado
WEB_USER_AGENT=            # opcional
```

`auto` escolhe a primeira key presente (Exa → Tavily → Brave). Sem key → **DuckDuckGo HTML** (sem custo; sujeito a CAPTCHA/rate-limit em IP de datacenter).

Placeholders em [`.env.example`](../.env.example). Secrets só no `.env` da VPS / secrets file — nunca no git.

## Segurança

- Só `http`/`https`
- Bloqueio SSRF: IPs privados, loopback, link-local, CGNAT, metadata (`169.254.169.254`, hostnames de metadata)
- Redirects revalidados a cada hop
- Timeout + teto de bytes
- Allowlist / denylist configuráveis
- Tools **nunca** ecoam API keys

## Memória

Achados **estáveis de cliente** (site, ICP, oferta, tom, concorrentes nomeados) → gravar em `clients/<slug>/` via agente **Cliente** (`PROFILE` / `brand` / `offers` / `history`). Não “responder e esquecer”.

Pesquisa genérica de mercado/SEO pode ficar na sessão; fatos de conta vão para `clients/`.

## Quem usa

Leitura/pesquisa: Diretor, Cliente, Analista, Estrategista, Copywriter, Criativo. Gestor: read-only (conferir landing/URL antes de publicar).

Browser Playwright = **fase 2** (opcional). MVP = search + fetch estáveis no Docker.

## Smoke

```bash
# No container openclaw
docker exec openclaw-vibestack-wa openclaw mcp list | grep web-research

docker exec openclaw-vibestack-wa /opt/middleware-venv/bin/python - <<'PY'
from web_research_lib import web_search, web_fetch, web_research_status
import sys
sys.path.insert(0, "/app/middleware")
from web_research_lib import web_search, web_fetch, web_research_status
print(web_research_status())
print(web_search("Mart Studios marketing", max_results=3))
print(web_fetch("https://martstudiosbr.com.br"))
PY

# Agente isolado
docker exec openclaw-vibestack-wa openclaw agent \
  --agent diretor \
  --session-key agent:diretor:web-smoke \
  --message "Chame web-research__web_search com query 'Mart Studios marketing' e web-research__web_fetch com url https://example.com; resuma em 3 bullets o que as tools devolveram. Nao invente."
```

Session-key: `agent:diretor:web-smoke`.

## Limitações

| Caso | Efeito |
|------|--------|
| CAPTCHA / bot-block (DDG ou site) | Search/fetch falha ou vazio |
| Página 100% JS (SPA) | Texto incompleto sem browser |
| Paywall | Conteúdo parcial |
| Search sem API key | DDG HTML — qualidade/estabilidade inferiores |

## Arquivos

- `middleware/web_research_lib.py` — core + SSRF
- `middleware/web_research_mcp.py` — FastMCP
- `middleware/test_web_research.py` — unitários
- Registro: `entrypoint.sh` (OpenClaw + Hermes)
