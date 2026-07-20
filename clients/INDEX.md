# Clientes — índice

Pasta canônica de contexto de contas. Cada cliente vive em `clients/<slug>/`.

| slug | Nome | Status | Notas |
|------|------|--------|-------|
| `mart-studios` | Mart Studios | seed / TODO | Preencher PROFILE e brand com dados reais |
| `difrare` | Difrare | seed / TODO | Preencher PROFILE e brand com dados reais |

## Como adicionar

1. Copie `clients/_template/` para `clients/<slug>/` (ou duplique um seed e limpe).
2. Preencha `PROFILE.md`, `brand.md`, `offers.md`, `history.md`.
3. Atualize esta tabela.
4. No volume OpenClaw (VPS): sincronize para `/root/.openclaw/workspace/clients/` (ver `docs/CLIENTES.md`).

## Regras

- **Slug** = minúsculas, hífen, sem acento (`mart-studios`, não `Mart Studios`).
- Arquivos são a **fonte da verdade**. O agente `cliente` não inventa fatos.
- Segredos (tokens, senhas) **não** entram aqui — só contexto de marca/ICP/oferta.
