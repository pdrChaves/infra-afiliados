# Setup da Infraestrutura — Automação de Afiliados

Infra base: **n8n + Postgres via Docker**. Tudo que não depende da Shopee,
pronto pra rodar enquanto as aprovações de afiliado/API saem.

---

## Pré-requisitos

- **Docker Desktop** instalado e rodando (Windows/Mac) ou Docker Engine (Linux).
  - Verifica no terminal: `docker --version` e `docker compose version`
- **Aviso WSL/Windows:** se você usa o Vanguard (anticheat do Valorant), ele
  conflita com a virtualização do WSL2/Docker. Se o Docker não subir, cheque
  se o Vanguard está ativo. Não dá pra rodar os dois ao mesmo tempo com
  Hyper-V em alguns setups.

---

## Passo 1 — Montar a pasta do projeto

Estrutura final:

```
afiliados-automacao/
├── docker-compose.yml
├── .env                 <- você cria a partir do .env.example
├── .env.example
├── .gitignore
└── init/
    └── 01_schema.sql    <- roda sozinho na 1ª subida do Postgres
```

Coloque todos os arquivos baixados nessa estrutura.

---

## Passo 2 — Criar o arquivo .env

1. Copie `.env.example` para `.env` (sem o `.example`).
2. Preencha de verdade:
   - `POSTGRES_PASSWORD` → senha forte
   - `N8N_PASSWORD` → senha do painel
   - `N8N_ENCRYPTION_KEY` → chave aleatória longa. Gere com:
     - PowerShell: `[guid]::NewGuid().ToString()`
     - Git Bash/WSL: `openssl rand -hex 24`

> ⚠️ A `N8N_ENCRYPTION_KEY` não pode mudar depois. Se mudar, o n8n perde acesso
> a todas as credenciais salvas (tokens da Shopee, Telegram, etc).

---

## Passo 3 — Subir os containers

No terminal, dentro da pasta do projeto:

```bash
docker compose up -d
```

`-d` = roda em background. Primeira vez demora (baixa as imagens).

Verifica se subiu:

```bash
docker compose ps
```

Os dois (`afiliados_postgres` e `afiliados_n8n`) devem estar `running`/`healthy`.

Ver logs se algo der errado:

```bash
docker compose logs -f n8n
docker compose logs -f postgres
```

---

## Passo 4 — Confirmar o schema do banco

O `01_schema.sql` roda automático na primeira subida. Confirma:

```bash
docker exec -it afiliados_postgres psql -U afiliados -d ofertas -c "\dt"
```

Deve listar `ofertas` e `publicacoes_log`.

> Se você já tinha subido antes SEM o init e quer recriar do zero:
> `docker compose down -v` (o `-v` apaga os volumes — perde TUDO, inclusive
> workflows do n8n) e sobe de novo. Use só se for início.

---

## Passo 5 — Acessar o painel do n8n

1. Navegador → `http://localhost:5678`
2. Login com `N8N_USER` / `N8N_PASSWORD` do `.env`
3. Na primeira vez o n8n pede pra criar a conta de owner — siga.

---

## Passo 6 — Criar o Bot do Telegram (destino = GRUPO privado)

O destino é um **grupo privado só seu**, usado como checklist operacional:
a automação posta as ofertas formatadas lá, e você marca/copia pro WhatsApp.
A ORDEM abaixo importa — é onde mais gente trava no setup de bot em grupo.

1. No Telegram, fale com **@BotFather**
2. `/newbot` → escolha nome e username (termina em `bot`)
3. Guarde o **token** (formato `123456:ABC-DEF...`)

4. **Desligue o Group Privacy do bot** (faça ANTES de adicionar ao grupo):
   - @BotFather → `/mybots` → selecione seu bot → **Bot Settings**
     → **Group Privacy** → **Turn off**
   - Por quê: por padrão o bot só "enxerga" mensagens que começam com `/` ou
     que respondem a ele. Com privacy LIGADO, o `getUpdates` pode não retornar
     as mensagens do grupo e você não acha o `chat_id`.

5. Crie o **grupo privado** no Telegram.

6. **Promova o grupo a supergroup de propósito** (evita dor de cabeça futura):
   - Configurações do grupo → torne o histórico visível para novos membros
     (ou outra config de supergroup). O Telegram converte o grupo em supergroup.
   - Por quê: grupo comum tem id curto (`-123456789`). Quando vira supergroup
     (às vezes automático), o id muda para `-100xxxxxxxxxx` e o antigo PARA de
     funcionar — o n8n daria erro "chat not found". Forçar a conversão agora
     fixa o id definitivo antes de você cadastrá-lo.

7. Adicione o bot ao grupo **como administrador**.

8. Mande qualquer mensagem no grupo.

9. Pegue o **chat_id**:
   - Acesse no navegador:
     `https://api.telegram.org/bot<SEU_TOKEN>/getUpdates`
   - Procure `"chat":{"id":-100...}` — o id do grupo/supergroup é **negativo**.

Guarde **token** e **chat_id** — viram credencial no n8n no Passo 8.

> Se um dia os posts pararem de chegar com erro "chat not found", o id do
> grupo migrou. Refaça o getUpdates (passos 8–9) e atualize o chat_id no n8n.

---

## Passo 7 — Conectar o n8n ao Postgres (credencial)

No n8n:
1. Menu → **Credentials** → **New** → busque **Postgres**
2. Preencha:
   - Host: `postgres`  ← nome do serviço no compose, NÃO localhost
   - Database: `ofertas`
   - User: `afiliados`
   - Password: (a do `.env`)
   - Port: `5432`
   - SSL: desligado
3. **Save** → deve testar conexão com sucesso.

---

## Passo 8 — Conectar o n8n ao Telegram (credencial)

1. Credentials → New → **Telegram**
2. Cole o **token** do BotFather
3. Save

---

## O que fica pronto agora (sem Shopee)

- [x] n8n rodando e acessível
- [x] Postgres com schema `ofertas` + `publicacoes_log`
- [x] Bot do Telegram criado, privacy mode OFF, adicionado a grupo privado
- [x] Credenciais Postgres + Telegram salvas no n8n

## O que falta (depende de aprovação externa)

- [ ] Conta de afiliado Shopee aprovada (3–5 dias úteis)
- [ ] API oficial Shopee solicitada e liberada (formulário no painel + análise)
- [ ] Credencial Gemini (Google AI Studio — gratuito, pega quando quiser)

## Próximos workflows (depois das chaves)

1. **Captação:** Shopee API → dados do produto → INSERT na fila
2. **Enriquecimento:** Gemini gera `copy_texto` dos itens pendentes
3. **Publicação:** Schedule → pega da `v_fila_publicacao` → Telegram → marca publicado
