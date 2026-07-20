# Clientes — contexto de contas (agente `cliente`)

Memória de clientes da agência: arquivos em `clients/` + agente OpenClaw **`cliente`**. O **Diretor** consulta o `cliente` **antes** de spawnar analista/estrategista/copywriter/criativo/gestor em tarefa de cliente, e pede validação depois das entregas.

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

(o bootstrap copia do repo para o volume.)

## Como cadastrar um cliente novo

1. No repo (ou direto no volume):
   ```bash
   cp -R clients/_template clients/meu-cliente
   # edite PROFILE.md, brand.md, offers.md, history.md
   # atualize clients/INDEX.md
   ```
2. Sincronize para a VPS (se editou no repo):
   ```bash
   # no host VPS, com o repo atualizado
   docker cp clients openclaw-vibestack-wa:/tmp/clients
   docker exec openclaw-vibestack-wa bash -c \
     'mkdir -p /root/.openclaw/workspace/clients && \
      cp -a /tmp/clients/. /root/.openclaw/workspace/clients/'
   ```
   Ou rode de novo o `scripts/bootstrap-agency-openclaw.sh` (ele sincroniza `CLIENTS_SRC` → workspace).
3. Teste no Telegram pedindo contexto desse slug (exemplo abaixo).

**Não** coloque tokens, senhas ou chaves de API nos arquivos de cliente.

## Como pedir no Telegram

Fale com o bot do **Diretor**. Exemplos:

- `Pro cliente mart-studios, me diga o ICP e o tom de voz (consulte o agente cliente).`
- `Cliente difrare: peça ao cliente o briefing e depois ao analista um resumo das campanhas Meta (só leitura).`
- `Gere 3 copies para mart-studios na oferta X — consulte o cliente antes e valide a entrega contra a brand.`
- `O criativo abaixo foge da marca difrare? Peça validação ao agente cliente.`

O Diretor deve:

1. `sessions_spawn` → `agentId: 'cliente'` (contexto)
2. Especialistas (se necessário)
3. `sessions_spawn` → `cliente` de novo (validação de peça)
4. Responder a você em texto

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
docker exec openclaw-vibestack-wa ls /root/.openclaw/workspace/clients
```

## Relação com a agência multi-agente

Ver também [AGENCY-MULTIAGENT.md](./AGENCY-MULTIAGENT.md). Fluxo:

```
Você → Diretor → Cliente → (ok) → especialistas → Cliente valida → Diretor
```
