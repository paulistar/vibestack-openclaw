# History — Mart Studios

### 2026-07-20 — P1.2 dados reais (repo)
- Contexto: seeds com TODO genérico não bastavam; agente `cliente` precisa de perfil substancial.
- Decisão / entrega: PROFILE/brand/offers/history preenchidos com fatos do ecossistema (domínios, Telegram `@chatmartstudios_bot`, Instagram `@martstudiosbr`, MCC Google `1455071541`, tagline do site, stack Easypanel/OpenClaw). IDs Meta `act_`, fee comercial e número WhatsApp ficaram `[A CONFIRMAR]`.
- Resultado / aprendizado: P1.2 deixa de ser “opcional via bot”; bot só completa gaps pontuais.
- Fonte: site martstudiosbr.com.br; docs DEPLOY/PLANO-P1; memória Google Ads MCP; contexto sessão VPS.

### 2026-07-20 — seed operacional P1.2 (baseline)
- Contexto: pasta criada; estrutura 4 arquivos + INDEX.
- Fonte: setup vibestack-openclaw

### 2026-07 — Telegram só no OpenClaw (P1.4)
- Contexto: double-poll Hermes × Diretor no mesmo bot.
- Decisão: Hermes Telegram off; `@chatmartstudios_bot` → Diretor.
- Fonte: docs/PLANO-P1.md / TELEGRAM-SETUP.md
