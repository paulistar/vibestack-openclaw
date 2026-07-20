# Clientes — contexto de contas (agente `cliente`)

Memória de clientes da agência: arquivos em `clients/` + agente OpenClaw **`cliente`**. Fluxo **Telegram-first**: você manda fatos no chat; o agente **organiza e grava** em `clients/<slug>/`. Não edite markdown à mão.

O **Diretor** spawna o `cliente` para **ler** (antes de especialistas) e para **escrever** (cliente novo / atualização), e pede validação depois das entregas.

Templates no repo: [`clients/`](../clients/) · prompts: [`agency/cliente/`](../agency/cliente/).

## Estrutura

```
clients/
  INDEX.md                 # tabela de slugs
  _template/               # modelo para novos clientes
  <slug>/
    PROFILE.md             # quem é, ICP, objetivos, IDs
    brand.md               # tom, visual, claims
    offers.md              # ofertas ativas / o que não vender
    history.md             # decisões e aprendizados
```

No container OpenClaw a cópia viva fica em:

`/root/.openclaw/workspace/clients/`

(o bootstrap copia seeds/templates do repo; o agente `cliente` grava atualizações no volume.)

## Como usar no Telegram (passo a passo)

Fale com o bot do **Diretor**.

1. **Cliente novo** — mande o que tiver (texto solto ok):
   ```
   Temos um cliente novo: Acme Brasil (slug acme-brasil).
   Segmento: SaaS B2B. Site: https://acme.example
   Contato: Ana (WhatsApp).
   ICP: donos de e-commerce 50–200k/mês. Dor: CAC alto.
   Tom: direto, sem hype. Evita: “garantido”, “milagre”.
   Oferta: Setup Meta Ads R$ 2.500 + fee 15%. CTA: agendar call.
   ```
2. O Diretor spawna o `cliente`, que cria `clients/acme-brasil/` a partir do `_template`, preenche os 4 arquivos, atualiza `INDEX.md` e responde o que **salvou** + **TODO/ambíguo**.
3. **Mais info** (incremental) — continue no mesmo chat:
   ```
   Mais info acme-brasil: Meta Ad Account 1234567890.
   Call de hoje: querem leads de demo, CPA alvo R$ 80.
   Não vender: white-label.
   ```
   O `cliente` faz **merge** (atualiza seções + append em `history.md`).
4. **Consulta / campanha** — use o slug; o Diretor lê via `cliente` antes dos especialistas:
   ```
   Pro cliente acme-brasil, me diga o ICP e o tom (consulte o agente cliente).
   ```

### Exemplos extras

- `Cliente difrare: peça ao cliente o briefing e depois ao analista um resumo das campanhas Meta (só leitura).`
- `Gere 3 copies para mart-studios na oferta X — consulte o cliente antes e valide a entrega contra a brand.`
- `O criativo abaixo foge da marca difrare? Peça validação ao agente cliente.`

O Diretor deve:

1. Novo/update → `sessions_spawn` → `agentId: 'cliente'` (**escrever**)
2. Tarefa existente → `sessions_spawn` → `cliente` (**ler**)
3. Especialistas (se necessário)
4. `sessions_spawn` → `cliente` de novo (validação de peça)
5. Responder a você em texto

**Não** coloque tokens, senhas ou chaves de API nos arquivos de cliente.

## Cadastro manual (opcional / seed no repo)

Só se precisar versionar um seed no git. No dia a dia use o Telegram.

```bash
cp -R clients/_template clients/meu-cliente
# edite PROFILE.md, brand.md, offers.md, history.md
# atualize clients/INDEX.md
```

Sincronize seeds para a VPS (não sobrescreve history só do volume se você cuidar do merge):

```bash
docker cp clients openclaw-vibestack-wa:/tmp/clients
docker exec openclaw-vibestack-wa bash -c \
  'mkdir -p /root/.openclaw/workspace/clients && \
   cp -a /tmp/clients/. /root/.openclaw/workspace/clients/ && \
   chmod -R u+rwX /root/.openclaw/workspace/clients'
```

Ou rode de novo o `scripts/bootstrap-agency-openclaw.sh` (sincroniza `CLIENTS_SRC` → workspace e garante write em `clients/`).

## Bootstrap / atualizar prompts

```bash
cd /opt/agenciamart-ia/vibestack-openclaw
set -a && source .env && set +a

docker cp scripts/bootstrap-agency-openclaw.sh openclaw-vibestack-wa:/tmp/bootstrap-agency-openclaw.sh
docker cp agency openclaw-vibestack-wa:/tmp/agency
docker cp clients openclaw-vibestack-wa:/tmp/clients

docker exec \
  -e APIPROMAX_BASE_URL -e APIPROMAX_GPT_API_KEY -e APIPROMAX_DEFAULT_MODEL \
  -e TELEGRAM_BOT_TOKEN -e TELEGRAM_ALLOWED_USERS \
  -e AGENCY_SRC=/tmp/agency \
  -e CLIENTS_SRC=/tmp/clients \
  openclaw-vibestack-wa bash /tmp/bootstrap-agency-openclaw.sh

# Só OpenClaw — NÃO reinicie o Evolution
docker restart openclaw-vibestack-wa
```

Validar:

```bash
docker exec openclaw-vibestack-wa openclaw agents list
# deve listar: diretor, cliente, analista, estrategista, copywriter, criativo, gestor

docker exec openclaw-vibestack-wa ls -la /root/.openclaw/workspace/clients
docker exec openclaw-vibestack-wa bash -c \
  'touch /root/.openclaw/workspace/clients/.write-test && rm -f /root/.openclaw/workspace/clients/.write-test && echo WRITE_OK'
docker exec openclaw-vibestack-wa ls -la /root/.openclaw/workspace/cliente/clients
```

## Relação com a agência multi-agente

Ver também [AGENCY-MULTIAGENT.md](./AGENCY-MULTIAGENT.md). Fluxo:

```
Você (Telegram) → Diretor → Cliente (lê|escreve) → (ok) → especialistas → Cliente valida → Diretor
```
