# Clientes — índice

Pasta canônica de contexto de contas. Cada cliente vive em `clients/<slug>/`.

| slug | Nome | Status | Notas |
|------|------|--------|-------|
| `mart-studios` | Mart Studios | seed / TODO | Preencher PROFILE e brand com dados reais |
| `difrare` | Difrare | seed / TODO | Preencher PROFILE e brand com dados reais |

## Como adicionar

**Preferido (Telegram):** diga ao Diretor “temos um cliente novo…” + fatos. O agente `cliente` cria a pasta a partir de `_template`, preenche os 4 arquivos e atualiza esta tabela. “Mais info: …” faz merge. Ver `docs/CLIENTES.md`.

**Manual / seed no repo** (opcional):

1. Copie `clients/_template/` para `clients/<slug>/`.
2. Preencha `PROFILE.md`, `brand.md`, `offers.md`, `history.md`.
3. Atualize esta tabela.
4. Sincronize o volume OpenClaw (VPS) — ver `docs/CLIENTES.md`.

## Regras

- **Slug** = minúsculas, hífen, sem acento (`mart-studios`, não `Mart Studios`).
- Arquivos são a **fonte da verdade**. O agente `cliente` não inventa fatos; grava só o que veio na mensagem.
- Segredos (tokens, senhas) **não** entram aqui — só contexto de marca/ICP/oferta.
