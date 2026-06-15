# vibestack-openclaw

Stack Docker self-hosted de uma **agência de tráfego com IA**: o [OpenClaw](https://github.com/openclaw/openclaw) com Ollama embutido, agentes especializados (gestor, criativo, analista…) e middleware MCP customizado que dá a eles **Meta Ads**, **geração de imagem/vídeo** e um **canal de WhatsApp** (recebe e responde, inclusive imagem e áudio). Pronta pra subir numa VPS (Hetzner, DigitalOcean, AWS Lightsail — qualquer host com Docker) e acessar do laptop via SSH tunnel — ou rodar localmente no Mac/Windows.

> **Novo por aqui?** Vá direto pra [Instalação rápida](#instalação-rápida-linux--mac--windows) (script `install.sh` que pergunta tudo e builda) ou siga o [Tutorial completo do zero](#tutorial-completo-do-zero) passo a passo. Cada integração (Meta Ads, B2, WhatsApp, Higgsfield, AtlasCloud) é **opcional** — preencha só o que for usar.

**O que você ganha rodando isso:**
- Um gateway OpenClaw acessível em `http://127.0.0.1:18789` (direto no Mac/Windows; via tunnel SSH na VPS).
- Modelos locais no mesmo container — escolha **Ollama** e/ou **LM Studio** no instalador (`llama3.2:3b`, `qwen2.5:7b`, etc.) sem dependência de API paga.
- 70 tools MCP pra Meta Ads (campanhas, ad sets, ads, creatives, insights, catálogos, datasets/pixels, product sets/items/feeds, **custom audiences**, **lookalikes**, **duplicação de campanhas/adsets/ads**) — agente cria/edita/lê/duplica/segmenta direto. 60 via CLI oficial + 10 via Graph API direta (audience/copies, que a CLI não cobre).
- **Canal de WhatsApp** (Evolution Go): o agente **recebe e responde** mensagens — inclusive interpreta **imagem e áudio** (se o modelo do agente for multimodal). Veja [WhatsApp (Evolution Go)](#whatsapp-evolution-go).
- **Geração de mídia** para o Criativo: **Higgsfield** (CLI envelopado em MCP — imagem/vídeo/soul-id) e **AtlasCloud** (MCP oficial, hub de 300+ modelos). Veja [Geração de mídia & hub de modelos](#geração-de-mídia--hub-de-modelos).
- Bloco demarcado no `Dockerfile` pra "bakear" suas próprias CLIs/binários (gog, goplaces, wacli já vêm de exemplo).
- **Hermes Agent** (NousResearch) no mesmo container como alternativa ao OpenClaw — API OpenAI-compatible em `http://127.0.0.1:8642/v1`, com acesso aos **mesmos** MCP servers (meta-ads, media-editor, whatsapp, higgsfield, atlascloud). Veja [Hermes Agent](#hermes-agent-alternativa-ao-openclaw).

---

## Sumário

- [Arquitetura em uma frase](#arquitetura-em-uma-frase)
- [Pré-requisitos](#pré-requisitos)
- [Instalação rápida (Linux / Mac / Windows)](#instalação-rápida-linux--mac--windows)
- [Tutorial completo do zero](#tutorial-completo-do-zero)
  - [Passo 1 — Provisionar a VPS](#passo-1--provisionar-a-vps)
  - [Passo 2 — SSH e setup inicial do servidor](#passo-2--ssh-e-setup-inicial-do-servidor)
  - [Passo 3 — Instalar Docker](#passo-3--instalar-docker)
  - [Passo 4 — Clonar o projeto](#passo-4--clonar-o-projeto)
  - [Passo 5 — (Opcional) Gerar o token da Meta Ads](#passo-5--opcional-gerar-o-token-da-meta-ads)
  - [Passo 6 — Configurar `.env`](#passo-6--configurar-env)
  - [Passo 7 — Build + Up](#passo-7--build--up)
  - [Passo 8 — Configurar o OpenClaw (uma vez por VPS)](#passo-8--configurar-o-openclaw-uma-vez-por-vps)
  - [Passo 9 — Confirmar MCP registrado](#passo-9--confirmar-mcp-registrado)
  - [Passo 10 — SSH tunnel do laptop](#passo-10--ssh-tunnel-do-laptop)
  - [Passo 11 — Abrir a UI e criar o primeiro agente](#passo-11--abrir-a-ui-e-criar-o-primeiro-agente)
  - [Passo 12 — Smoke test do MCP Meta Ads](#passo-12--smoke-test-do-mcp-meta-ads)
  - [Passo 13 — (Opcional) Habilitar subagentes](#passo-13--opcional-habilitar-subagentes)
  - [Passo 14 — (Opcional) Disparar cadeia de agentes via cron](#passo-14--opcional-disparar-cadeia-de-agentes-via-cron)
- [Atualizar o projeto na VPS](#atualizar-o-projeto-na-vps)
- [Backends de modelos locais (Ollama / LM Studio)](#backends-de-modelos-locais-ollama--lm-studio)
- [Hermes Agent (alternativa ao OpenClaw)](#hermes-agent-alternativa-ao-openclaw)
- [WhatsApp (Evolution Go)](#whatsapp-evolution-go)
- [Geração de mídia & hub de modelos (Higgsfield + AtlasCloud)](#geração-de-mídia--hub-de-modelos)
- [Referência técnica](#referência-técnica)
- [Troubleshooting](#troubleshooting)
- [Referências](#referências)

---

## Arquitetura em uma frase

Um container Docker (`openclaw-vibestack`) que roda **(a)** o gateway do OpenClaw na porta 18789 (loopback), **(b)** o backend de modelos locais que você escolheu instalar — **Ollama** (11434) e/ou **LM Studio** (1234), iniciado automaticamente no boot, **(c)** MCP servers compartilhados pelos agentes — middlewares Python (`meta-ads`, `media-editor`, `whatsapp`, `higgsfield`) + o MCP oficial `atlascloud` (npm), e **(d)** o **Hermes Agent** na 8642/9119 — alternativa ao OpenClaw com as mesmas tools. Ao lado, dois serviços irmãos no compose dão o canal de WhatsApp: **Evolution Go** (whatsmeow) na 8080 + **Postgres**. Tudo em **portas separadas**, coexistindo sem conflito.

| Serviço            | Porta (loopback) | Processo / serviço                       |
|--------------------|------------------|------------------------------------------|
| OpenClaw gateway   | 18789            | `openclaw gateway` (principal)           |
| Ollama             | 11434            | `ollama serve` (se instalado; sobe no boot) |
| LM Studio          | 1234             | `lms server` OpenAI-compat (se instalado; sobe no boot) |
| Hermes API server  | 8642             | `hermes gateway` (api_server)            |
| Hermes dashboard   | 9119             | `hermes dashboard` (UI gestão/chat)      |
| Evolution Go       | 8080             | WhatsApp API (whatsmeow) — serviço       |
| Postgres           | (interno)        | banco do Evolution Go                    |

O entrypoint registra o MCP automaticamente no boot via `openclaw mcp set`, propagando `ACCESS_TOKEN`/`AD_ACCOUNT_ID` pro processo filho.

---

## Pré-requisitos

- Uma VPS Linux (recomendado Ubuntu 22.04+ ou Debian 12+).
  - **RAM**: 4GB mínimo (2GB faz build do openclaw cair com OOM). 8GB+ confortável se for rodar Ollama com modelo grande.
  - **Disco**: 20GB+ (imagem ~3GB, modelos do Ollama 2–8GB cada).
- SSH key configurada no seu laptop pra acessar a VPS sem senha.
- (Opcional, pra Meta Ads) Conta no Meta Business Manager com permissão de admin.

> Esse tutorial assume Hetzner CX22 (CPX21 ainda melhor). Funciona em qualquer outro provider — só ajuste o IP no exemplo.

---

## Instalação rápida (Linux / Mac / Windows)

Há **duas formas de instalar**. As duas chegam no mesmo resultado (imagem buildada + `.env` pronto + diretórios de dados criados). A diferença é **quem faz o trabalho**: o instalador (automático) ou você (manual). Escolha conforme o quanto quer entender/controlar cada etapa.

**Pré-requisito comum:** Docker rodando (Docker Desktop no Mac/Windows, Docker Engine no Linux/VPS). No Docker Desktop, reserve **memória suficiente** — o build do OpenClaw é pesado e cai com OOM (`exit 137` / `cannot allocate memory`) abaixo de ~8 GB. Ajuste em *Docker Desktop → Settings → Resources → Memory* (12 GB é confortável). Veja [Troubleshooting](#build-cai-com-exit-137).

---

### Forma 1 — Instalador automático (`install.sh`)

O `install.sh` é **idempotente** (pode rodar de novo sem quebrar nada) e cuida de tudo. Em detalhe, ele:

1. **Verifica/instala o Docker** — no Linux instala via `get.docker.com`; no Mac/Windows detecta e aponta o download do Docker Desktop.
2. **Resolve os diretórios de dados pelo seu SO** — usa `~/.openclaw`, `~/.ollama` e `~/.hermes`. No Docker Desktop (Mac/Windows) isso funciona sem mexer no File Sharing; na VPS (`HOME=/root`) resolve pro mesmo `/root/.openclaw` de sempre. **É isso que evita o erro** `mounts denied: the path /root/.openclaw is not shared from the host`.
3. **Cria/atualiza o `.env`** — copia de `.env.example` se faltar, **pergunta os valores no terminal** (porta, Meta Ads, B2…) na primeira vez, e grava os data dirs resolvidos no passo 2. Não sobrescreve valores que você já preencheu.
4. **Gera os segredos** (se vazios) — `OPENCLAW_GATEWAY_TOKEN`, `GOG_KEYRING_PASSWORD` e `HERMES_API_SERVER_KEY`. Ao final, **exibe as chaves geradas**, dizendo onde ficam (no `.env`) e onde usar cada uma (ex.: a `HERMES_API_SERVER_KEY` é o Bearer token pra conectar um frontend na API do Hermes).
5. **Cria os diretórios de dados** físicos (`mkdir -p`) no host.
6. **Normaliza o `entrypoint.sh` pra LF** — evita o erro `entrypoint not found` em checkouts feitos no Windows.
7. **Builda a imagem** (`docker compose build`) e **para antes do `up`** — você sobe a stack manualmente.

> **⚠️ Windows: rode no Git Bash ou WSL — não no PowerShell/CMD.** O `install.sh` é um script **bash**; no PowerShell/CMD o `curl ... | bash` e o `./install.sh` **não funcionam** (lá `curl` é alias de `Invoke-WebRequest` e não existe `bash`). **O comando é o mesmo do Mac/Linux** — só precisa do terminal certo. Passo a passo no Windows:
>
> 1. **Instale o Git for Windows** (traz o **Git Bash**). No PowerShell: `winget install --id Git.Git -e` — ou baixe em https://git-scm.com/download/win. *(Alternativa: WSL, com `wsl --install` no PowerShell como administrador.)*
> 2. Deixe o **Docker Desktop aberto** (se usar WSL, ative *Settings → Resources → WSL integration*).
> 3. Abra o **Git Bash** (menu Iniciar → "Git Bash") e **cole o mesmo comando abaixo** — roda idêntico ao Mac/Linux.

Duas maneiras de chamá-lo:

**1a — direto da web (o instalador clona o repo sozinho):**

No terminal (Mac/Linux: terminal normal; Windows: **Git Bash ou WSL**, não PowerShell/CMD):

```bash
curl -fsSL https://raw.githubusercontent.com/ericorenato/vibestack-openclaw/main/install.sh | bash
```

Ele clona o repo em `./vibestack-openclaw` (mude o destino com `OPENCLAW_DIR=/caminho`) e se re-executa de lá. Mesmo vindo de um `curl | bash`, lê suas respostas do terminal (`/dev/tty`). Requer o repositório **público**. Como ele cria um `.env` novo, você vai **digitar os tokens da Meta/B2 do zero**.

**1b — clonando você mesmo (reaproveita um `.env` já existente):**

No Windows, rode em **Git Bash ou WSL** (não PowerShell/CMD):

```bash
git clone https://github.com/ericorenato/vibestack-openclaw.git
cd vibestack-openclaw
./install.sh
```

Rodar o `./install.sh` numa pasta que **já tem** `.env` é a forma de **consertar** um `.env` herdado da VPS (com `OPENCLAW_DATA_DIR=/root/.openclaw`) — ele reescreve os data dirs pros caminhos do seu SO e preserva seus tokens.

Depois de qualquer uma das duas, **de dentro da pasta do projeto**:

```bash
docker compose up -d
```

> **Modo não-interativo (CI / sem terminal):** exporte `NONINTERACTIVE=1` e o `.env` é criado só com defaults + segredos gerados (preencha Meta Ads / B2 editando o arquivo depois).

---

### Forma 2 — Instalação manual (você cria as pastas e o `.env`)

Pra quem quer controle total ou entender cada parte. Faz exatamente o que o instalador faz, mas na mão. **No Mac/Windows os caminhos são no seu `$HOME`; na VPS são em `/root`** — não use `/root/...` no Mac, senão dá `mounts denied`.

> **Windows:** os comandos abaixo (`git`, `mkdir -p`, `openssl`, `cp`, `tr`) são de shell **bash** — rode no **Git Bash** ou **WSL**, não no PowerShell/CMD.

```bash
# 1. Clone o repo e entre nele
git clone https://github.com/ericorenato/vibestack-openclaw.git
cd vibestack-openclaw

# 2. Crie os diretórios de dados (volumes persistentes) no SEU SO.
#    Mac/Windows:
mkdir -p ~/.openclaw ~/.ollama ~/.hermes
#    VPS (HOME=/root) — pule, ja' e' /root/.openclaw etc. (ou: mkdir -p /root/.openclaw /root/.ollama /root/.hermes)

# 3. Crie o .env a partir do exemplo
cp .env.example .env

# 4. Gere os 3 segredos (rode 3x e cole cada um no .env)
openssl rand -hex 32    # -> OPENCLAW_GATEWAY_TOKEN
openssl rand -hex 32    # -> GOG_KEYRING_PASSWORD
openssl rand -hex 32    # -> HERMES_API_SERVER_KEY
```

Agora **edite o `.env`** e ajuste:

- **Data dirs (CRÍTICO no Mac)** — aponte pros caminhos que você criou no passo 2:
  ```
  OPENCLAW_DATA_DIR=/Users/SEU_USUARIO/.openclaw
  OLLAMA_DATA_DIR=/Users/SEU_USUARIO/.ollama
  HERMES_DATA_DIR=/Users/SEU_USUARIO/.hermes
  ```
  (Na VPS: `/root/.openclaw`, `/root/.ollama`, `/root/.hermes`.) Se deixar `/root/...` no Mac, o `docker compose up` falha com `mounts denied: the path /root/.hermes is not shared from the host`.
- **Segredos** — cole os 3 valores gerados no passo 4 em `OPENCLAW_GATEWAY_TOKEN`, `GOG_KEYRING_PASSWORD` e `HERMES_API_SERVER_KEY`.
- **Meta Ads / B2 (opcional)** — preencha `META_ACCESS_TOKEN` (+ `META_AD_ACCOUNT_ID`) e os `B2_*` se for usar as tools de Meta Ads / media-editor. Veja [Passo 5](#passo-5--opcional-gerar-o-token-da-meta-ads) e [Passo 6](#passo-6--configurar-env).

```bash
# 5. (Só Windows) normalize o entrypoint pra LF, se editou em editor Windows:
#    tr -d '\r' < entrypoint.sh > entrypoint.lf && mv entrypoint.lf entrypoint.sh

# 6. Builde a imagem
docker compose build

# 7. Suba a stack
docker compose up -d
```

**Onde usar cada segredo depois de subir:**

| Segredo                  | Onde usar                                                                 |
|--------------------------|---------------------------------------------------------------------------|
| `OPENCLAW_GATEWAY_TOKEN` | Login do gateway OpenClaw (UI em `:18789`).                               |
| `HERMES_API_SERVER_KEY`  | API key / Bearer token pra conectar o **frontend** na API do Hermes (`http://127.0.0.1:8642/v1`). |
| `GOG_KEYRING_PASSWORD`   | Uso interno (keyring do `gog` no container) — não vai em frontend.        |

---

Depois do `up` (em qualquer das duas formas), siga o [Passo 8](#passo-8--configurar-o-openclaw-uma-vez-por-vps) (configurar OpenClaw) em diante, e a seção [Hermes Agent](#hermes-agent-alternativa-ao-openclaw) pra configurar o provider do Hermes. Se preferir entender cada etapa na mão, o tutorial abaixo cobre tudo passo a passo.

---

## Tutorial completo do zero

### Passo 1 — Provisionar a VPS

Cria uma VPS Ubuntu 22.04 no provider da sua escolha. Anote o IP público (vamos chamar de `YOUR_VPS_IP`).

Na Hetzner Cloud:
1. Console → **Add Server**.
2. Location: próxima de você (Nuremberg/Helsinki/Ashburn).
3. Image: **Ubuntu 22.04**.
4. Type: **CX22** (mínimo) ou **CPX21** (recomendado).
5. SSH Keys: marque sua chave pública (cria nova se não tiver).
6. **Create & Buy now**.

### Passo 2 — SSH e setup inicial do servidor

Do seu laptop:

```bash
ssh root@YOUR_VPS_IP
```

Dentro da VPS:

```bash
apt-get update && apt-get upgrade -y
apt-get install -y git curl ca-certificates nano
```

### Passo 3 — Instalar Docker

```bash
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
```

Espera ver versão do Docker e do compose plugin. Se `docker compose version` reclamar, instale o plugin:

```bash
apt-get install -y docker-compose-plugin
```

### Passo 4 — Clonar o projeto

```bash
cd ~
git clone https://github.com/ericorenato/vibestack-openclaw.git
cd vibestack-openclaw
```

> Substitua a URL pelo fork seu se for o caso.

### Passo 5 — (Opcional) Gerar o token da Meta Ads

**Pule esse passo se NÃO for usar o MCP da Meta Ads.** Vai poder usar o OpenClaw + Ollama normalmente, sem as 60 tools da Meta.

Siga o [guia oficial Meta Ads CLI / Primeiros passos](https://developers.facebook.com/documentation/ads-commerce/ads-ai-connectors/ads-cli/setup/get-started). Resumo:

1. **Criar Meta Developer App** em https://developers.facebook.com/apps → **Create App** → tipo **Business** → adicionar produto **Marketing API**.
2. **Adicionar o App ao seu Business Manager**: Business Suite → Configurações → Contas → Apps → **Adicionar**.
3. **Criar System User**: Business Suite → Configurações → Usuários → **Usuários do Sistema** → Adicionar. Função: **Administrador**. Nome sugerido: "vibestack-openclaw".
4. **Atribuir ativos** ao system user (botão **Atribuir ativos**):
   - Contas de anúncios — papel mínimo **Anunciante** (Admin recomendado pra criar/editar via MCP).
   - Páginas comerciais — pra criativos.
   - Catálogos — se for usar ads de catálogo/DPA.
   - Datasets/Pixels — pra tracking de conversão.
5. **Adicionar o system user como Admin do App**: Meta for Developers → seu App → Configurações → **Funções** → **Funções** → Adicionar Administradores → escolhe o system user.
   - **Sem esse passo, o token sai mas sem permissão pra falar pelo App.**
6. **Gerar token**: Business Suite → Usuários do Sistema → seu user → **Gerar novo token** → escolhe seu App → marca os 7 escopos:
   - `business_management`
   - `ads_management` ← libera write (criar campanha, ad set, ad)
   - `pages_show_list`
   - `pages_read_engagement`
   - `pages_manage_ads`
   - `catalog_management`
   - `read_insights`

   **Copia o token agora.** System User Tokens não expiram.
7. **Anote o ID da ad account principal**: Ads Manager → menu superior → Configurações → ID é o número depois de `act_` na URL.

### Passo 6 — Configurar `.env`

```bash
cp .env.example .env
nano .env
```

Preencha **no mínimo**:

```env
# Gere com: openssl rand -hex 32
OPENCLAW_GATEWAY_TOKEN=<resultado-do-openssl>
GOG_KEYRING_PASSWORD=<outro-resultado-do-openssl>

# Só preenche se fez o Passo 5
META_ACCESS_TOKEN=EAA...
META_AD_ACCOUNT_ID=act_123456789   # ou só 123456789 — o entrypoint adiciona o 'act_' se faltar
```

Os outros valores no `.env.example` já têm defaults sensatos. Pra gerar segredos:

```bash
openssl rand -hex 32   # roda uma vez pro gateway token
openssl rand -hex 32   # roda outra pro keyring password
```

### Passo 7 — Build + Up

> Atalho: `./install.sh` já faz o `mkdir` dos diretórios de dados e o `docker compose build` (parando antes do `up`). Se rodou o instalador, pule direto pro `docker compose up -d`.

```bash
mkdir -p /root/.openclaw /root/.ollama   # dispensável se usou ./install.sh

docker compose build
docker compose up -d
docker compose logs -f openclaw-vibestack
```

O build leva ~5-10min na primeira vez (pnpm install do openclaw + uv install da meta-ads + backend de modelos local escolhido). Espera o log estabilizar — você deve ver (a linha do backend varia conforme o que você instalou):

```
[start-ollama] ollama pronto (pid=NN, porta 11434)
[entrypoint] mcp 'meta-ads' registrado
```

Sai do log com `Ctrl+C` (container continua rodando).

### Passo 8 — Configurar o OpenClaw (uma vez por VPS)

O OpenClaw exige um wizard inicial pra criar `openclaw.json`. **Esse passo é interativo**:

```bash
docker compose exec openclaw-vibestack openclaw configure
```

Responde as perguntas (auth mode, modelo default, etc.). Detalhes em https://docs.openclaw.ai.

Depois do wizard, **reinicia o container** pra que o entrypoint registre o MCP:

```bash
docker compose up -d --force-recreate openclaw-vibestack
```

### Passo 9 — Confirmar MCP registrado

```bash
docker compose logs openclaw-vibestack | grep -iE "mcp|registrado"
```

Espera ver os servers registrados — entre eles `[entrypoint] mcp 'meta-ads' registrado`, e também `media-editor`, `whatsapp`, `higgsfield` e `atlascloud`. Avisos comuns e o que fazer:

- `AVISO: ACCESS_TOKEN vazio` → preencha `META_ACCESS_TOKEN` (Passo 6).
- `AVISO: ATLASCLOUD_API_KEY vazio` → preencha `ATLASCLOUD_API_KEY` no `.env` (o MCP `atlascloud` sobe, mas falha auth até preencher).
- Higgsfield: o MCP sobe sem credencial — a auth é por login (veja [Geração de mídia](#geração-de-mídia--hub-de-modelos)); confira com `docker compose exec openclaw-vibestack higgsfield auth status`.

Pra listar tudo de uma vez (deve mostrar `meta-ads`, `media-editor`, `whatsapp`, `higgsfield` e `atlascloud`):

```bash
docker compose exec openclaw-vibestack openclaw mcp list
```

Ou inspecionar a config gravada de um server específico:

```bash
docker compose exec openclaw-vibestack cat /root/.openclaw/openclaw.json | grep -A8 meta-ads
```

Deve mostrar `command`, `args` e o objeto `env` de cada server (ex.: `meta-ads` com `ACCESS_TOKEN`/`AD_ACCOUNT_ID`/`BUSINESS_ID`; `atlascloud` com `ATLASCLOUD_API_KEY`; `higgsfield` com `HOME`).

### Passo 10 — SSH tunnel do laptop

A porta 18789 do gateway é publicada **apenas em loopback** (`127.0.0.1`) na VPS — não está exposta na internet. Você acessa via tunnel SSH do laptop:

```bash
# No laptop (não na VPS):
ssh -N -L 18789:127.0.0.1:18789 root@YOUR_VPS_IP
```

Deixa esse terminal aberto. Em outro terminal, opcionalmente também tunela o Ollama:

```bash
ssh -N -L 11434:127.0.0.1:11434 root@YOUR_VPS_IP
```

Se o tunnel não conectar, verifica no `/etc/ssh/sshd_config` da VPS:

```
AllowTcpForwarding yes
```

E `systemctl restart ssh` se mudou.

### Passo 11 — Abrir a UI e criar o primeiro agente

No browser do laptop:

```
http://127.0.0.1:18789
```

Cole o `OPENCLAW_GATEWAY_TOKEN` do `.env` quando pedir.

Na UI:
1. **Models** → confirma se aparece a opção Ollama (URL default `http://127.0.0.1:11434`). Se quiser usar API paga (Anthropic/OpenAI), adiciona aqui também.
2. **MCP Servers** → você já deve ver `meta-ads` listado com ~70 tools. Se não aparecer, repete o Passo 9.
3. **Agents** → **New Agent** → escolhe o model, marca o MCP `meta-ads` como disponível, dá nome ("AdsOps", por exemplo), e descreve o que ele faz no system prompt.

Exemplo de system prompt pro agente de Meta Ads:

```
Você é um operador de Meta Ads. Cria campanhas SEMPRE em PAUSED.
Antes de criar qualquer estrutura, lista o estado atual (list_campaigns,
list_ad_sets) e confirma com o usuário. Para insights, prefira janelas
last_7d a last_30d. Usa output_format='json' por default; se algum tool
voltar parse_error, retenta com output_format='plain'.
```

### Passo 12 — Smoke test do MCP Meta Ads

Conversa com o agente que você acabou de criar:

> Liste as campanhas da minha ad account principal.

Espera receber JSON com nome, ID, status, objetivo, budget. Se sim, está tudo no ar.

Outros testes úteis pra confiança:

```
Mostra a ad account ativa.
Pega os insights da última semana agrupados por campanha.
Lista minhas custom audiences.
Duplica o ad set <ID> com sufixo "-copy-test" em PAUSED.
```

> Duplicações nascem em `status="PAUSED"` por default — pode testar sem medo de gastar dinheiro.

Comandos diretos no container pra debug:

```bash
docker compose exec openclaw-vibestack meta auth status
docker compose exec openclaw-vibestack meta --output json ads campaign list
```

### Passo 13 — (Opcional) Habilitar subagentes

**Pule esse passo se você só vai operar com um agente único.** Esse passo libera o padrão de subagentes — um agente delega trabalho a outro via `sessions_spawn`, que é **bloqueante** e devolve o resultado como tool-result no mesmo turno do pai. É o que viabiliza fluxos como "atendimento delega análise pro analista, recebe os dados, sintetiza".

Por padrão o OpenClaw bloqueia spawn cruzado (`agentId is not allowed for sessions_spawn`). O comando abaixo destrava.

Todos os comandos rodam dentro do container:

```bash
docker compose exec -it openclaw-vibestack bash
```

**1. Habilita subagentes e allowlist de spawn cruzado**

```bash
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.subagents.allowAgents '["*"]'
openclaw config set agents.defaults.subagents.announceTimeoutMs 300000
```

O que cada chave faz:

- **`maxSpawnDepth: 2`** — permite orquestrador (atendimento spawna analista, que pode spawnar trabalhador). Deixe em `1` se não precisar de aninhamento.
- **`allowAgents: ["*"]`** — qualquer agente pode spawnar qualquer outro. É a chave que destrava `agentId is not allowed for sessions_spawn`.
- **`announceTimeoutMs: 300000`** — 5min de janela pra entrega do resultado do filho ao pai. Sobe se você espera tarefas longas.

**2. Cria os agentes adicionais em `agents.list`**

Cada agente é uma entrada em `agents.list` do `openclaw.json`. Exemplo mínimo do `analista`:

```json
{
  "id": "analista",
  "name": "Analista",
  "workspace": "/root/.openclaw/workspace/analista",
  "agentDir": "/root/.openclaw/agents/analista/agent"
}
```

Os agentes herdam tudo de `agents.defaults` — model, `workspace` base, e o bloco `subagents` que você setou no item 1. O catálogo de tools vem do `tools.profile` global (`"coding"` neste repo) — esse perfil já expõe as tools básicas + as tools de qualquer MCP registrado, então **você não precisa configurar `tools.alsoAllow` por agente** pra que o analista use `meta-ads__*`.

O `openclaw.json` deste repo traz um exemplo funcional com `atendimento` + `analista` nesse formato mínimo. Use como referência.

> `sessions_spawn` vem implícita do bloco `subagents` — o modelo a chama com `runtime: 'subagent'`, `agentId: '<destino>'`, `task: '<descrição>'`, e o turno do pai bloqueia até o filho retornar com o tool-result.
>
> `sessions_yield` **não existe** nesse build do OpenClaw (confirmado por grep no source). Não instrua o modelo a chamá-la — seria no-op e fecharia o turno antes do filho responder.

**3. Reinicia o gateway**

```bash
openclaw gateway restart
```

**4. Valida**

```bash
openclaw config get agents.defaults.subagents
openclaw config get agents.list
```

A primeira saída deve mostrar `maxSpawnDepth: 2`, `allowAgents: ["*"]`, `announceTimeoutMs: 300000`. A segunda deve listar `main` + seus agentes adicionais.

Depois disso, no chat do agente orquestrador (ex: `atendimento`), você pode pedir coisas como:

> Delegue ao analista listar minhas campanhas Meta Ads e me traga uma análise crítica.

E o orquestrador vai chamar `sessions_spawn(runtime: 'subagent', agentId: 'analista', task: '...')`, aguardar o tool-result no mesmo turno e sintetizar.

### Passo 14 — (Opcional) Disparar cadeia de agentes via cron

O OpenClaw inclui um scheduler interno (`openclaw cron`) que dispara mensagens pra agentes em horários ou intervalos. Combinado com o padrão de subagentes do Passo 13, dá pra orquestrar fluxos automáticos sem nenhum trigger externo — ex: atendimento delega análise pro analista, que consulta o MCP Meta Ads, e o atendimento sintetiza, tudo dentro de um único turno bloqueante.

**Exemplo funcional: atendimento → analista (com MCP Meta Ads)**

```bash
docker compose exec openclaw-vibestack openclaw cron add \
  --name "Cadeia atendimento→analista" \
  --at "30s" \
  --tz "America/Sao_Paulo" \
  --session isolated \
  --agent atendimento \
  --delete-after-run \
  --message "Você executa em UM ÚNICO turno bloqueante.

ETAPA 1 — Delegue ao Analista

Chame sessions_spawn com:
  runtime: 'subagent'
  agentId: 'analista'
  task: 'Use meta-ads para listar campanhas. Retorne tabela Markdown com colunas: ID, Nome, Status, Spend, Impressions, Clicks, Conversions.'

IMPORTANTE:
- sessions_spawn é BLOQUEANTE neste runtime
- Retorna o resultado do Analista como tool-result no mesmo turno
- NÃO chame sessions_yield (não existe nesta versão)
- Aguarde o tool-result antes de prosseguir

ETAPA 2 — Ainda no mesmo turno, processe o resultado

Sintetize:

## Resumo do que o Analista entregou
[2 linhas]

## Análise crítica
- Melhor campanha: [nome — motivo]
- Pior campanha: [nome — hipótese]
- Saturação detectada: [sim/não, onde]

## Recomendações (sem executar)
1. [ação]
2. [ação]
3. [ação]"
```

Pontos críticos do comando:

- **`--session isolated`** — obrigatório quando `--agent` aponta pra um agente que não é o `main`. O CLI rejeita `--session main` nesse caso com `sessionTarget "main" is only valid for the default agent`.
- **`--agent atendimento`** — quem recebe a mensagem. Esse é o orquestrador que vai spawnar o subagente.
- **`--delete-after-run`** — remove o job depois de uma execução. Use `--keep-after-run` se quiser deixar persistido (vira `idle` no `cron list` depois de rodar — comportamento esperado).
- **`sessions_spawn` é bloqueante** — não chame `sessions_yield` (não existe nesse build). O turno do pai aguarda o tool-result do spawn dentro do mesmo turno; tentar "ceder" o turno faz o pai morrer antes do filho anunciar e dispara `Subagent announce give up` nos logs.

**Listar e remover jobs:**

```bash
docker compose exec openclaw-vibestack openclaw cron list
docker compose exec openclaw-vibestack openclaw cron rm <jobId>
```

Jobs persistem em `/root/.openclaw/cron/jobs.json` — sobrevivem a `docker compose down`/restart por causa do volume do Passo 7.

---

## Atualizar o projeto na VPS

```bash
cd ~/vibestack-openclaw
git pull
docker compose build
docker compose up -d --force-recreate openclaw-vibestack
```

(O `docker compose build` só é necessário se o `Dockerfile` ou a pasta `middleware/` mudaram.)

Pra atualizar a versão do openclaw upstream, edita no `.env`:

```env
OPENCLAW_REF=v1.2.3   # tag, branch ou commit
```

E rebuild com `--no-cache`:

```bash
docker compose build --no-cache
docker compose up -d
```

---

## Backends de modelos locais (Ollama / LM Studio)

O `./install.sh` pergunta **qual backend instalar** dentro do container — **Ollama**, **LM Studio** ou **os dois**. Só o escolhido é baixado na imagem (build args `INSTALL_OLLAMA` / `INSTALL_LMSTUDIO` no `.env`). **O que for instalado sobe sozinho no boot** (o entrypoint detecta e inicia). Adicionar o outro depois = rodar o `./install.sh` de novo e refazer o `docker compose build`.

Diagnóstico e (re)start manual (idempotentes):

```bash
docker compose exec openclaw-vibestack models-status
docker compose exec openclaw-vibestack start-ollama
docker compose exec openclaw-vibestack start-lmstudio
```

### Ollama

```bash
docker compose exec openclaw-vibestack ollama pull llama3.2:3b
docker compose exec openclaw-vibestack ollama pull qwen2.5:7b
docker compose exec openclaw-vibestack ollama list
```

Modelos ficam em `/root/.ollama` no host (volume), persistem entre rebuilds. Sugestões por tamanho:
- **3GB RAM**: `llama3.2:3b`, `phi3:mini`
- **8GB RAM**: `qwen2.5:7b`, `mistral:7b`
- **16GB+**: `qwen2.5:14b`, `llama3.1:8b-instruct`

### LM Studio

Server OpenAI-compatível em `http://127.0.0.1:1234/v1`. O `lms` é um binário grande (~750 MB) que se materializa no primeiro uso; o build já faz esse bootstrap, mas se o server não responder logo após subir o container, espere 1-2 min ou rode `docker compose exec openclaw-vibestack start-lmstudio` de novo (é idempotente).

Baixe (do Hugging Face) e carregue um modelo:

```bash
docker compose exec openclaw-vibestack lms get qwen2.5-7b-instruct
docker compose exec openclaw-vibestack lms load qwen2.5-7b-instruct --yes
docker compose exec openclaw-vibestack lms ls
```

Modelos ficam em `/root/.lmstudio/models` no host (volume `LMSTUDIO_DATA_DIR`), persistem entre rebuilds.

**Wirar como provider dos agentes:**
- **OpenClaw** — adicione o bloco `lmstudio` em `models.providers` no `openclaw.json` (base URL `http://127.0.0.1:1234/v1`, `api: openai`, `apiKey: lm-studio`), trocando o `id`/`name` do modelo pelo que `lms ls` mostrar. (Há um exemplo pronto comentado no `openclaw.json` da raiz.)
- **Hermes** — `docker compose exec -it openclaw-vibestack hermes model` e aponte a base URL `http://127.0.0.1:1234/v1`.

---

## Hermes Agent (alternativa ao OpenClaw)

O [Hermes Agent](https://github.com/NousResearch/hermes-agent) da NousResearch vem
**baked no mesmo container** como uma alternativa ao OpenClaw. Ele é clonado do git no
build (pinado por `HERMES_REF`, igual ao OpenClaw), instalado num venv Python 3.11
com o extra `[all]` (browser/Playwright, mcp, messaging, etc.), e **compartilha os mesmos
MCP servers** que o OpenClaw — `meta-ads`, `media-editor`, `whatsapp` e `higgsfield` (mesmos
scripts em `/app/middleware`, mesmo venv) + `atlascloud` (MCP oficial via npm).

Ele expõe **duas portas separadas**, ambas coexistindo com OpenClaw (18789) e Ollama (11434):

- **8642 — `api_server`**: uma **API OpenAI-compatible** (`/v1/chat/completions`, `/v1/models`,
  `/health`). **Não é uma página de navegador** — é pra conectar frontends/clientes.
- **9119 — `hermes dashboard`**: o **dashboard web** (UI React de gestão/chat). **Esta é a "página web"**
  do Hermes — abre no navegador.

### O que o entrypoint faz no boot

1. **Registra as tools** fazendo um merge idempotente em `${HERMES_DATA_DIR}/config.yaml`
   sob a chave `mcp_servers` (preservando qualquer outra config que você editar). Sem
   filtro de `tools`, o Hermes habilita todas as tools de cada server.
2. **Sobe o `hermes gateway`** em background. A única plataforma que sobe sem token é o
   `api_server` (OpenAI-compatible), que **exige `HERMES_API_SERVER_KEY`** pra iniciar.
3. **Sobe o `hermes dashboard`** em background, **bindado em loopback** (`127.0.0.1:9120`)
   e publicado via **socat** em `9119`. O bind loopback é
   obrigatório: o dashboard tem defesas de DNS-rebinding/Origin no WebSocket que rejeitam
   a aba Chat quando o bind é `0.0.0.0`; em loopback o WS é tratado como confiável e o
   socat (TCP-puro) leva o WebSocket transparente até a porta publicada. Sobe com `--tui`,
   que **habilita a aba "Chat"** (o `ui-tui` já vem pré-buildado na imagem).

> O provider/modelo **não** é configurado pelo build (decisão de projeto). Igual ao
> OpenClaw, você configura depois — veja abaixo.

### Configurar o provider/modelo (uma vez)

```bash
# Wizard interativo de modelo/provider:
docker compose exec -it openclaw-vibestack hermes model

# ...ou edite direto o config.yaml (persiste no volume ${HERMES_DATA_DIR}):
#   ${HERMES_DATA_DIR}/config.yaml  -> chave model: { provider, default }
```

Providers suportados incluem OpenRouter, Anthropic, Nous Portal, Ollama local
(`http://127.0.0.1:11434`), e outros — escolha no wizard. Enquanto não houver provider,
o api_server sobe mas as completions falham.

### Acessar a API

A porta 8642 é publicada **apenas em loopback** na VPS. Do laptop:

```bash
ssh -N -L 8642:127.0.0.1:8642 root@YOUR_VPS_IP
```

```bash
# Health check (sem auth):
curl http://127.0.0.1:8642/health

# Listar modelos / chat (Bearer = HERMES_API_SERVER_KEY do .env):
curl http://127.0.0.1:8642/v1/models \
  -H "Authorization: Bearer $HERMES_API_SERVER_KEY"
```

Qualquer frontend OpenAI-compatible (Open WebUI, LobeChat, etc.) conecta apontando pra
`http://127.0.0.1:8642/v1` com a `HERMES_API_SERVER_KEY` como API key. O modelo exposto
chama-se `hermes-agent`.

### Acessar o dashboard web (a "página web")

O `hermes dashboard` roda na **9119**, publicado **apenas em loopback** no host.

- **No Mac/Windows (local):** abra direto no navegador:
  ```
  http://127.0.0.1:9119
  ```
- **Na VPS:** túnel SSH do laptop e depois abra no navegador:
  ```bash
  ssh -N -L 9119:127.0.0.1:9119 root@YOUR_VPS_IP
  # depois: http://127.0.0.1:9119
  ```

Como o dashboard sobe bindado em loopback (e publicado via socat), o WebSocket da aba Chat
é tratado como confiável e a página usa o token embutido — **não pede login**. Você gerencia
config, providers, env e conversa com o agente na aba **Chat**. Logs:
`docker compose exec openclaw-vibestack tail -f /var/log/hermes-web.log` (servidor) e
`/var/log/hermes-web-socat.log` (bridge).

> Se a aba Chat der **"WebSocket connection failed"**, quase sempre é bind `0.0.0.0` (a
> defesa de DNS-rebind/Origin do dashboard rejeita o WS) — o entrypoint contorna bindando
> em `127.0.0.1:9120` + socat pra `9119`. Se vier 404/tela em branco, o build da UI pode
> não ter rodado; confira o log do servidor.

### Confirmar as tools registradas

Lista os MCP servers do Hermes (deve mostrar `meta-ads`, `media-editor`, `whatsapp`, `higgsfield`, `atlascloud`):

```bash
docker compose exec openclaw-vibestack hermes mcp list
```

Ver o boot do gateway no log:

```bash
docker compose logs openclaw-vibestack | grep hermes
```

---

## WhatsApp (Evolution Go)

O canal de WhatsApp usa o [**Evolution Go**](https://github.com/evolution-foundation/evolution-go)
— uma API em Go baseada em **`whatsmeow`** (o mesmo protocolo WhatsApp Web; **não usa Baileys**).
Roda como **serviço separado** no `docker-compose` (imagem `evoapicloud/evolution-go`), com um
**Postgres** ao lado. Os agentes (OpenClaw e Hermes) enviam mensagens pelo middleware MCP
`whatsapp` (`middleware/whatsapp_evolution_mcp.py`), que fala com a API pelo DNS do compose
(`http://evolution-go:8080`) — por isso **não precisa de URL pública**.

**Canal completo (inbound + outbound):** além do envio, há um **bridge** inbound
(`middleware/whatsapp_bridge.py`) que fecha o ciclo — você conversa com o agente pelo WhatsApp:

```
WhatsApp → Evolution Go (evento "Message") --webhook--> bridge (porta 8765, interna)
        → agente escolhido (Hermes api_server  OU  openclaw agent), sessão por número
        → Evolution Go (/send/text) → WhatsApp
```

O `evolution-go` posta os eventos no `WEBHOOK_URL=http://openclaw-vibestack:8765/webhook`
(DNS do compose, automático). O bridge filtra mensagens **recebidas** (ignora as
suas próprias, grupos e status), mantém **uma sessão Hermes por contato** (`X-Hermes-Session-Id`),
responde 200 na hora (o agente pode demorar com tool calls) e processa em background.

**Mídia recebida (imagem e áudio).** O bridge também processa **imagem** e **áudio** enviados pelo WhatsApp:

1. Baixa os bytes na ordem **`mediaUrl` (S3/MinIO presigned)** → **`base64` inline** → **`POST /message/downloadmedia`** (on-demand; funciona mesmo sem S3).
2. Salva em `/root/.openclaw/workspace/_shared/assets/wa/` (persistente).
3. Manda pro modelo do agente:
   - **Hermes** → conteúdo multimodal OpenAI (`image_url` para imagem, `input_audio` para áudio).
   - **OpenClaw** → passa o caminho do arquivo salvo + legenda no prompt (o agente interpreta com suas tools).
4. **Se o modelo configurado não aceitar a modalidade** (não é de visão/áudio), o bridge responde avisando que *"o modelo configurado neste agente não interpreta imagens/áudios"* — em vez de erro cru. Como o modelo **varia por agente**, isso depende do que você plugou no Hermes/OpenClaw.

Vídeo/documento ainda não são interpretados (o bridge avisa). Legenda de imagem é usada como prompt. Para o caminho via **S3/Backblaze**, ligue o storage do Evolution (veja abaixo); sem isso, o download on-demand cobre tudo.

> **Quem responde (escolha do aluno):** `WA_BRIDGE_AGENT=hermes|openclaw`.
> - `hermes` → HTTP no api_server (`/v1/chat/completions`, sessão por número).
> - `openclaw` → CLI `openclaw agent --message ... --to +<número> --json` (sessão por número; `WA_BRIDGE_OPENCLAW_AGENT` opcional escolhe o binding). Não usa `--deliver` — o bridge é quem envia pelo Evolution.
>
> Troque o agente no `.env` e reinicie. O `WA_BRIDGE_ALLOWED_NUMBERS` (CSV; **vazio = qualquer um**)
> restringe quem pode falar com o agente — recomendado preencher.

**Auth (confirmado no código do Evolution):** header `apikey`. A `EVOLUTION_API_KEY` (global) é
de admin (criar instância); cada instância tem seu próprio token (`EVOLUTION_INSTANCE_TOKEN`,
definido no create) usado em envio/QR/status.

### Storage de mídia recebida (opcional — S3 / Backblaze)

O Evolution Go pode subir a mídia recebida num bucket **S3/MinIO** e mandar a `mediaUrl` (link presigned) no webhook — aí o bridge baixa de lá. É **opcional**: sem isso, a mídia já vem como **base64 inline** no webhook (o compose deixa `WEBHOOK_FILES=true`), então funciona out-of-the-box; ligar o S3 só deixa o payload mais enxuto e guarda uma cópia no seu bucket. Use a variável `MINIO_*` do Evolution (o `install.sh` pergunta isso e deixa reusar as credenciais do Backblaze B2):

```
EVOLUTION_MINIO_ENABLED=true
EVOLUTION_MINIO_ENDPOINT=s3.us-west-002.backblazeb2.com   # host SEM https://
EVOLUTION_MINIO_ACCESS_KEY=<B2_KEY_ID>
EVOLUTION_MINIO_SECRET_KEY=<B2_APP_KEY>
EVOLUTION_MINIO_BUCKET=<bucket>
EVOLUTION_MINIO_REGION=us-west-002
EVOLUTION_MINIO_USE_SSL=true
```

O compose mapeia isso pras vars que o Evolution Go lê (`MINIO_ENABLED/ENDPOINT/ACCESS_KEY/SECRET_KEY/BUCKET/USE_SSL/REGION` + `WEBHOOK_FILES`). Quando ligado, a mídia recebida fica também no seu bucket (URLs presigned válidas ~7 dias).

### Subir e parear (uma vez)

Sobe os três serviços (openclaw-vibestack + evolution-go + postgres):

```bash
docker compose up -d
```

1. **Ativar a licença** (o Evolution responde `503` até ativar) no Manager:
   ```bash
   # VPS: ssh -N -L 8080:127.0.0.1:8080 root@YOUR_VPS_IP
   # abra http://127.0.0.1:8080/manager/login  (API key = EVOLUTION_API_KEY)
   ```
2. **Criar a instância e parear** — pelo agente (tools MCP) ou pelo Manager:
   - `wa_create_instance` → cria a instância com o `EVOLUTION_INSTANCE_TOKEN`.
   - `wa_get_qr` → mostra o QR; escaneie no celular (WhatsApp → Aparelhos conectados).
   - `wa_instance_status` → quando = `connected`, está pronto.
3. **Enviar** (qualquer agente): `wa_send_text(number="5511999999999", text="oi")`.
4. **Conversar (inbound):** com a instância pareada, mande uma mensagem do seu WhatsApp pro
   número conectado — o bridge entrega ao Hermes e responde. Restrinja quem pode falar via
   `WA_BRIDGE_ALLOWED_NUMBERS` no `.env`. Log do bridge:
   `docker compose exec openclaw-vibestack tail -f /var/log/whatsapp-bridge.log`.

⚠️ A licença do Evolution Go usa **heartbeats** (precisa de internet de saída); não é 100% offline.

---

## Geração de mídia & hub de modelos

São **opcionais** — habilite se quiser que o agente **Criativo** gere imagem/vídeo. Há dois caminhos, com **modelos de auth diferentes** (cada um pelo que a plataforma oferece). Pode usar um, outro, ou os dois.

### Higgsfield (CLI + MCP) — auth por navegador (1x)

O Higgsfield não tem MCP oficial funcional, então a imagem instala o **CLI** (`@higgsfield/cli`) e o expõe via um middleware MCP próprio (`higgsfield_cli_mcp.py`): tools `generate_image`, `generate_video`, `soul_id_create`, `upload`, etc.

A autenticação é **OAuth no navegador** (não tem API key). Por isso você loga **uma vez** e o token persiste num volume (`${HIGGSFIELD_DATA_DIR}` → `/root/.higgsfield`) — sobrevive a restart/rebuild.

Login (uma vez; abre uma URL/código pra logar no navegador):

```bash
docker compose exec openclaw-vibestack higgsfield auth login
```

Conferir o status quando quiser:

```bash
docker compose exec openclaw-vibestack higgsfield auth status
```

Tokens são curtos: **só refaça o login quando `auth status` acusar expiração** — não a cada restart, graças ao volume. Mídia gerada cai em `/root/.openclaw/workspace/_shared/assets/` (persistente). Para gerar sempre com um **rosto fixo** (ex.: uma pessoa da marca), treine um `soul_id` uma vez a partir de uma seed em `seeds/image/` (no Backblaze B2) e reuse — veja `agency/criativo/AGENTS.md`.

### AtlasCloud (MCP oficial) — auth por API key (env)

Hub de 300+ modelos (imagem/vídeo/LLM). Aqui usamos o **MCP server oficial** (`atlascloud-mcp`, instalado na imagem) — não há CLI/wrapper a manter. Auth é **só por API key via env**, sem login nem volume: a chave no `.env` já sobrevive a restart.

1. Pegue a key em https://www.atlascloud.ai/console/api-keys.
2. Preencha `ATLASCLOUD_API_KEY=...` no `.env` (ou responda a pergunta do `install.sh`).
3. Recrie o container pra propagar a env:

```bash
docker compose up -d --force-recreate openclaw-vibestack
```

Pronto — `atlascloud` aparece em `openclaw mcp list` (e no Hermes). Por que API key e não login interativo? É o modelo mais automático para container: stateless, zero passos manuais, recupera sozinho após restart — mesmo padrão de `META_ACCESS_TOKEN` / `B2_*`.

---

## Referência técnica

### Estrutura do repo

```
.
├── Dockerfile               # node:24 + openclaw + ollama + meta-ads CLI + middleware + hermes
├── entrypoint.sh            # ollama serve + openclaw mcp set + hermes gateway/dashboard + exec CMD
├── docker-compose.yml       # openclaw-vibestack + evolution-go + postgres (env, volumes, portas)
├── middleware/
│   ├── meta_ads_cli_mcp.py        # MCP — 70 tools Meta Ads (CLI + Graph API)
│   ├── media_editor_mcp.py        # MCP — ffmpeg + Backblaze B2
│   ├── higgsfield_cli_mcp.py      # MCP — Higgsfield CLI (geração imagem/vídeo, soul-id)
│   ├── whatsapp_evolution_mcp.py  # MCP — envio WhatsApp via Evolution Go (whatsmeow)
│   ├── whatsapp_bridge.py         # bridge inbound: webhook Evolution -> Hermes -> resposta
│   └── requirements.txt
├── postgres/
│   └── init-evolution-dbs.sql     # cria evogo_auth / evogo_users no 1o boot
├── .env.example
└── README.md
```

### MCP servers registrados (o que cada agente ganha)

O `entrypoint.sh` registra estes MCP servers no boot (no OpenClaw via `openclaw mcp set` e no Hermes via merge no `config.yaml`). Cada um é **opcional** — sobe sempre, mas só funciona quando você preenche a credencial correspondente no `.env`. Confira com `docker compose exec openclaw-vibestack openclaw mcp list`.

| MCP server   | O que dá ao agente                                                   | Como é instalado                                                        | Auth (no `.env`)                          | Documentação |
|--------------|----------------------------------------------------------------------|-------------------------------------------------------------------------|-------------------------------------------|--------------|
| `meta-ads`   | 70 tools de Meta Ads (campanhas, ad sets, ads, creatives, insights, catálogos, pixels, custom audiences, lookalikes, duplicação) | middleware Python (`meta_ads_cli_mcp.py`) envelopando a CLI oficial `meta` | `META_ACCESS_TOKEN` (+ `META_AD_ACCOUNT_ID`) | [Tools do MCP Meta Ads](#tools-do-mcp-meta-ads) |
| `media-editor` | Edição de mídia com **ffmpeg** (cortar, redimensionar, overlay, trilha, validar p/ Meta) + **Backblaze B2** como storage de seeds/derivações | middleware Python (`media_editor_mcp.py`) + `ffmpeg` na imagem            | `B2_KEY_ID` / `B2_APP_KEY` / `B2_BUCKET` / `B2_ENDPOINT_URL` | [Tools do MCP media-editor](#tools-do-mcp-media-editor-ffmpeg--backblaze-b2) |
| `whatsapp`   | Enviar texto/mídia e gerir a instância (QR/status) via Evolution Go  | middleware Python (`whatsapp_evolution_mcp.py`)                          | `EVOLUTION_API_KEY` / `EVOLUTION_INSTANCE_TOKEN` | [WhatsApp (Evolution Go)](#whatsapp-evolution-go) |
| `higgsfield` | Gerar **imagem/vídeo** e treinar **soul-id** (rosto fiel)            | middleware Python (`higgsfield_cli_mcp.py`) envelopando o CLI `@higgsfield/cli` (instalado na imagem) | login no navegador 1x (token em volume `${HIGGSFIELD_DATA_DIR}`) | [Geração de mídia](#geração-de-mídia--hub-de-modelos) |
| `atlascloud` | Hub de **300+ modelos** (imagem/vídeo/LLM)                           | MCP server **oficial** `atlascloud-mcp` (npm, instalado na imagem)      | `ATLASCLOUD_API_KEY`                      | [Geração de mídia](#geração-de-mídia--hub-de-modelos) |

> Inbound de WhatsApp (receber mensagens, inclusive imagem/áudio) é o `whatsapp_bridge.py` — não é um MCP, é um serviço que o entrypoint sobe. Veja [WhatsApp (Evolution Go)](#whatsapp-evolution-go).

### Componentes "bakeados" na imagem

Além dos MCP servers acima, o `Dockerfile` instala na imagem (tudo num container só):

- **OpenClaw** (gateway + UI, porta 18789) — agente principal, clonado e buildado do upstream.
- **Hermes Agent** (NousResearch) — alternativa ao OpenClaw (API OpenAI-compatible 8642 + dashboard 9119), com os mesmos MCP servers. Veja [Hermes Agent](#hermes-agent-alternativa-ao-openclaw).
- **Ollama** (porta 11434) — roda modelos locais (`llama3.2`, `qwen2.5`, etc.) sem API paga. **Não é MCP**: é o provedor de modelo que os agentes podem usar. Veja [Baixar modelos no Ollama](#baixar-modelos-no-ollama).
- **CLIs/SDKs**: `meta` (Meta Ads, PyPI), `@higgsfield/cli`, `atlascloud-mcp`, `ffmpeg`, `boto3` (B2), e os binários de exemplo `gog`/`goplaces`/`wacli`.
- **Evolution Go** + **Postgres** — serviços irmãos no compose (não na mesma imagem) que dão o canal de WhatsApp.

Pra adicionar os seus, veja [Adicionar uma CLI nova à imagem](#adicionar-uma-cli-nova-à-imagem) e [Adicionar um MCP server novo](#adicionar-um-mcp-server-novo).

### Tools do MCP Meta Ads

70 tools no total: 60 envelopando a CLI oficial `meta-ads` + 10 chamando direto a Graph API (Custom Audiences + duplicação de entidades — a CLI v1.0.1 não cobre nenhum dos dois).

- **Ad Accounts**: `list_ad_accounts`, `get_ad_account`, `current_ad_account`
- **Campaigns**: `list_campaigns`, `get_campaign`, `create_campaign`, `update_campaign`, `pause_campaign`, `resume_campaign`, `archive_campaign`, `delete_campaign`
- **Ad Sets**: `list_ad_sets`, `get_ad_set`, `create_ad_set`, `update_ad_set`, `pause_ad_set`, `resume_ad_set`, `delete_ad_set`
- **Ads**: `list_ads`, `get_ad`, `create_ad`, `update_ad`, `pause_ad`, `resume_ad`, `delete_ad`
- **Creatives**: `list_creatives`, `get_creative`, `create_creative`, `create_creative_dco`, `update_creative`, `delete_creative`
- **Insights**: `get_insights` (date_preset, since/until, breakdown, fields, filtros)
- **Catalogs**: `list_catalogs`, `get_catalog`, `create_catalog`, `update_catalog`, `delete_catalog`
- **Pages**: `list_pages`, `get_page`
- **Datasets/Pixels**: `list_datasets`, `get_dataset`, `create_dataset`, `connect_dataset`, `disconnect_dataset`, `assign_user_to_dataset`
- **Product Sets**: `list_product_sets`, `get_product_set`, `create_product_set`, `update_product_set`, `delete_product_set`
- **Product Items**: `list_product_items`, `get_product_item`, `create_product_item`, `update_product_item`, `delete_product_item`
- **Product Feeds**: `list_product_feeds`, `get_product_feed`, `create_product_feed`, `update_product_feed`, `delete_product_feed`
- **Custom Audiences** (Graph API direta, não passa pela CLI): `list_custom_audiences`, `get_custom_audience`, `create_custom_audience`, `create_lookalike_audience`, `add_users_to_audience`, `remove_users_from_audience`, `delete_custom_audience`
- **Duplicação** (Graph API direta — endpoint `/copies`): `duplicate_campaign`, `duplicate_ad_set`, `duplicate_ad`. Default `status_option="PAUSED"` + `deep_copy=True`. Aceita `new_name` (renomeia depois de duplicar) ou `rename_suffix` (Meta acrescenta sufixo numa única chamada).

Todas as tools que envelopam a CLI aceitam `output_format` (`json` default | `table` | `plain` | `none`). Todos os `create_*` e `duplicate_*` partem com `status="paused"` / `status_option="PAUSED"` por segurança. As tools de audience hasham email/phone localmente em SHA256 antes de enviar (Meta exige PII hasheada) — use `already_hashed=True` se a lista já vier pronta.

### Tools do MCP media-editor (ffmpeg + Backblaze B2)

O MCP `media-editor` (`middleware/media_editor_mcp.py`) é o **editor de imagem/vídeo do agente Criativo**. Toda mídia (seeds e derivações) vive no **Backblaze B2** — as tools recebem e devolvem **chaves B2 puras** (sem `b2://`), nos prefixos `inbox/`, `seeds/`, `work/`, `final/`, `requests/`, `meta/`. As transformações usam **ffmpeg** dentro do container e são **idempotentes**: sem `output_key` a saída é derivada de `hash(input + params)` em `work/<slug>/...`, então re-rodar a mesma operação devolve `was_cached=true` sem reprocessar. Requer os `B2_*` no `.env`.

**Seeds & inbox (descoberta de mídia-base):**
- `list_seeds(kind=None)` — lista mídia-base já classificada (`image`/`video`/`audio`).
- `request_human_media(slug, instructions, deadline_iso)` — registra um pedido de gravação humana em `requests/`.
- `list_inbox(prefix="")` / `claim_inbox_item(inbox_key, seed_kind, seed_slug)` — vê uploads humanos pendentes e os promove de `inbox/` → `seeds/<kind>/<slug>`.
- `b2_list(prefix, max_keys=100)`, `b2_get_info(key)`, `b2_upload_local(local_path, key)`, `b2_delete(key)` — utilitários crus de bucket.

**Imagem:**
- `image_fit(input_key, width, height, mode="cover", output_format=None, output_key=None)` — redimensiona/recorta. `mode`: `cover` (padrão), `contain` (padding), `crop`, `stretch`. Ex.: 1:1 → `width=1080, height=1080`; 9:16 → `1080x1920`.
- `image_overlay(input_key, kind, position="center", text=..., overlay_key=..., font_size=48, font_color="white", box=True, scale_pct=100)` — sobrepõe **texto** (`kind="text"`) ou **logo/imagem** (`kind="image"`).

**Vídeo (encadeie na ordem):**
- `video_trim` (cortar início/fim) → `video_fit` (enquadrar WxH) → `video_overlay` (legenda/logo) → `video_audio` (trilha) → `video_loop` / `video_speed` quando precisar.
- Auxiliares: `video_concat` (juntar clipes), `video_transcode` (codec/bitrate), `video_extract_frame` (tira um frame como seed-imagem).

**Validar & finalizar:**
- `probe(key, validate_for=None)` — inspeciona dimensões/duração/codecs. `validate_for`: `meta_image_feed` | `meta_image_story` | `meta_video_feed` | `meta_video_reels` → retorna `valid=true/false` + violações.
- `finalize_for_meta(b2_key, slug, description)` — **único caminho que materializa o arquivo local**: baixa do B2 e grava em `/root/.openclaw/workspace/_shared/creatives/` (persistente), devolvendo `path`, `width`/`height`, `duration_seconds`, `valid_for_meta`. Esse `path` é o que o **Gestor** passa pro `create_creative` do MCP `meta-ads`.

**Exemplo (criativo de imagem 1:1 com legenda), como o Criativo encadearia:**

```text
list_seeds(kind="image")                              -> acha seeds/image/produto.jpg
image_fit("seeds/image/produto.jpg", 1080, 1080)      -> work/.../fit.jpg
image_overlay(<fit>, kind="text", text="50% OFF",
              position="bottom", box=True)            -> work/.../overlay.jpg
probe(<overlay>, validate_for="meta_image_feed")      -> {"valid": true, ...}
finalize_for_meta(<overlay>, "promo-julho",
                  "Banner 1:1 50% OFF")               -> {"path": ".../_shared/creatives/promo-julho-....jpg"}
```

Para gerar mídia **do zero** (em vez de transformar uma seed), use os MCPs [`higgsfield`/`atlascloud`](#geração-de-mídia--hub-de-modelos) e depois suba o resultado pro B2 com `b2_upload_local` para entrar nesse pipeline. Detalhes do papel do Criativo em `agency/criativo/AGENTS.md`.

### Convenções de segurança operacional do wrapper

- **Safe-by-default em writes**: todo `create_*` nasce em `paused`. Todo `duplicate_*` nasce em `PAUSED`. Pra ativar, o agente precisa chamar `resume_*` ou `update_*` explicitamente — não há atalho acidental pra produção.
- **Deletes obrigam `--force`**: não há prompt interativo no MCP, então o wrapper sempre passa `--force`. Quem chama `delete_*` está afirmando que tem certeza.
- **PII nunca trafega em claro**: `add_users_to_audience` / `remove_users_from_audience` aplicam SHA256 local. Mesmo se um log capturar a chamada de rede, não vaza email/phone original.
- **`act_` prefix normalizado**: `META_AD_ACCOUNT_ID` aceita com ou sem `act_`. O entrypoint adiciona se faltar — não dá pra quebrar a CLI por formato de ID.
- **Env explicitamente passado pro MCP child**: o `entrypoint.sh` declara `env` no `openclaw mcp set` em vez de confiar em propagação implícita. Sem isso a CLI da Meta retorna "No access token found" mesmo com env no container.
- **Saída JSON sanitizada**: `--no-color --no-input` em toda chamada da CLI evita ANSI sujando o `json.loads`. `"No results."` é normalizado pra `[]`. `current_ad_account` é sintetizado do env (a CLI não suporta JSON nesse subcomando).

### Arquitetura multi-agente recomendada (opcional)

> 📁 **Prompts prontos:** a pasta [`agency/`](agency/) traz os 6 agentes deste padrão como **templates** (com placeholders `{{...}}` pra você adaptar ao seu contexto). Veja o [`agency/README.md`](agency/README.md) pra instruções.

Esse MCP é o **executor** — quem realmente fala com a Meta. Mas pra operar tráfego pago com qualidade, vale ter agentes especializados em torno dele. Padrão sugerido (6 agentes, todos no mesmo OpenClaw):

| Agente | Trigger | Lê | Escreve | MCP? |
|---|---|---|---|---|
| **Coletor** | Cron (ex: 6x/dia) | — | `snapshots/{ts}.json` | ✅ list/get/insights |
| **Analista** | Cron (ex: 3x/dia) | `snapshots/` | `insights/{ts}.json` | ❌ |
| **Estrategista** | Evento `insights-ready` | `insights/`, `snapshots/`, `decisions/` | `recommendations/{ts}.json` | ❌ |
| **Aprovador** | Evento `recommendations-ready` | `recommendations/` | `decisions/approved\|rejected/{ts}.json` | ❌ (usa Telegram) |
| **Executor** | Evento `action-approved` | `decisions/approved/` | `executions/{ts}.json` | ✅ pause/update/duplicate |
| **Auditor** | Cron semanal | tudo | `audit/{week}.json` | ❌ |

Princípios:
- **Coletor é read-only**. Nunca chama write tool.
- **Estrategista propõe, humano aprova, Executor executa**. Apenas o Executor toca em mutating tools, e só com `authorization_token` válido vindo do Aprovador.
- **Catálogo restrito de ações**: o Executor só roda `pause_*`, `update_*` (budget), `duplicate_*`. Tudo fora disso é alerta pra humano.
- **Memory > prompt**: snapshots e decisões ficam em memory shared, não em system prompt do agente — sobrevive a restart, dá pra auditar.

Esse padrão não está hardcoded no MCP — é arquitetura que você compõe na UI do OpenClaw. O MCP só expõe as ferramentas; cada agente decide quando usa.

> Pra esse padrão funcionar (Estrategista delegar pro Executor, Analista invocar o Coletor, etc.) você precisa habilitar subagentes — veja [Passo 13](#passo-13--opcional-habilitar-subagentes). Sem isso, o OpenClaw bloqueia spawn cruzado com `agentId is not allowed for sessions_spawn`. Pra agendar disparos automáticos sem trigger externo, combine com o [Passo 14](#passo-14--opcional-disparar-cadeia-de-agentes-via-cron).

### Adicionar uma CLI nova à imagem

Edita o `Dockerfile`, localiza o bloco demarcado `BINÁRIOS CUSTOMIZADOS`, e adiciona:

```dockerfile
ARG MEUBIN_VERSION=1.0.0
RUN curl -fL "https://github.com/org/meubin/releases/download/v${MEUBIN_VERSION}/meubin_linux_amd64.tar.gz" \
       | tar -xzO meubin > /usr/local/bin/meubin \
 && chmod +x /usr/local/bin/meubin
```

Commit + push + na VPS: `git pull && docker compose build && docker compose up -d --force-recreate`.

### Adicionar um MCP server novo

1. Cria o servidor (Python/Node/Go — qualquer linguagem que fale o protocolo MCP) em `middleware/seu_mcp.py`.
2. Edita `entrypoint.sh`, no bloco "Registro de MCP servers", adiciona:

   ```sh
   register_mcp seu-server '{"command":"/caminho/binario","args":["arg1"],"env":{"VAR":"val"}}'
   ```

3. Commit, pull na VPS, `docker compose up -d --force-recreate`.

### Persistência

Sobrevivem a `docker compose down`/rebuild (cada um é um volume):

- `${OPENCLAW_DATA_DIR}` (default `/root/.openclaw`) → `/root/.openclaw` (auth profiles, `openclaw.json`, **workspace do agente** — tudo num mount só).
- `${OLLAMA_DATA_DIR}` (default `/root/.ollama`) → `/var/lib/ollama` (modelos baixados).
- `${HERMES_DATA_DIR}` (default `/root/.hermes`) → `/root/.hermes` (config.yaml, sessões, memórias).
- `${HIGGSFIELD_DATA_DIR}` (default `/root/.higgsfield`) → `/root/.higgsfield` (token do `higgsfield auth login`).
- `${EVOLUTION_DATA_DIR}` / `${POSTGRES_DATA_DIR}` → dados/sessão do WhatsApp.

**Onde os agentes devem gravar arquivos.** Só persiste o que está **dentro** desses volumes. Escrita em `/tmp`, `/app`, `/root` (fora de `.openclaw`/`.hermes`) ou no diretório atual é **efêmera** e some no `down`/rebuild — essa é a causa de "os arquivos sumiram". Diretórios persistentes canônicos para os agentes:

- `/root/.openclaw/workspace/<agente>/` — workspace por agente (já configurado em `openclaw.json`).
- `/root/.openclaw/workspace/_shared/assets/` — mídia baixada/gerada (ex.: pelo MCP `higgsfield`).
- `/root/.openclaw/workspace/_shared/creatives/` — criativos finalizados (`finalize_for_meta`).

O entrypoint cria `_shared/assets` e `_shared/creatives` no boot, e os `AGENTS.md` instruem os agentes a nunca gravar fora do workspace. **Storage canônico de longo prazo continua sendo o Backblaze B2** (sobrevive até à destruição do volume); o `_shared/` é cache local persistente entre restarts.

### CLI `openclaw` dentro do container

A imagem inclui wrapper em `/usr/local/bin/openclaw` que aponta pra `node /app/dist/index.js`:

```bash
docker compose exec openclaw-vibestack openclaw security audit
docker compose exec openclaw-vibestack openclaw mcp list
docker compose exec openclaw-vibestack openclaw --help
```

---

## Troubleshooting

### Build cai com `exit 137`

Falta de RAM. Aumenta swap (`fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`) ou sobe pra VPS com mais memória.

### `AllowTcpForwarding` bloqueado

```bash
sed -i 's/^#*AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

### Porta 18789 em uso na VPS

Outro processo escutando. Muda `OPENCLAW_GATEWAY_PORT` no `.env` e re-up.

### MCP `meta-ads` não aparece na UI

```bash
docker compose logs openclaw-vibestack | grep -iE "mcp|access_token"
```

Procura `AVISO: falha ao registrar mcp 'meta-ads'`. Se aparecer, o `openclaw.json` não existe (precisa rodar o Passo 8) ou o schema rejeitou o JSON.

### `meta auth status` diz `Not authenticated`

ACCESS_TOKEN não chegou no container. Confirma no `.env` que `META_ACCESS_TOKEN` está preenchido (sem aspas extras, sem espaços) e re-up com `--force-recreate`.

### Agente diz "Permissions error" ao criar campanha

O System User não tem papel "Anunciante" (ou superior) na ad account, OU o token foi gerado sem o escopo `ads_management`. Volta no Passo 5 itens 4 e 6.

### `pnpm install` falha por lockfile

Mudança no upstream. Troca `OPENCLAW_REF` no `.env` pra uma tag/commit conhecidamente bom e rebuild.

### `agentId is not allowed for sessions_spawn`

Spawn cruzado entre agentes está desabilitado por padrão. Rode o [Passo 13](#passo-13--opcional-habilitar-subagentes) — especificamente o `agents.defaults.subagents.allowAgents '["*"]'` e o restart do gateway.

### Agente não vê tools de MCP (ex: `meta-ads__*`) no catálogo

As tools de MCP são herdadas pelo agente via o perfil global `tools.profile` (este repo usa `"coding"`, que já expõe as tools básicas + MCP). Se o agente não vê:

1. Confirme que `tools.profile` no `openclaw.json` está em `"coding"` ou `"full"` — perfis menores não expõem MCP.
2. Confirme que o MCP está registrado: `docker compose exec openclaw-vibestack openclaw mcp list` deve listar `meta-ads`. Se não, refaça o Passo 9.
3. Cheque os logs do gateway por linhas `tool policy removed N tool(s)` — algum override per-agente pode estar derrubando tools sem querer.

### `Subagent announce give up (retry-limit)` no log do cron

O agente pai encerrou o turno antes do subagente devolver o resultado. Causa típica: o prompt instrui o modelo a chamar `sessions_yield` (essa tool **não existe** nesse build do OpenClaw — confirmado por grep no source). O pattern correto é deixar `sessions_spawn` bloqueando o turno até o tool-result chegar; veja o exemplo no [Passo 14](#passo-14--opcional-disparar-cadeia-de-agentes-via-cron).

### `cron: sessionTarget "main" is only valid for the default agent`

`openclaw cron add --agent <outro>` exige `--session isolated`. Só o agente default (`main`) aceita `--session main`. Reescreve o comando com `--session isolated`.

### `scope upgrade pending approval` / `pairing required: device is asking for more scopes`

Qualquer comando que fale com o gateway (`cron`, `config set`, `devices`, etc.) trava com algo assim:

```
gateway connect failed: GatewayClientRequestError: scope upgrade pending approval (requestId: <uuid>)
GatewayTransportError: gateway closed (1008): pairing required: device is asking for more scopes than currently approved
```

**Causa:** o seu device CLI está pareado com um conjunto de escopos (ex.: só `operator.write`), mas o comando que você rodou precisa de um escopo a mais (ex.: `operator.pairing`). O gateway não concede sozinho — ele abre um **pedido de upgrade pendente** e bloqueia as conexões até alguém aprovar.

**Como resolver:**

```bash
openclaw devices list                 # mostra o(s) pedido(s) pendente(s) e o requestId
openclaw devices approve <requestId>  # ou: openclaw devices approve --latest
```

Os avisos `gateway connect failed … Direct scope access failed; using local fallback` que aparecem durante o `approve` são esperados — é o CLI contornando o próprio bloqueio pra registrar a aprovação. Confirme com `openclaw devices list` (o pedido some e o device ganha o escopo novo) e refaça o comando original.

> Alternativa: aprovar pela UI do Control em `:18789` (o device admin, que já tem `operator.approvals`/`operator.pairing`).

### JSON malformado em algum tool

Já tem proteção: `--no-color --no-input` + normalização de `"No results."` → `[]` + `current_ad_account` sintético do env. Se ainda aparecer, o agente pode chamar a tool com `output_format="plain"` e a CLI manda texto cru (o agente parseia).

---

## Referências

- OpenClaw: https://github.com/openclaw/openclaw
- Docs OpenClaw: https://docs.openclaw.ai
- Meta Ads CLI (PyPI): https://pypi.org/project/meta-ads/
- Meta Ads CLI guia oficial: https://developers.facebook.com/documentation/ads-commerce/ads-ai-connectors/ads-cli
- Ollama: https://ollama.com
- MCP (Model Context Protocol): https://modelcontextprotocol.io
- Hermes Agent (NousResearch): https://github.com/NousResearch/hermes-agent
- Higgsfield CLI: https://higgsfield.ai/cli
- AtlasCloud (CLI/MCP, hub de modelos): https://www.atlascloud.ai/cli
- Evolution Go (WhatsApp API): https://github.com/EvolutionAPI/evolution-go
- Backblaze B2 (storage S3-compatible): https://www.backblaze.com/cloud-storage
