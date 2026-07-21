# Tools

Você lê **e escreve** arquivos de contexto de cliente. Não precisa de MCP de anúncios.

## Caminhos canônicos

- Índice: `/root/.openclaw/workspace/clients/INDEX.md`
- Template: `/root/.openclaw/workspace/clients/_template/`
- Cliente: `/root/.openclaw/workspace/clients/<slug>/`
  - `PROFILE.md` — quem é, ICP, objetivos, IDs de conta
  - `brand.md` — tom, visual, claims
  - `offers.md` — ofertas ativas / o que não vender
  - `history.md` — decisões e aprendizados

Atalho no workspace do agente: `clients/` → mesmo volume (`../clients`).

Grave **somente** sob `/root/.openclaw/workspace/clients/...` (ou o symlink `clients/...`). Nunca `/tmp`, `/app` ou fora de `.openclaw`.

## Leitura

1. Abra `INDEX.md` se o slug for ambíguo.
2. Leia os 4 arquivos do slug (ou só os necessários ao pedido).
3. Cite sempre o caminho relativo (`clients/<slug>/brand.md`) ao afirmar um fato.

## Escrita — obrigatória em novo/atualização

Quando o Diretor pedir criar, atualizar ou registrar fatos de cliente:

1. Normalize o **slug** (minúsculas, hífen, sem acento).
2. Se a pasta não existir: copie de `_template/` para `clients/<slug>/`.
3. Preencha / faça merge nos 4 arquivos com fatos da mensagem (sem inventar).
4. **Append** em `history.md` (entrada `### YYYY-MM-DD — título` + Fonte: Telegram / call / …).
5. Atualize a tabela em `INDEX.md`.
6. Confirme no chat: o que salvou + Ambíguo/TODO.

### Merge incremental

- Mensagens do tipo “mais info: …” → atualizar seções e append no history.
- Não apague fatos já gravados sem ordem explícita de correção.
- Conflito (novo fato contradiz arquivo) → registre ambos no history e marque Ambíguo; peça clarificação ao Diretor.

### Segurança

- Sem tokens, senhas, API keys nos arquivos.
- Só contexto de marca / ICP / oferta / IDs públicos de conta (Meta Ad Account, Google Customer ID).

## Web research (MCP `web-research`)

Use **`web-research__web_search`** / **`web-research__web_fetch`** (não as tools nativas `web_search`/`web_fetch` do OpenClaw). Enriquecer contexto: site do cliente, páginas de oferta, menções públicas.

- Achado **confirmado** e estável → **grave** em `PROFILE.md` / `brand.md` / `offers.md` + append em `history.md` (fonte: URL + data).
- Não grave rumor; marque Ambíguo/TODO se incerto.
- Nunca copie secrets de páginas; só fatos de marca/negócio.
