# Guess Game — Orquestração com Docker Compose

Infraestrutura em Docker Compose para o [jogo de adivinhação](https://github.com/fams/guess_game) (Flask + React + Postgres), com proxy reverso NGINX balanceando carga entre múltiplas réplicas do backend.

> O código das aplicações (`guess/`, `repository/`, `run.py`, `frontend/src/`) **não foi alterado**. Todo o trabalho está nos arquivos de infraestrutura listados abaixo. A documentação original do jogo está em [`README-jogo.md`](README-jogo.md).

## TL;DR

```bash
git clone https://github.com/AndreAlmeida7/estrutura_docker_compose.git
cd estrutura_docker_compose
docker compose up -d --build
```

**URL da aplicação: http://localhost:8080**

Não precisa de configuração prévia: o `docker-compose.yml` já traz defaults para todas as variáveis. Para customizar versões, porta ou réplicas, copie `.env.example` para `.env` e edite.

- `http://localhost:8080/` — frontend (Home)
- `http://localhost:8080/maker` — criar jogo
- `http://localhost:8080/breaker` — adivinhar
- `http://localhost:8080/api/...` — API do backend (via proxy)

A porta pode ser alterada pela variável `HTTP_PORT` (ver `.env.example`).

---

## Arquitetura

```
                    ┌──────────────────────── frontend-net ───────┐
  Navegador ──:8080─┤  nginx (guess-frontend)                     │
                    │   ├─ /        → arquivos estáticos do React │
                    │   └─ /api/*   → upstream "backend"          │
                    └───────────────┬─────────────────────────────┘
                                    │ round-robin + failover
                    ┌───────────────┴──── backend-net (internal) ─┐
                    │  backend #1   backend #2   backend #3       │
                    │  (guess-backend, Flask :5000)               │
                    │               │                             │
                    │           db (postgres:16) ── volume pgdata │
                    └─────────────────────────────────────────────┘
```

### Arquivos de infraestrutura

| Arquivo | Função |
|---|---|
| `docker-compose.yml` | Orquestra os serviços `db`, `backend` (3 réplicas) e `nginx` |
| `.env.example` | Modelo do `.env`: versões das imagens, nº de réplicas, porta e credenciais (defaults já embutidos no compose) |
| `Dockerfile` | Imagem do backend Flask (Python 3.12) |
| `frontend/Dockerfile` | Build multi-stage: Node 18.17 compila o React → NGINX serve o build e faz o proxy |
| `nginx/default.conf` | Proxy reverso, balanceamento de carga e roteamento da SPA |
| `postgres/init/01-schema.sql` | Schema inicial do banco (executado só na criação do volume) |
| `docker/healthcheck.py` | Healthcheck/liveness do backend |
| `.dockerignore` | Mantém `node_modules`, `.git` etc. fora do contexto de build |

---

## Decisões de design

### Serviços

**`db` — Postgres 16 (alpine).** Imagem oficial, sem customização: a configuração vem por variáveis de ambiente e o schema por script de init. Versão major fixada (`16`) porque o formato do diretório de dados muda entre majors.

**`backend` — Flask.** Imagem `python:3.12-slim` com só o necessário em runtime (`run.py`, `guess/`, `repository/`), rodando com usuário não-root. A configuração usa as mesmas variáveis `FLASK_DB_*` do `start-backend.sh` original, injetadas pelo compose, com `FLASK_DB_HOST=db`. O backend não publica porta no host: só é acessível pelo NGINX.

**`nginx` — frontend + proxy reverso.** Um único container cumpre os dois papéis pedidos:
- Stage 1 (`node:18.17.0-alpine`): `npm ci` + `npm run build` com `REACT_APP_BACKEND_URL=/api`. O frontend faz `fetch(${REACT_APP_BACKEND_URL}/create)`, então as chamadas viram relativas (`/api/create`) e chegam no próprio NGINX, sem CORS nem URL de backend fixa no bundle.
- Stage 2 (`nginx:1.28-alpine`): serve o build estático e encaminha `/api/*` para o backend, removendo o prefixo (`/api/guess/abc` → `backend:5000/guess/abc`).
- `try_files ... /index.html` garante que as rotas da SPA (`/maker`, `/breaker`) funcionem no refresh.
- O binário do Cypress (devDependency só de testes E2E) não é baixado no build (`CYPRESS_INSTALL_BINARY=0`).

### Balanceamento de carga

O backend roda com `deploy.replicas: 3` (configurável via `BACKEND_REPLICAS`). O Docker registra todas as réplicas sob o mesmo nome DNS `backend`, e o NGINX as consome por um único `upstream`:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;   # DNS interno do Docker
upstream backend {
    zone backend_upstream 64k;
    server backend:5000 resolve max_fails=3 fail_timeout=10s;
}
```

- **Estratégia: round-robin** (padrão do NGINX). As requisições do jogo são curtas e homogêneas e o backend é stateless (todo o estado fica no Postgres), então não há ganho em `least_conn` ou afinidade de sessão (`ip_hash`).
- **`resolve` (NGINX ≥ 1.27.3):** o NGINX reconsulta o DNS a cada 10s. Réplicas adicionadas com `--scale` ou containers reiniciados com IP novo entram no pool sem reiniciar o NGINX. Sem isso, o NGINX resolveria o nome só no boot e ficaria com IPs velhos.
- **Failover:** `max_fails`/`fail_timeout` tiram uma réplica com problema do pool, e `proxy_next_upstream error timeout http_502 http_503 http_504` reenvia a requisição para outra réplica, de forma transparente pro usuário.
- **Observabilidade:** toda resposta da API traz o header `X-Upstream` com o IP da réplica que atendeu, o que permite ver o balanceamento acontecendo (ver [Validação](#validação)).

### Redes

- `frontend-net`: só o NGINX, é a única rede com porta publicada.
- `backend-net` (`internal: true`): NGINX, backends e Postgres. Sem rota para fora: banco e backend não ficam expostos no host nem na internet.

### Volumes e persistência

- Volume nomeado `pgdata` montado em `/var/lib/postgresql/data`. Os dados sobrevivem a `docker compose down`, à recriação de containers e à troca de versão da imagem. Só `docker compose down -v` apaga.
- `./postgres/init` é montado (read-only) em `/docker-entrypoint-initdb.d` e só roda quando o volume está vazio.

### Resiliência

| Mecanismo | O que resolve |
|---|---|
| `restart: unless-stopped` em todos os serviços | Container que cai (crash, OOM, erro de conexão no boot) é reiniciado automaticamente pelo Docker |
| Healthcheck do `db` (`pg_isready -h 127.0.0.1`) + `depends_on: service_healthy` | O backend só sobe com o banco aceitando conexões TCP. O `-h 127.0.0.1` evita um falso positivo durante o init: o servidor temporário do init só escuta via socket |
| Schema criado no init do Postgres | Evita uma race condition real: com 3 réplicas subindo juntas num banco vazio, o `CREATE TABLE IF NOT EXISTS` concorrente do backend falha em algumas réplicas (`duplicate key ... pg_type_typname_nsp_index`). Com a tabela já criada, o comando vira no-op |
| Healthcheck de liveness do backend (`docker/healthcheck.py`) | O backend abre **uma** conexão com o Postgres no boot e não reconecta. Se o banco reiniciar, o processo segue vivo mas toda rota responde 500. O healthcheck faz um `/guess` real num jogo semeado no init (`__healthcheck__`). Se receber 500, encerra o processo e a restart policy sobe um container novo, que reconecta. Se o app ainda está subindo (conexão recusada), só reporta unhealthy, sem derrubar |
| `depends_on.db.restart: true` | Num `docker compose restart db` ou num update do `db`, o compose reinicia o backend junto |
| Failover no NGINX + `resolve` | Uma réplica fora do ar não gera erro pro usuário. Quando ela volta, reentra no pool sozinha |
| Healthcheck do NGINX (`/nginx-health`) | Status visível em `docker compose ps` |

---

## Instalação e execução

### Pré-requisitos

- Docker Engine 24+ com Docker Compose v2.20+ (ou Docker Desktop recente no Windows/macOS)
- Porta 8080 livre (ou altere `HTTP_PORT` no `.env`)

### Subir

```bash
docker compose up -d --build
docker compose ps        # aguarde todos ficarem "healthy" (~20-40s no primeiro build)
```

Acesse **http://localhost:8080**.

### Como jogar

1. Em **Maker**, digite uma senha e envie. Guarde o `game_id` retornado.
2. Em **Breaker**, informe o `game_id` e tente adivinhar.

### Comandos úteis

```bash
docker compose logs -f backend          # logs de todas as réplicas
docker compose logs -f nginx
docker compose up -d --scale backend=5  # escala na hora; o NGINX enxerga em até 10s
docker compose down                     # para tudo, mantém os dados
docker compose down -v                  # para tudo e APAGA o banco
```

---

## Atualização dos componentes

Cada componente é uma imagem versionada, com as versões centralizadas em variáveis. Na primeira atualização, crie o `.env` a partir do modelo:

```bash
cp .env.example .env      # Windows: copy .env.example .env
```

```dotenv
BACKEND_VERSION=1.0.0       # tag da imagem guess-backend
FRONTEND_VERSION=1.0.0      # tag da imagem guess-frontend (React + NGINX)
POSTGRES_VERSION=16-alpine  # tag da imagem oficial do Postgres
NODE_VERSION=18.17.0        # imagem base do build do React
NGINX_VERSION=1.28-alpine   # imagem base do NGINX
```

Atualizar = **trocar a versão no `.env` e recriar só o serviço**. Nenhuma mudança no `docker-compose.yml` nem no código.

### Backend

```bash
# 1. Atualize o código (git pull) e incremente a versão no .env
BACKEND_VERSION=1.1.0
# 2. Gere a nova imagem e recrie apenas as réplicas do backend
docker compose up -d --build backend
```

### Frontend / NGINX

```bash
FRONTEND_VERSION=1.1.0        # nova versão do React e/ou da config do NGINX
# opcional: NGINX_VERSION=1.28.1-alpine para atualizar o NGINX base
docker compose up -d --build nginx
```

### Banco de dados

```bash
POSTGRES_VERSION=16.6-alpine   # minor/patch: só trocar a tag
docker compose up -d db        # dados preservados no volume pgdata; o backend é reiniciado junto
```

> **Upgrade de versão major** (ex.: 16 → 17): o formato do diretório de dados é incompatível entre majors. Faça dump e restore:
> ```bash
> docker compose exec db pg_dumpall -U postgres > backup.sql
> docker compose down && docker volume rm guess-game_pgdata
> # altere POSTGRES_VERSION=17-alpine no .env
> docker compose up -d db
> docker compose exec -T db psql -U postgres < backup.sql
> docker compose up -d
> ```

### Rollback

As tags antigas continuam no cache local. Basta voltar a versão no `.env` e rodar `docker compose up -d <serviço>` (sem `--build`): o compose reutiliza a imagem existente.

### Usando um registry (CI/CD)

As imagens já têm nome e tag (`guess-backend:${BACKEND_VERSION}`). Para publicar num registry, prefixe o nome (ex.: `ghcr.io/usuario/guess-backend:${BACKEND_VERSION}`) e use `docker compose build && docker compose push`. Em produção, rode `docker compose pull && docker compose up -d` e remova o bloco `build:`, assim a atualização passa a ser só trocar a tag.

---

## Validação

Com a stack de pé:

```bash
# 1. Frontend e rotas da SPA
curl -I http://localhost:8080/
curl -I http://localhost:8080/breaker

# 2. API via proxy
curl -X POST http://localhost:8080/api/create -H "Content-Type: application/json" -d '{"password":"docker"}'
curl -X POST http://localhost:8080/api/guess/<game_id> -H "Content-Type: application/json" -d '{"guess":"docker"}'

# 3. Balanceamento: o IP no X-Upstream alterna entre as réplicas
for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null http://localhost:8080/api/health | grep -i x-upstream; done

# 4. Restart automático: derruba o processo de uma réplica e vê o Docker reiniciá-la
docker compose exec backend python -c "import os,signal; os.kill(1, signal.SIGINT)"
docker compose ps backend      # a réplica volta sozinha; a API segue respondendo pelas outras

# 5. Persistência: os dados sobrevivem à recriação dos containers
docker compose down && docker compose up -d
curl -X POST http://localhost:8080/api/guess/<game_id> -H "Content-Type: application/json" -d '{"guess":"docker"}'   # {"result":"Correct"}

# 6. Banco reiniciado: o backend se recupera sozinho
docker compose restart db
```

No PowerShell, troque o `for` do item 3 por:
```powershell
1..6 | % { (Invoke-WebRequest http://localhost:8080/api/health).Headers["X-Upstream"] }
```

---

## Estrutura do repositório

```
.
├── docker-compose.yml
├── .env.example
├── .dockerignore
├── Dockerfile                  # backend
├── docker/healthcheck.py       # liveness do backend
├── nginx/default.conf          # proxy reverso + load balancer
├── postgres/init/01-schema.sql # schema inicial
├── frontend/
│   ├── Dockerfile              # build React + NGINX
│   └── src/ ...                # (original, sem alterações)
├── guess/ repository/ run.py   # backend (original, sem alterações)
├── README.md                   # este arquivo
└── README-jogo.md              # README original do jogo
```
