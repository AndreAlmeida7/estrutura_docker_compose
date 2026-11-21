# Build do React
FROM node:18.17.0-alpine AS build
WORKDIR /app

# o Cypress só é usado em testes, não precisa baixar o binário
ENV CYPRESS_INSTALL_BINARY=0
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./
# o front chama ${REACT_APP_BACKEND_URL}/create, então as requisições vão para /api no próprio nginx
ENV REACT_APP_BACKEND_URL=/api
RUN npm run build

# NGINX servindo o build e fazendo o proxy para o backend
FROM nginx:1.28-alpine
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html
