# Frontend React servido pelo NGINX, que também atua como proxy reverso / load balancer.
# Build context: raiz do repositório (precisa de frontend/ e nginx/).
ARG NODE_VERSION=18.17.0
ARG NGINX_VERSION=1.28-alpine

# ---------- Stage 1: build do React ----------
FROM node:${NODE_VERSION}-alpine AS build
WORKDIR /app

# Cypress é devDependency apenas para testes E2E; não baixa o binário no build
ENV CYPRESS_INSTALL_BINARY=0

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY frontend/ ./

# O frontend chama ${REACT_APP_BACKEND_URL}/create e /guess/<id>.
# Com "/api" as chamadas ficam relativas ao próprio NGINX, que as encaminha ao backend.
ARG REACT_APP_BACKEND_URL=/api
ENV REACT_APP_BACKEND_URL=${REACT_APP_BACKEND_URL}
RUN npm run build

# ---------- Stage 2: NGINX ----------
FROM nginx:${NGINX_VERSION}
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/nginx-health || exit 1
