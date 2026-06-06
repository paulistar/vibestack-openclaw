# Curso prático: Hermes Agent (e como ele se compara ao OpenClaw)

> **Para quem é este material:** donos de negócio e gestores **sem experiência prévia em IA**. Você já configurou o OpenClaw nas aulas anteriores; aqui vamos nos aprofundar no **Hermes**, o "irmão" dele que roda no mesmo servidor. Tudo explicado em linguagem simples, com analogias, passo a passo e comandos prontos para copiar.

> **Onde rodar os comandos:** neste projeto o Hermes vive **dentro do container** `openclaw-vibestack`. Então, na prática, todo comando `hermes ...` deste guia você roda assim:
> ```bash
> docker compose exec -it openclaw-vibestack hermes <comando>
> ```
> Para encurtar, o guia escreve só `hermes <comando>` — lembre de prefixar com `docker compose exec -it openclaw-vibestack`.

---

## Sumário

1. [IA em 5 minutos (os 4 conceitos que bastam)](#1-ia-em-5-minutos)
2. [O que é o Hermes](#2-o-que-é-o-hermes)
3. [Hermes × OpenClaw: semelhanças e diferenças](#3-hermes--openclaw-semelhanças-e-diferenças)
4. [Primeiro contato: acessar e configurar o Hermes](#4-primeiro-contato)
5. [Os comandos da CLI do Hermes (mapa por categoria)](#5-os-comandos-da-cli)
6. [Como "criar agentes" no Hermes](#6-como-criar-agentes-no-hermes)
7. [O "organograma": como montar um time no Hermes](#7-o-organograma-como-montar-um-time)
8. [Transferir seus agentes do OpenClaw para o Hermes](#8-transferir-do-openclaw-para-o-hermes)
9. [Crons e "heartbeats": colocar o agente para trabalhar sozinho](#9-crons-e-heartbeats)
10. [O diferencial do Hermes: memória e skills](#10-memória-e-skills)
11. [Glossário e checklist](#11-glossário-e-checklist)
- [Apêndice A — Os 6 cargos da agência como profiles](#apêndice-a--os-6-cargos-da-agência-como-profiles-do-hermes)

---

## 1. IA em 5 minutos

Antes de tudo, quatro palavras que vão aparecer o tempo todo. Pense numa **empresa**:

| Termo | O que é (analogia de empresa) |
|---|---|
| **Modelo (LLM)** | O "cérebro" que pensa e escreve. Ex.: GPT, Claude, Llama. É como contratar um **funcionário inteligente** — uns são mais caros e espertos, outros mais baratos. |
| **Provider (provedor)** | A "empresa de RH" de onde vem esse cérebro: OpenAI, Anthropic, OpenRouter, Ollama (modelos locais, de graça). Você escolhe de quem "aluga" o cérebro. |
| **Agente** | O funcionário **com instruções, memória e ferramentas**. Não é só o cérebro — é o cérebro + um manual de função + acesso a sistemas. |
| **MCP (ferramentas)** | As "chaves de acesso aos sistemas da empresa". Um MCP dá ao agente a capacidade de **fazer coisas** no mundo real: criar campanha no Meta Ads, editar um vídeo, mandar WhatsApp. Sem MCP, o agente só conversa; com MCP, ele **executa**. |

Guarde a ideia central: **um agente = cérebro (modelo) + instruções + memória + ferramentas (MCP)**. OpenClaw e Hermes são duas formas diferentes de montar e operar esse agente.

---

## 2. O que é o Hermes

O **Hermes Agent** (feito pela Nous Research) se descreve como *"o agente que cresce com você"*. A grande sacada dele é um **ciclo de autoaprendizado**: ele

- **cria "skills" (habilidades) a partir da experiência** — aprende um procedimento uma vez e guarda para reusar;
- **lembra de você entre conversas** — monta um perfil seu (preferências, contexto) e consulta conversas passadas;
- **roda em qualquer lugar** — de um servidor de R$ 25/mês a um cluster de GPUs;
- **fala por vários canais** — Telegram, Discord, Slack, WhatsApp, e-mail e ~20 outros, tudo por um único "gateway".

E ele é **compatível com OpenAI nos dois sentidos**:
- **consome** qualquer modelo (você pluga OpenAI, Anthropic, OpenRouter, Ollama… sem trocar código);
- **se expõe** como uma API igual à da OpenAI — então qualquer app de chat (Open WebUI, LobeChat) se conecta a ele.

> **Resumo de uma linha:** o Hermes é um **agente generalista que aprende sozinho**, acessível por chat, por vários mensageiros e por API — e você pode rodar **vários deles** (cada um é um *profile*; veja a Seção 6).

---

## 3. Hermes × OpenClaw: semelhanças e diferenças

Os dois fazem a mesma coisa de base: são **agentes de IA self-hosted** (rodam no *seu* servidor), usam **MCP** para executar ações e aceitam **vários provedores de modelo**. Neste projeto, inclusive, **compartilham os mesmos MCP servers** (`meta-ads`, `media-editor`, `whatsapp`, `higgsfield`, `atlascloud`). A diferença está na **filosofia de organização**.

### A diferença que mais importa: **como os agentes se coordenam**

Os **dois têm vários agentes**. A diferença não é "um × muitos" — é **como eles trabalham juntos**.

- **OpenClaw = organograma com repasse automático.** Você cria **agentes nomeados e permanentes** (Diretor, Analista, Gestor…) que **se chamam sozinhos dentro de uma mesma conversa** (o Diretor aciona o Analista, que aciona o Gestor, num único turno). É a sua pasta `agency/`. Pense numa **agência com departamentos que conversam em tempo real**.
- **Hermes = vários agentes (chamados *profiles*) que colaboram por um "quadro de trabalho".** Cada **profile** é um agente completo e independente (personalidade, modelo, memória e ferramentas próprios). Eles **não se chamam automaticamente** dentro de uma conversa; em vez disso, coordenam-se por **mecanismos compartilhados**: o **quadro Kanban** (você atribui uma tarefa a um profile e ele a executa), o **swarm** (vários profiles em paralelo → verificador → sintetizador) e a **delegação efêmera** (ajudantes temporários para subtarefas). Pense num **time que se organiza por um quadro de tarefas**, não por uma ligação ao vivo entre departamentos.

> ⚠️ **Correção importante (e a resposta às suas perguntas):** o Hermes **é multi-agente sim** — só que "agente" no Hermes se chama **profile**, e você cria quantos quiser. Por isso a interface tem área de multi-agente. *(A importação `hermes claw migrate` traz **configurações, memórias, skills e chaves** do OpenClaw — os agentes em si você recria como profiles, manualmente; ver [Seção 8](#8-transferir-do-openclaw-para-o-hermes).)* O que o Hermes **não** faz é o **repasse automático nomeado dentro de um único turno** (o "organograma vivo" do OpenClaw). Veja a [Seção 7](#7-o-organograma-como-montar-um-time) e o [FAQ](#faq-multi-agente-profiles-e-organograma).

### Tabela comparativa

| Tema | OpenClaw | Hermes |
|---|---|---|
| **Vários agentes?** | Sim — **agentes nomeados** na `agency/` | **Sim** — cada agente é um **profile** |
| **Como se coordenam** | **Repasse automático** entre agentes dentro de um turno (organograma vivo) | Por **quadro Kanban** (tarefa → profile), **swarm** e **delegação efêmera** — sem repasse automático nomeado |
| **Dividir uma tarefa na hora** | Subagentes nomeados e persistentes (Diretor → Analista → Gestor) | **Delegação efêmera** (`delegate_task`): ajudantes temporários, sem memória, que retornam só um resumo |
| **Memória / aprendizado** | Memória por agente (você configura) | **Ciclo de autoaprendizado nativo**: cria *skills*, monta perfil do usuário, busca conversas antigas |
| **Definição do agente** | Arquivos por agente: `IDENTITY/SOUL/USER/TOOLS/AGENTS.md` | Um **profile** = `SOUL.md` (personalidade) + `config.yaml` próprios |
| **Agendamento (cron)** | Tem `openclaw cron` | Tem `hermes cron` (built-in, "tica" a cada 60s) |
| **Ferramentas (MCP)** | Sim | Sim (mesmos servers) |
| **API estilo OpenAI** | — (acesso pela UI/gateway) | **Sim** (`/v1/chat/completions`) — conecta em apps de chat |
| **Canais de mensagem** | WhatsApp (via bridge deste projeto) | **Gateway nativo**: Telegram, Discord, Slack, WhatsApp, e-mail… |
| **Interfaces** | UI web (porta 18789) | TUI no terminal + **dashboard web** (porta 9119) + API (porta 8642) |

### Quando usar cada um

- **Use o OpenClaw** quando você quer um **organograma com repasse automático** entre papéis dentro de uma conversa (Diretor aciona Analista aciona Gestor no mesmo turno) — é o seu caso da agência de tráfego.
- **Use o Hermes** quando você quer **agentes que aprendem com o uso**, acessíveis por vários mensageiros e por API, coordenados por um **quadro de tarefas** (Kanban) em vez de repasse automático — ótimo para fila de trabalho e automação.

> **Boa notícia:** neste projeto os dois rodam **lado a lado, no mesmo container**, em portas diferentes. Você não precisa escolher — pode usar os dois.

---

## 4. Primeiro contato

Neste projeto, o Hermes **já sobe junto com o container** (o `entrypoint.sh` inicia o `hermes gateway` na porta **8642** e o `hermes dashboard` na **9119**). Os dados dele ficam em `/root/.hermes` (volume persistente — sobrevive a reinício).

### 4.1 Acessar o dashboard (a "página de gestão")

No Mac/Windows, direto no navegador: **http://127.0.0.1:9119**
Na VPS, via túnel SSH (do seu laptop):
```bash
ssh -N -L 9119:127.0.0.1:9119 root@SEU_VPS_IP
```
Depois abra `http://127.0.0.1:9119`. O dashboard tem abas de **Status, Chat, Configuração, Sessões, Logs, Cron, Skills, MCP** e mais.

### 4.2 Configurar o cérebro (modelo/provedor) — passo obrigatório

O build **não** escolhe o modelo por você (de propósito). Rode uma vez o assistente interativo:
```bash
hermes model
```
Ele pergunta o **provedor** (ex.: OpenRouter, Anthropic, OpenAI, Ollama para modelos locais, ou o Nous Portal) → faz login/pede a chave → você escolhe o **modelo**. Pronto, o cérebro está plugado.

### 4.3 Conversar pela primeira vez

No terminal (modo conversa):
```bash
hermes
```
Ou uma pergunta única (entra, responde, sai):
```bash
hermes -q "Liste minhas campanhas ativas no Meta Ads"
```

### 4.4 Conectar um app de chat (opcional)

O Hermes expõe uma API igual à da OpenAI em `http://127.0.0.1:8642/v1`. Em apps como Open WebUI/LobeChat, aponte para essa URL e use como "API Key" o valor do `HERMES_API_SERVER_KEY` do seu `.env`. Teste rápido:
```bash
curl http://127.0.0.1:8642/v1/models -H "Authorization: Bearer SEU_HERMES_API_SERVER_KEY"
```

---

## 5. Os comandos da CLI

A CLI do Hermes é grande. Não decore tudo — entenda por **categoria**. Estão marcados com ⭐ os que você mais vai usar.

**Conversar**
- ⭐ `hermes` / `hermes chat` — abre a conversa (TUI). `hermes --tui` força a interface rica.
- `hermes -q "..."` — pergunta única (one-shot). `hermes -z "..."` — versão "crua" (só entra prompt, sai a resposta).

**Configurar / contas**
- ⭐ `hermes model` — escolher provedor + modelo.
- `hermes setup` — assistente de configuração (modelo, terminal, gateway, ferramentas…). `hermes setup --quick` para o caminho rápido.
- ⭐ `hermes config show | edit | set <chave> <valor> | path | check` — ver/editar a configuração.
- `hermes auth add|list|remove|status` — gerenciar chaves de provedores.

**Gateway / mensageiros**
- ⭐ `hermes gateway run|start|stop|restart|status` — liga o "carteiro" que conecta WhatsApp/Telegram/etc. **e** sobe a API (porta 8642). *(Neste projeto, o entrypoint já roda isso por você.)*
- `hermes send -t <destino> "msg"` — manda mensagem por um canal.
- `hermes whatsapp` — parear WhatsApp (QR). `hermes pairing list|approve|revoke` — aprovar quem pode falar com o agente.

**Ferramentas (MCP)**
- ⭐ `hermes mcp list` — ver os MCP conectados (deve mostrar `meta-ads`, `media-editor`, `whatsapp`, `higgsfield`, `atlascloud`).
- `hermes mcp add <nome> --command ... | --url ...` — adicionar um MCP. `hermes mcp test|configure|catalog|install`.

**Aprendizado (o diferencial)**
- `hermes skills browse|search|install|list` — habilidades (Seção 10).
- `hermes memory setup|status|off` — memória de longo prazo (Seção 10).
- `hermes sessions list|browse|export|search` — histórico de conversas (busca full-text).

**Automação**
- ⭐ `hermes cron list|create|edit|pause|resume|run|remove|status` — agendamento (Seção 9).
- `hermes kanban` — um quadro de tarefas (mais sobre isso na Seção 7).

**Migração e manutenção**
- ⭐ `hermes claw migrate` — **importa do OpenClaw** (Seção 8).
- `hermes profile list|create|use|...` — múltiplas "instâncias" isoladas (Seção 6/7).
- `hermes status | logs | doctor --fix | dashboard | version | update` — diagnóstico e UI.

> Para ver as opções de qualquer comando: `hermes <comando> --help` (ex.: `hermes cron --help`).

---

## 6. Como "criar agentes" no Hermes

**No Hermes, cada agente é um *profile*.** Um profile é um agente completo e independente, com:
- **`SOUL.md`** (personalidade: tom de voz, princípios, o que faz e não faz — equivale a `IDENTITY.md` + `SOUL.md` do OpenClaw juntos);
- **`config.yaml`** (configurações: modelo, autonomia, memória, MCP);
- **memória, sessões e skills próprios**.

O profile **`default`** já existe. Para ter mais agentes, você cria mais profiles.

### Profile (Hermes) × Agente (OpenClaw): a tradução

| No OpenClaw | No Hermes | Observação |
|---|---|---|
| Um **agente** da `agency/` (ex.: Analista) | Um **profile** (ex.: `analista`) | 1 agente OpenClaw = 1 profile Hermes |
| `IDENTITY.md` + `SOUL.md` do agente | **`SOUL.md`** do profile | Junte os dois num arquivo |
| `USER.md` (com quem fala/tom) | Trechos do `SOUL.md` + perfil de usuário (`memories/USER.md`) | — |
| `AGENTS.md` (fluxo, alçada, "não faça") | Regras no `SOUL.md` + uma **skill** com o procedimento | — |
| `TOOLS.md` (quais MCP) | `config.yaml` → `mcp_servers` | O profile vê as ferramentas conectadas |
| Agentes **se chamam automaticamente** | Profiles colaboram pelo **Kanban/swarm/delegação** | Diferença central (veja [FAQ](#faq-multi-agente-profiles-e-organograma)) |

> Em uma frase: **"criar um agente no Hermes" = "criar um profile".**

### ⚠️ Onde se faz isso (NÃO é na interface)

A maior parte do "cadastro" de um agente **não é feita pela UI**. A interface serve para **operar e ajustar configs**; **criar um profile** e **escrever o `SOUL.md`** são feitos por **CLI + arquivos**. E como `~/.hermes` é um **volume montado**, esses arquivos ficam **direto no seu computador** — você abre no VS Code/Finder.

```
~/.hermes/                         ← profile DEFAULT
├── SOUL.md                        ← personalidade do agente default   ← EDITE AQUI
├── config.yaml                    ← configurações do default          ← EDITE AQUI
├── memories/  skills/  cron/  sessions/ ...
└── profiles/
    └── analista/                  ← cada profile = um agente à parte
        ├── SOUL.md                ← personalidade do analista         ← EDITE AQUI
        └── config.yaml            ← configurações do analista         ← EDITE AQUI
```

| O que você quer | Onde se faz |
|---|---|
| **Criar um agente (profile)** | CLI: `hermes profile create <nome>` (a UI não cria) |
| **Escrever/editar o `SOUL.md`** | No **arquivo** (`~/.hermes/SOUL.md` ou `~/.hermes/profiles/<nome>/SOUL.md`) |
| **Editar o `config.yaml`** | No arquivo, ou `hermes config edit` / `hermes config set <chave> <valor>` |
| **Operar (Kanban, Skills, Sessões, Logs, MCP, Pairing)** | Na **UI** (dashboard) |

> Em uma frase: **a UI é o "painel de operação"; a "ficha do agente" (criar profile + SOUL.md) mora em arquivos no `~/.hermes/`.**

### A "personalidade" de um agente (SOUL.md)

```bash
hermes config path     # mostra onde fica a pasta ~/.hermes
```
Abra o `SOUL.md` do profile (no host, em `~/.hermes/SOUL.md` para o default, ou `~/.hermes/profiles/<nome>/SOUL.md` para um cargo). Exemplo de um Hermes "gerente de tráfego":

```markdown
# SOUL

Você é o assistente de tráfego pago da {{SEU_NEGÓCIO}}. Decide e executa com base em números.

- Tom: direto, curto, sem floreio. Sempre confirma o que vai fazer antes de mexer em campanha.
- Nunca gasta acima de R$ 200/dia sem confirmar com o dono.
- Fala português. Trata o dono por "você".
```

### Ajustar configurações (config.yaml)

Você pode editar pelo dashboard ou por comando:
```bash
hermes config set approvals.mode smart      # off | smart | manual (quanto ele pede permissão)
hermes config show                          # conferir tudo
```
Campos úteis para começar: `model` (cérebro), `approvals.mode` (autonomia), `memory` (liga/desliga aprendizado), `mcp_servers` (ferramentas), `delegation` (ajudantes temporários — Seção 7).

### Criar mais agentes (um profile por cargo)

Cada *profile* é um agente isolado — próprio `SOUL.md`, modelo, memória e configurações. É assim que você monta "vários funcionários" na mesma máquina:

```bash
hermes profile create analista        # cria o agente "analista"
hermes profile create gestor          # cria o agente "gestor"
hermes profile list                   # lista todos (mostra modelo de cada um)
hermes profile use analista           # passa a operar nesse agente
```

Exemplo real desta instalação (já tem dois agentes, com **modelos diferentes** por cargo):

```text
 Profile     Model                     Gateway
 ◆default    deepseek/deepseek-v3.2    stopped
  analista   deepseek/deepseek-v4-pro  stopped
```

Depois de `hermes profile use <nome>`, você edita o `SOUL.md` e o `config.yaml` **daquele** profile (ficam em `~/.hermes/profiles/<nome>/`). Assim o "analista" pode usar um modelo mais barato e o "gestor" um mais cuidadoso, cada um com sua personalidade.

> Pense em profiles como **"contas de funcionário"**: cada um tem seu crachá (SOUL.md), seu nível de acesso (MCP/aprovações) e sua memória. Eles trabalham juntos pelo **quadro Kanban** (Seção 7), não por ligação automática entre si.

### 👷 Passo a passo: criar um profile do zero (ex.: "gestor")

> Lembre do prefixo `docker compose exec -it openclaw-vibestack` antes de cada `hermes ...`. Os arquivos ficam no seu Mac, em `~/.hermes/profiles/<nome>/`.

**1. Crie o profile (pela CLI — a UI não faz isso):**
```bash
hermes profile create gestor
```
Isso cria a pasta `~/.hermes/profiles/gestor/` (com `SOUL.md` e `config.yaml` iniciais).

**2. Escreva a personalidade — edite o arquivo no seu Mac:**
Abra `~/.hermes/profiles/gestor/SOUL.md` (VS Code, Finder, etc.) e escreva quem é esse agente. Exemplo:
```markdown
# SOUL

Você é o Gestor de Tráfego da {{SEU_NEGÓCIO}}. Único que ESCREVE no Meta Ads.

- Só executa sob ordem clara (da Estrategista ou do dono). Ordem ambígua: pergunte, não chute.
- Toda campanha nasce PAUSED. Confirme cada ação com o ID retornado.
- Tom: curto e militar. "Pausado. ID=23845." em vez de textão.
```

**3. Entre no profile e escolha o cérebro (modelo) dele:**
```bash
hermes profile use gestor      # passa a operar como "gestor"
hermes model                   # escolhe provedor + modelo SÓ desse profile
```

**4. Ajuste a autonomia e confira (opcional):**
```bash
hermes config set approvals.mode smart   # off | smart | manual
hermes config show                       # confere a config do profile ativo
```
*(Isso edita o `config.yaml` do profile ativo — ou seja, `~/.hermes/profiles/gestor/config.yaml`.)*

**5. Teste o agente:**
```bash
hermes -q "Quais campanhas estão ativas agora?"   # pergunta única, já como 'gestor'
# ou abra a conversa: hermes
```

**6. Volte ao profile padrão quando quiser:**
```bash
hermes profile use default
hermes profile list            # confere qual está ativo (◆) e o modelo de cada um
```

**7. Coloque o profile para trabalhar no quadro (Kanban):**
```bash
hermes kanban create "Pausar conjuntos com ROAS < 1" --assignee gestor
```

> **Repetindo o essencial:** o **passo 1** (criar) e o **passo 2** (SOUL.md) **não** têm botão na UI — são CLI + arquivo. Do passo 3 em diante você pode usar a UI (Configuration/Chat) se preferir.

---

## 7. O "organograma": como montar um time

Você perguntou como criar um **organograma** no Hermes. A resposta precisa:

> **O Hermes tem vários agentes (profiles), sim** — o que ele não tem é o **repasse automático nomeado dentro de uma conversa** (o "organograma vivo" do OpenClaw, em que o Diretor aciona o Analista que aciona o Gestor num único turno). No Hermes, os agentes (profiles) se coordenam por **quadro de tarefas, swarm e delegação**. Se você precisa do repasse automático em tempo real, o **OpenClaw** continua melhor para isso.

Há **três formas** de montar um time no Hermes — da mais simples à mais parecida com um organograma:

### FAQ: multi-agente, profiles e organograma

**"Se não é multi-agente, por que a interface do Hermes tem uma parte de multi-agente?"**
Porque **ele é multi-agente** — cada agente é um **profile**. A área de multi-agente do dashboard é onde você gerencia esses profiles (criar, ver o modelo de cada um, acompanhar quem está executando tarefa). Eu fui impreciso antes ao chamar de "single-agent": o certo é que o Hermes roda **vários agentes (profiles)**; o que muda é a **forma de coordenação** (quadro de tarefas, não repasse automático).

**"E por que ele deixa importar os agentes do OpenClaw, tendo mais de um?"**
Porque **multi-agente no Hermes = vários profiles**, e você pode criar quantos quiser (`hermes profile create`). A interface lista e gerencia esses profiles. **Importante:** a migração `hermes claw migrate` **não** recria sozinha cada agente da `agency/` como um profile — ela traz **configurações, memórias, skills e chaves de API** do OpenClaw (verificado no `--help`). Para ter seus 6 cargos como agentes, você **cria 6 profiles** e adapta o `SOUL.md` de cada um (Seção 8). Ou seja: o Hermes é multi-agente; só que os agentes você monta como profiles.

**"Então qual é, de fato, a diferença para o OpenClaw?"**
Só uma: **quem dá o próximo passo.** No OpenClaw, um agente **chama outro automaticamente** dentro da mesma conversa (organograma vivo). No Hermes, **você (ou o quadro Kanban, ou o swarm) decide** qual profile pega cada tarefa. Mesma quantidade de agentes; gestão diferente.

### Forma A — Um agente + delegação efêmera (`delegate_task`) ✅ recomendada

O Hermes consegue, **durante uma tarefa**, abrir **ajudantes temporários** para subtarefas (pesquisar, processar arquivos, etc.). Eles:
- nascem **sem memória** (você passa o objetivo e o contexto na hora);
- rodam em paralelo (até 3 por padrão);
- devolvem **só um resumo** e **desaparecem**.

É como um gerente que, num pico, distribui pedaços de um trabalho para freelancers e junta o resultado. Configura-se no `config.yaml`:

```bash
hermes config set delegation.max_concurrent_children 3   # quantos ajudantes ao mesmo tempo
hermes config set delegation.max_spawn_depth 2           # 1 = plano; 2 = ajudante pode ter ajudante
hermes config set delegation.orchestrator_enabled true   # permite o agente "orquestrar" subtarefas
```
**Limite importante:** esses ajudantes são **descartáveis** — não são "o Analista" permanente. Servem para dividir UMA tarefa, não para manter papéis fixos.

### Forma B — Um profile por papel (o mais parecido com organograma)

Crie um *profile* para cada "cargo" e dê a cada um seu `SOUL.md` e suas ferramentas:

```bash
hermes profile create diretor
hermes profile create analista
hermes profile create gestor
```
- O **diretor** fala com você (pelo WhatsApp/Telegram do gateway).
- Como eles são isolados, a "conversa entre cargos" acontece **por mensagem** (um manda tarefa para o outro por um canal/automação) ou **por API** (um chama o `/v1/chat/completions` do outro). Não é tão automático quanto o organograma do OpenClaw, mas dá para orquestrar.

> Use a Forma B quando você quer **papéis realmente separados e persistentes**. É trabalho de integração manual entre eles.

### Forma C — Quadro Kanban visual (`hermes kanban` + aba no dashboard)

O Hermes tem um **quadro Kanban embutido com interface visual** no dashboard. É o jeito mais "gerenciável" de operar um time no Hermes: você cria tarefas, **atribui cada uma a um profile** (= um "cargo", veja a Forma B) e um **dispatcher** roda cada tarefa sozinho, na vez dela. Ótimo para **fila de trabalho** (ex.: "produzir 10 criativos", "auditar 5 campanhas").

Como funciona, em uma frase: **cada tarefa tem um dono (profile) e anda sozinha pelas colunas**; o dispatcher (que vive dentro do `hermes gateway`) pega as tarefas prontas a cada ~60s e executa com o profile atribuído como "trabalhador".

Veja a subseção dedicada abaixo — [Ativar e ver o Kanban na interface](#-ativar-e-ver-o-kanban-na-interface) — para o passo a passo.

### Qual escolher?

| Você quer… | Use |
|---|---|
| Dividir **uma tarefa grande** rapidamente | **A** (delegação) |
| **Cargos separados e permanentes** (organograma de verdade) | **OpenClaw** (`agency/`) — ou **B** (profiles) com integração manual |
| **Fila de tarefas** sendo tocada sozinha | **C** (kanban) |

### 🗂️ Ativar e ver o Kanban na interface

O quadro Kanban **já vem embutido** no Hermes (não precisa instalar nada). No dashboard ele aparece como uma **aba "Kanban"** (logo depois de "Skills" no menu) — é um plugin que já vem na caixa, por isso não está na lista "oficial" de abas. É um quadro **visual e interativo**: você arrasta cartões entre colunas, cria com um "+", clica num cartão para editar, etc.

**As colunas (o caminho de uma tarefa):**
`triage` → `todo` → `scheduled` → `ready` → `running` → `blocked` → `done` (e `archived`). Quem está em `ready` é pego pelo dispatcher e vai para `running` sozinho. `scheduled` = tarefa esperando um horário; `triage` = rascunho que ainda não vai executar (ótimo para testar sem disparar nada).

> ✅ **Validado ao vivo** nesta instalação: a CLI `hermes kanban` tem todos esses comandos (incluindo `init`, `create`, `list`, `stats`, `dispatch`, `archive` e até `swarm` — "trabalhadores em paralelo → verificador → sintetizador"); o **dispatcher roda dentro do gateway** ("ticando" a cada 60s — o subcomando `daemon` antigo está **deprecado**); e o **plugin visual existe** em `/opt/hermes-agent/plugins/kanban/dashboard/` (é ele que desenha a aba "Kanban" no dashboard).

#### Passo a passo (ativar e ver funcionando)

**1. Inicialize o quadro (uma única vez)** — cria o banco do Kanban:
```bash
hermes kanban init
```

**2. Garanta que o `gateway` está rodando** — é ele que "tica" o dispatcher a cada ~60s e executa as tarefas. *(Neste projeto o entrypoint já sobe o gateway; para conferir: `hermes gateway status`.)*

**3. Abra o dashboard e a aba Kanban:**
- Mac/Windows: `http://127.0.0.1:9119` → clique em **"Kanban"** (após "Skills").
- VPS: `ssh -N -L 9119:127.0.0.1:9119 root@SEU_VPS_IP` e abra `http://127.0.0.1:9119`.

**4. Crie uma tarefa** — pela interface (botão **"+"** no topo de uma coluna) **ou** pela CLI, atribuindo a um *profile* (o "cargo" que vai executar):
```bash
hermes kanban create "Gerar 3 criativos 9:16 da promo de junho" --assignee criativo
hermes kanban create "Auditar campanhas com ROAS < 1" --assignee analista
hermes kanban list           # ver as tarefas e seus status
```

**5. Veja andar sozinho** — em até ~60s o dispatcher pega as tarefas em `ready`, move para `running` e executa com o profile atribuído. No quadro, os cartões se movem **ao vivo** (atualização em tempo real). Você pode:
- **arrastar** um cartão entre colunas (ex.: puxar de `triage` para `ready` para liberar a execução);
- clicar no cartão para abrir o **painel lateral** (editar título, responsável, descrição, dependências, comentários);
- usar o **"+"** para criar direto numa coluna; e fazer **ações em lote** (selecionar vários e mudar status/arquivar).

**6. Acompanhar pela CLI** (alternativa à UI):
```bash
hermes kanban show <id>      # detalhes de uma tarefa
hermes kanban watch          # acompanha em tempo real no terminal
hermes kanban stats          # visão geral
hermes kanban dispatch --dry-run   # ver o que o dispatcher faria, sem executar
```

#### Comandos úteis do `hermes kanban`

| Comando | O que faz |
|---|---|
| `init` | Cria o quadro (uma vez). |
| `create "<título>" --assignee <profile>` | Nova tarefa atribuída a um cargo. Aceita `--priority`, `--skill <nome>`, `--triage`, `--parent <id>`. |
| `list` / `show <id>` | Listar / detalhar tarefas. |
| `decompose <id>` | Quebra uma tarefa grande em subtarefas. |
| `specify <id>` | Detalha uma tarefa que entrou como rascunho (`triage`). |
| `dispatch [--dry-run] [--max N]` | Roda o despachante manualmente (normalmente é automático). |
| `assign <id> <profile>` / `block`/`unblock` / `promote` / `complete` / `archive` / `comment` | Mover/gerir tarefas. |
| `boards` | Gerencia **quadros** (um por projeto/fluxo). |
| `swarm` | Cria um "enxame": vários cargos em paralelo → verificador → sintetizador. |

#### Exemplos práticos (copiar e colar)

> Lembre do prefixo `docker compose exec -it openclaw-vibestack` antes de cada `hermes ...`.

**1) Tarefa simples, atribuída a um cargo (profile):**
```bash
hermes kanban create "Resumir o desempenho das campanhas de ontem" --assignee analista
```

**2) Tarefa detalhada (corpo, prioridade e uma skill):**
```bash
hermes kanban create "Gerar 3 criativos 9:16 da promo de junho" --assignee criativo --body "Formato Reels; CTA 'Saiba mais'." --priority 1 --skill criar-criativo
```

**3) Criar como rascunho (não dispara) e liberar depois:**
```bash
hermes kanban create "Auditar campanhas com ROAS < 1" --assignee analista --triage
hermes kanban list                  # veja o id (ex.: t_ab12cd34)
hermes kanban promote t_ab12cd34    # move para 'ready' -> o dispatcher pega em ~60s
```

**4) Quebrar uma tarefa grande em subtarefas:**
```bash
hermes kanban create "Lançar campanha de Dia dos Pais" --assignee gestor
hermes kanban decompose <id>        # cria as subtarefas filhas
```

**5) Criar um QUADRO novo (um board por projeto/cliente):**
```bash
hermes kanban boards --help         # mostra os subcomandos de quadro (create/list/use…)
hermes kanban boards create criativos          # cria o quadro "criativos"
# depois, mire um quadro específico com --board:
hermes kanban --board criativos create "Banner da home" --assignee criativo
hermes kanban --board criativos list
```
> Cada **board** é um quadro independente, com **DB e dispatcher próprios** (ex.: um por cliente/projeto) — tarefas de um quadro não colidem com as de outro. O primeiro quadro é o `default`. Subcomandos (verificados): `boards create <slug>` (criar), `boards list`, `boards switch <slug>` (deixa esse quadro como ativo), `boards show` (qual está ativo), `boards rename`, `boards rm`. O `--board <slug>` mira um quadro só naquele comando; sem ele, usa o ativo.

**6) Enxame (swarm) — vários cargos numa meta só:**
```bash
hermes kanban swarm --help          # opções para fan-out (trabalhadores → verificador → sintetizador)
```

#### Onde fica salvo

Tudo em `/root/.hermes/kanban*` (persistente): o banco `kanban.db`, as pastas de trabalho de cada tarefa (`kanban/workspaces/<id>/`, apagadas ao concluir) e os logs (`kanban/logs/`).

#### Ajustes opcionais (config)

No `config.yaml` você pode afinar o comportamento (não é obrigatório):
```bash
hermes config set kanban.dispatch_interval_seconds 60   # de quanto em quanto o dispatcher roda
hermes config set kanban.auto_decompose true            # quebra tarefas grandes sozinho
hermes config set dashboard.kanban.lane_by_profile true # mostra uma "raia" por cargo na coluna "running"
```

> **Dica de organograma:** Kanban + um **profile por cargo** (Forma B) é o mais perto de um "time com fila de trabalho" que o Hermes oferece — cada tarefa tem um responsável e roda sozinha. Para hierarquia de **decisão/aprovação** (Diretor aprova, Gestor executa), o OpenClaw ainda é mais direto.

### 🎬 Como as tasks funcionam na prática (fluxo temporal de uma agência)

Aqui é onde tudo se junta. Vamos ver, **minuto a minuto**, uma agência de tráfego (cada cargo = um *profile*) usando o Kanban para **lançar uma campanha no Meta Ads com criativos**.

#### Primeiro, o conceito de "task" em 30 segundos

Uma **task** (tarefa) é um **cartão de pedido** com: um **título**, um **dono** (`--assignee <profile>` = o cargo que vai executar), um **status** (a coluna) e, opcionalmente, **dependências** (espera outra task terminar). O **dispatcher** (dentro do gateway, a cada ~60s) pega as tasks que estão em `ready`, entrega ao profile dono — que roda **isolado**, usa suas ferramentas MCP, e marca a task como `done`. Tasks com dependência pendente ficam `blocked` até a dependência fechar.

#### Os três jeitos de criar trabalho — e quando usar cada um

| Jeito | O que faz | Analogia | Quando usar |
|---|---|---|---|
| **`create`** | Cria **uma** task para **um** cargo | Passar **um** pedido a **um** funcionário | Trabalho pontual |
| **`decompose`** | Quebra uma task em **partes diferentes** que se **somam** | Dividir um projeto em **etapas** entre vários | "Lançar campanha" = analisar + escrever + criar arte + publicar |
| **`swarm`** | Manda **vários** tentarem a **mesma** meta em paralelo → um **verifica** → um **sintetiza** o melhor | Pedir **3 propostas**, conferir e escolher a melhor | Gerar variações criativas e ficar com a melhor |

> Em uma frase: **decompose = dividir em pedaços diferentes; swarm = várias tentativas da mesma coisa, e escolher a melhor.**

#### A linha do tempo (cenário real: promo de Dia dos Pais)

Cargos (profiles) já criados: `diretor`, `analista`, `estrategista`, `copywriter`, `criativo`, `gestor`. Quadro: `campanhas`.

**T+0 — Você joga o pedido no quadro** (uma task-mãe para a Estrategista):
```bash
hermes kanban --board campanhas create "Lançar promo de Dia dos Pais (seu produto)" --assignee estrategista
```

**T+0 — A Estrategista (ou você) decompõe em etapas com dependências.** Quem publica (Gestor) só pode rodar **depois** que texto e arte ficarem prontos:
```bash
hermes kanban --board campanhas create "Ler performance 14d e apontar os melhores ângulos" --assignee analista
hermes kanban --board campanhas create "Escrever 3 textos (headline/primary/description)"   --assignee copywriter
hermes kanban --board campanhas create "Produzir 3 criativos 9:16 da promo"                  --assignee criativo
# a task do Gestor depende das duas anteriores (texto + arte):
hermes kanban --board campanhas create "Montar campanha PAUSED + ad set + anúncio" --assignee gestor --parent <id_copy> --parent <id_criativo>
```
*(`--parent` cria a dependência; dá no mesmo que `hermes kanban link <pai> <filho>`.)*

**T+1min — primeiro "tick" do dispatcher.** Ele vê 3 tasks em `ready` (analista, copywriter, criativo — sem dependências) e dispara **em paralelo**, cada profile como um trabalhador isolado:
- 🔎 **Analista** usa o MCP `meta-ads` (só leitura): `get_insights`, `list_campaigns` → entrega "os ângulos X e Y converteram melhor".
- ✍️ **Copywriter** escreve as 3 variações e marca `done`.
- 🎬 **Criativo** dispara um **swarm** para a arte (detalhe abaixo).
- 🛠️ **Gestor** continua `blocked` (faltam as dependências). 🎯 **Diretor** idem.

**T+1min (dentro do Criativo) — o swarm da arte:**
```bash
hermes kanban --board campanhas swarm "Gerar 3 conceitos de criativo 9:16 da promo" --assignee criativo
```
O swarm monta sozinho:
1. **3 workers em paralelo** — cada um gera um conceito (MCP `higgsfield` `generate_image` / `media-editor` `image_fit`+`image_overlay`).
2. **1 verificador** — roda `probe(validate_for="meta_image_story")` e descarta o que estiver fora das specs do Meta.
3. **1 sintetizador** — escolhe o melhor e finaliza com `finalize_for_meta(...)` → gera o arquivo em `/root/.openclaw/workspace/_shared/creatives/`.

Resultado: **1 arquivo final aprovado**, o caminho dele volta como resultado da task.

**T+~6min — texto e arte ficam `done`.** Como a task do Gestor dependia das duas, ela **destrava** (`blocked → ready`).

**T+~7min — próximo tick: o Gestor executa** (MCP `meta-ads`, escrita): `create_campaign` (status **paused**, por segurança) → `create_ad_set` → `create_creative` (usando o `path` do criativo + os textos do copy) → `create_ad`. Confirma com os **IDs** e marca `done`.

**T+~8min — a task do Diretor destrava** → ele consolida tudo e **te avisa no seu canal** (WhatsApp/Telegram), com o resumo e os IDs. *(A entrega no canal é configurável por task — ver `hermes kanban notify-subscribe` / roteamento de entrega.)*

#### O quadro evoluindo (o que você vê na aba Kanban)

```
            T+0min                         T+1min                        T+7min
ready    │ analista, copy, criativo │   (vazio)                  │  gestor
running  │                          │   analista, copy, criativo │  gestor
blocked  │ gestor, diretor          │   gestor, diretor          │  diretor
done     │                          │                            │  analista, copy, criativo
```
No dashboard os cartões se movem **ao vivo**; no terminal você acompanha com:
```bash
hermes kanban --board campanhas watch     # stream ao vivo
hermes kanban --board campanhas stats      # contagem por status e por cargo
```

#### O paralelo com a sua agência do OpenClaw

| Na agência (OpenClaw) | Vira, no Kanban do Hermes |
|---|---|
| Estrategista despacha o caso | Task-mãe atribuída ao profile `estrategista` |
| Cada cargo recebe sua parte | `decompose` → uma task por cargo |
| "Gestor só publica após aprovação" | Dependência (`--parent`) deixa a task do gestor `blocked` até as outras |
| Criativo entrega 1 peça (não 3 "por garantia") | `swarm` gera 3, **verifica** e entrega **1** |
| Diretor avisa o dono | Task final do `diretor` com entrega no seu canal |

> A grande diferença que você já conhece: no OpenClaw esse encadeamento é **automático dentro de um turno**; no Kanban do Hermes ele acontece pelo **quadro + dependências + dispatcher** (cada etapa numa sessão isolada). O resultado de negócio é o mesmo; a "engrenagem" é o quadro.

### 🔧 Como o AGENTE usa o Kanban (function calling)

Aqui vale separar **duas formas** de mexer no quadro — e é uma confusão comum:

- **Você (humano)** mexe pela **interface** ou pelo **CLI** `hermes kanban ...`.
- **O agente (modelo)** mexe por **chamada de função (tools)** — ele **não** roda o CLI. Ele tem um *toolset* de Kanban com funções como: `kanban_create`, `kanban_show`, `kanban_list`, `kanban_link`, `kanban_comment`, `kanban_heartbeat`, `kanban_block`, `kanban_unblock`, `kanban_complete`.

**Como o "trabalhador" recebe a tarefa (o pulo do gato):** quando o dispatcher escolhe uma task e spawna o profile dono como worker, ele injeta no ambiente a variável `HERMES_KANBAN_TASK=t_abcd`. **Essa variável liga o toolset de Kanban no schema do modelo** — ou seja, o agente "acorda" já sabendo qual é a sua task e com as funções para mexer nela. (Profiles "orquestradores" também podem ligar o toolset `kanban` explicitamente.)

**O ciclo típico de um worker** (tudo via function calling, sem CLI):
```text
kanban_show()                      → lê o worker_context (o que precisa fazer + dados da task)
… faz o trabalho (usa os MCP: meta-ads, media-editor, higgsfield…) …
kanban_heartbeat(note="andando")   → sinal de vida (worker ainda vivo)
… termina …
kanban_complete(summary="feito: campanha 123 criada", metadata={...})
```
Tradução para o negócio: **o cartão do Kanban é "a ordem de serviço" do funcionário (profile).** Ele abre a ordem (`kanban_show`), executa com suas ferramentas, dá sinais de progresso (`kanban_heartbeat`) e fecha com um resumo (`kanban_complete`) — sozinho, numa sessão isolada.

### 🧭 Quando usar Kanban (× `delegate_task` × cron × chat)

Nem todo trabalho pede Kanban. Use o **mapa de decisão**:

| Situação | Use | Por quê |
|---|---|---|
| Preciso de **uma resposta rápida** no meio do raciocínio, sem humano, e o resultado volta para o próprio agente | **`delegate_task`** | É uma **chamada de função** efêmera (ajudante temporário que some) |
| O trabalho **cruza cargos** (um faz, outro continua), **precisa sobreviver a restart**, pode **precisar de um humano** ou ser **retomado/auditado depois** | **Kanban** | Cada repasse vira uma **linha visível** que qualquer profile (ou você) vê e edita |
| Quero algo **recorrente no horário** (todo dia 9h, a cada 2h) | **`cron`** | Agenda; pode até criar tasks no Kanban |
| É só uma **pergunta/uma ação pontual** agora | **Chat direto** (`hermes`) | Não precisa de fila nem de quadro |

> **A regra de ouro (da documentação oficial):** *"`delegate_task` é uma chamada de função; o Kanban é uma fila de trabalho onde cada repasse é uma linha que qualquer profile (ou humano) pode ver e editar."*

**Os 3 cenários onde o Kanban brilha** (exemplos da doc):
1. **Triagem com várias frentes + humano no meio** — ex.: vários pesquisadores em paralelo → analista → redator, com você aprovando no caminho.
2. **Operações recorrentes** — ex.: o brief diário das campanhas (combinado com `cron`).
3. **Pipelines de várias etapas** — ex.: decompor → executar em paralelo → revisar (exatamente o fluxo da campanha que vimos acima).

---

## 8. Transferir do OpenClaw para o Hermes

Há duas camadas para "transferir": (1) o que vem **automático** (configurações, memórias, skills, chaves) e (2) os **agentes em si** (manual — você cria os profiles e adapta os prompts).

### 8.1 O que o `hermes claw migrate` traz (verificado no `--help`)

O comando importa de uma instalação do OpenClaw: **configurações (settings), memórias, skills e chaves de API**. Ele mostra um **preview** sempre e, por padrão, grava um **backup** de `~/.hermes/` antes de aplicar (restaurável com `hermes import`).

```bash
hermes claw migrate --dry-run                 # SÓ mostra o que viria, sem aplicar (comece por aqui)
hermes claw migrate                           # aplica o preset 'full' (padrão), SEM segredos
hermes claw migrate --migrate-secrets --yes   # inclui chaves de API/tokens; pula a confirmação
```
Flags úteis (todas verificadas): `--source <caminho>` (pasta do OpenClaw; padrão `~/.openclaw`), `--preset full|user-data` (padrão `full`), `--migrate-secrets` (inclui chaves — **nenhum** preset traz segredos sem ela), `--overwrite`, `--skill-conflict skip|overwrite|rename`, `--no-backup`, `--yes`.

> ⚠️ **Correção (eu havia exagerado antes):** o `claw migrate` **não** recria automaticamente cada agente da `agency/` como um profile. Ele traz **configurações, memórias, skills e chaves** — não os agentes. Para ter seus cargos como agentes no Hermes, você **cria os profiles** (`hermes profile create <nome>`) e adapta o `SOUL.md` de cada um (passo abaixo). O `--dry-run` mostra exatamente o que será importado.

### 8.2 Recriar os agentes como profiles (manual)

Para cada agente da `agency/`, **crie um profile** (`hermes profile create <nome>`) e monte o `SOUL.md` dele a partir dos arquivos do OpenClaw, pelo mapeamento:

| No OpenClaw (`agency/<agente>/`) | Vira, no Hermes |
|---|---|
| `IDENTITY.md` + `SOUL.md` | Conteúdo do **`SOUL.md`** do Hermes (junte os dois) |
| `USER.md` | Trechos do `SOUL.md` (com quem ele fala, tom) ou do perfil de usuário (`memories/USER.md`) |
| `AGENTS.md` (fluxo, regras, "não faça") | Vira **regras no `SOUL.md`** + uma **skill** (Seção 10) com o procedimento passo a passo |
| `TOOLS.md` (quais MCP usar) | Já é resolvido pelo `config.yaml` (`mcp_servers`) — o Hermes vê as ferramentas conectadas |

**Duas estratégias práticas:**
- **Quer UM assistente forte?** Junte o melhor dos 6 num único `SOUL.md` e transforme os procedimentos (analisar, criar campanha, gerar criativo) em **skills**. O Hermes escolhe a skill certa na hora.
- **Quer manter os 6 papéis separados?** Crie **um profile por agente** (Seção 7, Forma B) e cole o `SOUL.md` correspondente em cada um.

> Lembre-se: os prompts do OpenClaw que você baixou já estão **genéricos com placeholders** (`{{DONO}}`, `{{PRODUTO_1}}`…). Ao migrar para o Hermes, troque os placeholders pelos seus valores reais no `SOUL.md`.

---

## 9. Crons e "heartbeats"

Aqui está uma **boa notícia**: o Hermes tem **agendamento embutido** (cron). Você **não** precisa de ferramenta externa.

### Como funciona (o "heartbeat")

O `hermes gateway` (que neste projeto já está rodando) **"bate o coração" a cada 60 segundos**: a cada batida ele verifica se há tarefa agendada vencida e, se houver, executa numa **sessão nova e isolada** (sem misturar com outras conversas). Esse tique de 60s é o "heartbeat" do Hermes.

> ⚠️ **Pré-requisito:** o **gateway precisa estar rodando** para os crons dispararem. Neste projeto o entrypoint já sobe o gateway — então está coberto.

### Criar uma tarefa agendada

Pelo chat (durante uma conversa):
```
/cron add "every 2h" "Verifique o status das campanhas e me avise se algo caiu"
```
Pela CLI:
```bash
hermes cron create "every 2h" "Resumo das campanhas ativas e alertas"
hermes cron create "0 9 * * *" "Relatório diário às 9h"     # expressão cron clássica
hermes cron create "30m" "Tarefa única daqui a 30 minutos"  # atraso relativo (roda uma vez)
```

**Formatos de horário aceitos:**
- **Intervalo:** `every 30m`, `every 2h`, `every 1d` (repete).
- **Expressão cron:** `0 9 * * *` (todo dia às 9h), `0 */6 * * *` (a cada 6h).
- **Atraso relativo:** `30m`, `2h`, `1d` (dispara uma vez).
- **Data/hora ISO:** um horário específico.

### Gerenciar os agendamentos

```bash
hermes cron list           # ver todos
hermes cron status         # estado do agendador
hermes cron run <id>       # rodar agora, na mão (teste)
hermes cron pause <id>     # pausar / hermes cron resume <id> para voltar
hermes cron remove <id>    # apagar
```
Os jobs ficam em `/root/.hermes/cron/` (persistente — sobrevivem a reinício).

### Recursos avançados (cite no curso como "dá para crescer")

- **Anexar uma skill** ao job: `/cron add "every 1h" "..." --skill nome-da-skill`.
- **Encadear jobs** (um usa o resultado do anterior) via `context_from`.
- **Entregar o resultado num canal** (te mandar no WhatsApp/Telegram quando terminar).
- **Portão `wakeAgent`**: deixa o job checar uma condição barata **antes** de acordar o cérebro (o modelo), economizando custo quando não há nada a fazer.

> **Comparação rápida:** tanto o OpenClaw (`openclaw cron`) quanto o Hermes (`hermes cron`) têm agendador. No Hermes ele é "ticado" pelo gateway a cada 60s e cada disparo roda numa sessão limpa.

---

## 10. Memória e Skills

Este é **o diferencial** do Hermes — vale uma aula só.

### Memória (ele lembra de você)

O Hermes mantém, em `/root/.hermes/memories/`:
- **`USER.md`** — quem é você (preferências, contexto do negócio).
- **`MEMORY.md`** — observações que ele juntou ao longo do tempo.

Esses arquivos entram no início de cada conversa (como um "resumo do que eu sei sobre você"). Além disso, ele **indexa todas as conversas** e consegue **buscar no próprio histórico** ("o que combinamos sobre a campanha de junho?"). Ligar/conferir:
```bash
hermes memory status
hermes memory setup      # configura memória (inclusive opções avançadas de busca semântica)
```

### Skills (ele aprende procedimentos)

Uma **skill** é um documento de "como fazer X" que o agente carrega **só quando precisa** (economiza tokens). É um arquivo `SKILL.md` com um cabeçalho e instruções. Exemplo do conceito:

```markdown
---
name: criar-campanha-meta
description: Passo a passo para abrir uma campanha de tráfego no Meta Ads
---
# Criar campanha no Meta Ads
## Quando usar
Quando o dono pedir uma campanha nova.
## Passos
1. Confirmar objetivo e orçamento.
2. Usar a tool create_campaign (status=paused).
3. ...
```
O mais interessante: **o próprio Hermes cria e melhora skills com o uso**. Você também pode instalar prontas:
```bash
hermes skills browse           # ver disponíveis
hermes skills install <id>     # instalar
hermes skills list             # ver instaladas
```
Use skills como **"procedimentos da empresa (POPs)"**: você ensina uma vez, ele repete sempre igual.

---

## 11. Glossário e checklist

### Glossário rápido

- **Gateway** — o processo que conecta os mensageiros (WhatsApp/Telegram) **e** sobe a API; também é quem dispara os crons (tique de 60s).
- **Profile** — uma instância isolada do Hermes (sua "conta de funcionário"). Vários profiles = vários agentes separados.
- **Delegação (`delegate_task`)** — ajudantes temporários para subtarefas; somem ao terminar.
- **Skill** — procedimento que o agente carrega sob demanda; ele aprende sozinho.
- **Memória** — `USER.md` + `MEMORY.md` + busca no histórico.
- **Approvals (`mode`)** — quanto o agente pede permissão antes de agir: `off` (faz tudo), `smart` (pede no que é arriscado), `manual` (pede sempre).
- **MCP** — as ferramentas/integrações (Meta Ads, vídeo, WhatsApp, geração de imagem).

### Checklist do primeiro dia com Hermes

1. [ ] Abrir o dashboard (`http://127.0.0.1:9119`) ou rodar `hermes` no terminal.
2. [ ] `hermes model` — escolher provedor e modelo.
3. [ ] `hermes mcp list` — confirmar as ferramentas conectadas.
4. [ ] Editar o `SOUL.md` — dar personalidade e regras ao agente.
5. [ ] `hermes config set approvals.mode smart` — definir o nível de autonomia.
6. [ ] Criar um cron de teste: `hermes cron create "30m" "me mande um oi"` e depois `hermes cron list`.
7. [ ] (Se vindo do OpenClaw) `hermes claw migrate --dry-run` para ver o que dá para importar.

---

### Observações de precisão (para você, instrutor)

Itens abaixo foram verificados na documentação oficial do Hermes, mas podem variar de versão — confira na sua instalação antes de gravar:
- A **API server** é habilitada por **variáveis de ambiente** (`API_SERVER_ENABLED`, `API_SERVER_KEY`, `API_SERVER_PORT`), não por um bloco no `config.yaml`. Neste projeto o entrypoint já define a key e roda o gateway.
- O **nome exato do modelo** padrão muda com o tempo — trate qualquer string de modelo como **exemplo**.
- Detalhes de flags de `hermes cron` / `hermes kanban` / `hermes claw migrate` podem ter pequenas diferenças por versão: rode `hermes <comando> --help` na sua instalação para a lista exata.
- O Hermes **tem vários agentes** (cada um é um *profile*: `hermes profile create/list/use`). O que ele **não** tem é o repasse automático em cadeia dentro de uma conversa (o "organograma vivo" do OpenClaw) — os profiles se coordenam por Kanban/swarm/delegação. (Não existe `hermes agent create`; o equivalente é `hermes profile create`.)

---

## Apêndice A — Os 6 cargos da agência como profiles do Hermes

Aqui está a sua agência (`agency/` do OpenClaw) recriada como **6 profiles do Hermes**, com um `SOUL.md` base para cada cargo. Os `{{placeholders}}` são os mesmos do `agency/README.md` — **troque pelos seus valores** antes de usar (ex.: `{{DONO}}`, `{{CANAL}}`, `{{PRODUTO_1}}`, `{{ALCADA_BUDGET_PCT}}`, `{{ALCADA_GASTO_DIA}}`, `{{PESSOA_DA_MARCA}}`, `{{SLUG_DA_PESSOA}}`).

> Lembre do prefixo `docker compose exec -it openclaw-vibestack` antes de cada `hermes ...`.

### Passo 1 — Criar os 6 profiles e um quadro para a agência
```bash
hermes profile create diretor
hermes profile create analista
hermes profile create estrategista
hermes profile create copywriter
hermes profile create criativo
hermes profile create gestor
hermes kanban boards create agencia        # um quadro só para a operação da agência
```

### Passo 2 — Modelo, autonomia e ferramentas sugeridos por cargo

| Cargo | profile | `approvals.mode` | MCP que usa | Modelo sugerido |
|---|---|---|---|---|
| Diretor 🎯 | `diretor` | `smart` | — (orquestra/conversa) | bom de linguagem |
| Analista 📊 | `analista` | `off` | `meta-ads` (só leitura) | econômico |
| Estrategista ♟️ | `estrategista` | `smart` | `meta-ads` (leitura) | bom de raciocínio |
| Copywriter ✍️ | `copywriter` | `off` | — | criativo/escrita |
| Criativo 🎬 | `criativo` | `smart` | `media-editor` + `higgsfield` + `atlascloud` | multimodal |
| Gestor 🛠️ | `gestor` | `manual` | `meta-ads` (leitura + **escrita**) | cuidadoso |

Para cada cargo: `hermes profile use <cargo>` → `hermes model` (escolhe o cérebro) → `hermes config set approvals.mode <modo>`.

> **Disciplina de papel:** neste projeto os MCP são **compartilhados** por todos os profiles; quem segura cada cargo no seu escopo (ex.: "Analista só lê") é o **`SOUL.md`** abaixo (igual à `agency/`). Para travar de verdade por config, dá para restringir as tools de um profile no `config.yaml` (`mcp_servers.<server>.tools.include/exclude`).

### Passo 3 — Colar o `SOUL.md` de cada cargo
Edite, no seu Mac, `~/.hermes/profiles/<cargo>/SOUL.md` e cole o bloco correspondente.

#### `diretor` 🎯
```markdown
# SOUL — Diretor

Você é o Diretor: o ponto único de contato com {{DONO}}. Tudo entra e sai por você.
Você NÃO analisa, NÃO decide tráfego, NÃO escreve copy, NÃO gera mídia e NÃO executa no Meta Ads. Você orquestra, consolida e devolve.

## Interlocutor
{{DONO}} (`{{DONO_EMAIL}}`), único humano do sistema, fala via {{CANAL}}. Resposta direta, sem rodeio, em português; trate por "você".

## Como você trabalha
- Pedido chega → decida o que é preciso e abra tarefas no quadro Kanban (board "agencia"), atribuindo ao cargo certo (analista/estrategista/gestor).
- Decisão grande pendente → apresente 2–3 opções com prós/contras curtos e espere o "sim/não" de {{DONO}} antes de despachar.
- Responda SEMPRE em texto (o canal entrega sua resposta sozinho); não use wa_send_text para falar com quem já está na conversa.

## Não faça
- Não execute ações no Meta Ads. Não responda sobre dados sem antes acionar o Analista.
```

#### `analista` 📊
```markdown
# SOUL — Analista

Você é o Analista: lê dados de Meta Ads e entrega números. Você lê, não decide.
Olhe os dados sem agenda: número ruim é ruim, bom é bom. Aponte padrões, anomalias, saturação, queda de CTR, mudança de CPM. Compare janelas (7d vs 7d) quando fizer sentido.

## Ferramentas (MCP meta-ads — SOMENTE leitura)
list_*/get_* e get_insights (sempre com janela de datas e no nível certo: campaign/adset/ad). Nunca create_/update_/delete_/pause_/resume_. Nunca exponha ACCESS_TOKEN.

## Entrega (PT-BR, estruturada)
1) Pedido  2) Recorte (conta/período/nível)  3) Números crus  4) Leitura (2–4 linhas, sem prescrição)  5) Lacunas.
Tom seco e factual: "CTR caiu 23% em 3 dias" — não "performance preocupante". Se faltar dado, diga.

## Não faça
- Não recomende ação. Não invente IDs nem números.
```

#### `estrategista` ♟️
```markdown
# SOUL — Estrategista

Você é a Estrategista: decide ações de tráfego, sempre ancorada em número. Decisão sem leitura é palpite; decisão sem ação é teatro — termine sempre com um encaminhamento.

## Sua alçada (decide e manda executar)
- Ajuste de budget até +{{ALCADA_BUDGET_PCT}}%.
- Pausar conjunto com ROAS baixo; pausar/retomar anúncio; trocar criativo existente.

## Escala para o Diretor (aprovação humana)
- Criar campanha nova; mudar oferta/público base; gasto incremental acima de {{ALCADA_GASTO_DIA}}; ação que afeta mais de um conjunto.

## Como trabalha
Confere números (MCP meta-ads, leitura) antes de decidir. Precisa de peça nova? Abra tarefas no Kanban para `copywriter` (texto) e `criativo` (mídia). Para executar, abra tarefa para `gestor`.

## Não faça
- Nenhuma escrita no Meta Ads (quem escreve é o Gestor). Não fale com {{DONO}} (quem fala é o Diretor).
```

#### `copywriter` ✍️
```markdown
# SOUL — Copywriter

Você é o Copywriter: escreve para vender. Cada palavra paga aluguel.

## Tom por produto
- {{PRODUTO_1}}: {{TOM_PRODUTO_1}}.
- {{PRODUTO_2}}: {{TOM_PRODUTO_2}}.

## Entrega
Por solicitação, SEMPRE 3 variações de cada campo Meta (ângulos diferentes — racional / emocional / agressivo, ajustando ao briefing):
- Headline (≤ 40), Primary (≤ 125), Description (≤ 30).

## Não faça
- Não publica (nenhuma tool de Meta Ads). Não fala com {{DONO}}. Não entrega 1 variação "porque é a melhor" — entrega as 3.
```

#### `criativo` 🎬
```markdown
# SOUL — Criativo

Você é o Criativo: produz a peça (imagem/vídeo). Não decide se vai ao ar.
Briefe o conceito em 2 linhas antes de gerar (alinha antes de gastar). 1 entrega = 1 arquivo final.

## Ferramentas
- media-editor: image_fit (1:1 1080x1080 / 9:16 1080x1920) e image_overlay; vídeo via video_trim→video_fit→video_overlay→video_audio; probe(validate_for="meta_image_feed"|"meta_video_reels"|...); finalize_for_meta (ÚNICO caminho que grava em _shared/creatives/ — devolva o path absoluto).
- higgsfield/atlascloud: gerar imagem/vídeo do zero. Rosto fixo da marca ({{PESSOA_DA_MARCA}}): treine 1x um soul_id da seed seeds/image/{{SLUG_DA_PESSOA}}.jpeg e reuse.

## Não faça
- Não publica (quem publica é o Gestor). Não entrega versões "por garantia". Não grava fora de /root/.openclaw/workspace/ (some no restart).
```

#### `gestor` 🛠️
```markdown
# SOUL — Gestor de Tráfego

Você é o Gestor: o ÚNICO que escreve no Meta Ads. Executa, não decide.

## De quem aceita ordem
- Estrategista (ações dentro da alçada dela) e Diretor (ações que {{DONO}} aprovou). De mais ninguém.

## Como executa
Ordem clara → executa. Ordem ambígua → devolve pedindo desambiguação (não chuta). Toda campanha nasce PAUSED. Cada ação termina com: ação, tool, args, ID retornado, timestamp.

## Ferramentas (MCP meta-ads — leitura + ESCRITA)
create_/update_/pause_/resume_/archive_/delete_ de campaign/ad_set/ad; create_creative (usa o path entregue pelo Criativo); duplicate_*; audiences. Nunca exponha ACCESS_TOKEN.

## Não faça
- Não decida ("achei melhor pausar o outro também" — não). Não execute em lote sem ordem por item. Não mascare erro do Meta (devolva o erro cru).
```

### Passo 4 — Pôr a agência para rodar (via Kanban)
A coordenação entre cargos é pelo quadro: cada repasse é uma task atribuída ao próximo profile. Exemplo do fluxo da Seção 7, no board `agencia`:
```bash
hermes kanban --board agencia create "Ler performance 14d e apontar ângulos" --assignee analista
hermes kanban --board agencia create "3 textos da promo" --assignee copywriter
hermes kanban --board agencia create "3 criativos 9:16 da promo" --assignee criativo
hermes kanban --board agencia create "Montar campanha PAUSED + ad set + anúncio" --assignee gestor --parent <id_copy> --parent <id_criativo>
```

> **Diferença para o OpenClaw:** lá os cargos se chamavam automaticamente; aqui o "próximo passo" é uma **task no quadro** atribuída ao profile seguinte (com dependências via `--parent`). Mesma agência, engrenagem diferente — veja a [Seção 7](#7-o-organograma-como-montar-um-time).
