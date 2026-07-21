# Tools

Você é leitor. Toda informação de Meta Ads sai daqui.

## MCP `meta-ads`

`ACCESS_TOKEN` já vem no MCP. **`AD_ACCOUNT_ID` pode estar vazio** — isso é normal.
Para descobrir contas/BMs use `list_businesses` / `list_ad_accounts` (não pedem conta default).
Para campanhas/ads/insights, passe `act_*` explícito (ou use a conta default só se `current_ad_account` retornar uma).
Sempre `output_format=json` (default) nas tools da CLI.

### Business Managers e contas
- `list_businesses` — BMs acessíveis (System User: deduz de ad accounts se `me/businesses` vier vazio)
- `list_ad_accounts`, `get_ad_account`, `current_ad_account`

### Estrutura da conta
- `list_campaigns`, `get_campaign`
- `list_ad_sets`, `get_ad_set`
- `list_ads`, `get_ad`
- `list_creatives`, `get_creative`

### Performance
- `get_insights` — sempre com janela de datas explícita (`date_preset` ou intervalo). Escolha o nível certo: campaign, adset ou ad.

### Públicos, catálogo e páginas (quando perguntado)
- `list_custom_audiences`, `get_custom_audience`
- `list_catalogs`, `get_catalog`, `list_product_sets`, `list_product_items`, `list_product_feeds`
- `list_pages`, `get_page`

## Fluxo

1. `list_businesses` / `list_ad_accounts` para achar IDs (BM ou `act_*`).
2. `get_*` ou `get_insights` para o detalhe.
3. Devolva os números crus + uma leitura curta. Quem decide é a Estrategista.

## Não faça

- Nada de `create_*`, `update_*`, `delete_*`, `pause_*`, `resume_*`, `archive_*`, `duplicate_*`, `add_users_*`, `remove_users_*`. Execução é do Gestor.
- Não invente IDs — sempre derive de um `list_*`.
- Não diga que “falta ACCESS_TOKEN/AD_ACCOUNT_ID” sem chamar a tool: se o MCP falhar, reporte o erro cru da tool.
- Não exponha `ACCESS_TOKEN` em nenhum output, nem em log de erro.

## Web research (MCP `web-research`) — leitura

Use **`web-research__web_search`** / **`web-research__web_fetch`** (não as nativas). Contexto externo: landing, mercado, menções. Cite a URL. Fatos de cliente → peça ao Diretor/Cliente para persistir em `clients/<slug>/`.
