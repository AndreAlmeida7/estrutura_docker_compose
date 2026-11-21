# Guess Game com Docker Compose

Estrutura em Docker Compose para o [jogo de adivinhação](https://github.com/fams/guess_game): backend Flask, banco Postgres e um NGINX que serve o frontend React e distribui as requisições entre as instâncias do backend.

O código do jogo não foi alterado. A documentação original está em `README-jogo.md`.

## Como rodar

Precisa só do Docker com o Compose v2.

```bash
git clone https://github.com/AndreAlmeida7/estrutura_docker_compose.git
cd estrutura_docker_compose
docker compose up -d --build
```

Depois que `docker compose ps` mostrar os serviços como `healthy`, acesse:

**http://localhost:8080**

Se a porta 8080 já estiver em uso, crie um arquivo `.env` com `HTTP_PORT=8081` (ou outra porta) e rode o comando de novo.

Para parar: `docker compose down`. Os dados do banco continuam no volume; para apagar tudo, use `docker compose down -v`.

## Arquivos

- `docker-compose.yml`: define os serviços `db`, `backend` e `nginx`
- `Dockerfile`: imagem do backend
- `frontend/Dockerfile`: compila o React e gera a imagem do NGINX com o build
- `nginx/default.conf`: proxy reverso e balanceamento de carga
- `postgres/init/01-schema.sql`: cria a tabela na primeira inicialização do banco
- `docker/healthcheck.py`: verificação de saúde do backend
- `.env.example`: variáveis que podem ser alteradas (versões, porta, credenciais)

## Decisões de design

**Serviços.** São três: `db` (Postgres 16), `backend` (Flask, com 3 réplicas) e `nginx`. O NGINX faz dois papéis no mesmo container: entrega os arquivos estáticos do React e repassa as chamadas da API para o backend. O backend não expõe porta para fora, só é acessado pelo NGINX.

O frontend monta as URLs como `${REACT_APP_BACKEND_URL}/create`. No build, essa variável recebe `/api`, então o navegador chama `/api/create` no próprio NGINX, que encaminha para `backend:5000/create`. Assim não é preciso fixar o endereço do backend no frontend nem lidar com CORS.

**Balanceamento de carga.** As 3 réplicas do backend respondem pelo mesmo nome (`backend`) no DNS do Docker. O NGINX usa esse nome em um `upstream` com round-robin, que é suficiente aqui porque o backend não guarda estado: tudo fica no banco. A opção `resolve` faz o NGINX consultar o DNS a cada 10 segundos, então réplicas novas (via `--scale`) ou reiniciadas entram no rodízio sem reiniciar o NGINX. Se uma réplica falha, a requisição é reenviada para outra (`proxy_next_upstream`).

Cada resposta da API vem com o header `X-Upstream`, indicando qual réplica atendeu.

**Redes.** Há duas redes: `frontend`, onde fica só o NGINX com a porta publicada, e `backend`, interna, com NGINX, backend e banco. Banco e backend ficam sem acesso externo.

**Volume.** Os dados do Postgres ficam no volume nomeado `pgdata`. Eles sobrevivem a `docker compose down`, à recriação dos containers e à troca de versão da imagem.

**Resiliência.** Todos os serviços usam `restart: unless-stopped`, então um container que cai é reiniciado pelo Docker. O backend só sobe quando o banco está pronto (healthcheck com `pg_isready`), e o NGINX só sobe quando o backend está saudável.

Dois ajustes vieram de testes:

- Com as 3 réplicas subindo juntas em um banco vazio, todas tentam criar a tabela ao mesmo tempo e algumas falham. Por isso a tabela é criada antes, no script de init do Postgres.
- O backend abre uma única conexão com o banco e não reconecta. Se o Postgres reiniciar, o backend continua de pé, mas responde erro em tudo. O healthcheck (`docker/healthcheck.py`) testa uma consulta real e, se der erro 500, encerra o processo para o Docker subir o container de novo, já com uma conexão nova.

## Atualizando os componentes

Cada componente é uma imagem com versão definida por variável:

```
BACKEND_VERSION=1.0.0
FRONTEND_VERSION=1.0.0
POSTGRES_VERSION=16-alpine
```

Sem `.env`, valem esses valores padrão. Para mudar, copie o modelo (`cp .env.example .env`, ou `copy` no Windows), altere a versão e recrie só o serviço:

```bash
# backend (depois de atualizar o código)
docker compose up -d --build backend

# frontend / nginx
docker compose up -d --build nginx

# banco: basta trocar a tag, por exemplo POSTGRES_VERSION=16.6-alpine
docker compose up -d db
```

Para voltar uma versão, é só restaurar o valor anterior no `.env` e rodar `docker compose up -d <serviço>`. A imagem antiga continua no cache local.

Uma observação sobre o Postgres: trocar de versão minor (16.x) funciona direto, mas uma versão major (16 para 17) usa outro formato de dados. Nesse caso é preciso fazer backup com `pg_dumpall`, recriar o volume e restaurar.

## Testando

```bash
# balanceamento: o IP muda a cada requisição
for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null http://localhost:8080/api/health | grep -i x-upstream; done

# derrubar uma réplica: o Docker reinicia e a API continua respondendo pelas outras
docker compose exec backend python -c "import os,signal; os.kill(1, signal.SIGINT)"
docker compose ps backend

# reiniciar o banco: o backend se recupera sozinho
docker compose restart db
```

No PowerShell, o teste de balanceamento fica:

```powershell
1..6 | % { (Invoke-WebRequest http://localhost:8080/api/health -UseBasicParsing).Headers["X-Upstream"] }
```

Para testar a persistência, crie um jogo pelo site, rode `docker compose down` e `docker compose up -d`, e use o mesmo `game_id` na tela Breaker.
