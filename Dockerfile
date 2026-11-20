# Backend Flask do jogo de adivinhação
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependências primeiro para aproveitar cache de camadas
COPY requirements.txt .
RUN pip install -r requirements.txt

# Apenas o código necessário em runtime
COPY run.py .
COPY guess/ guess/
COPY repository/ repository/

# Healthcheck/liveness (infra): valida a conexão com o banco e força restart se ela quebrar
COPY docker/healthcheck.py /usr/local/bin/healthcheck.py

RUN useradd --system --no-create-home appuser
USER appuser

# Valores padrão; sobrescritos pelo docker-compose
ENV FLASK_APP=run.py \
    FLASK_DB_TYPE=postgres \
    FLASK_DB_PORT=5432

EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
  CMD ["python", "/usr/local/bin/healthcheck.py"]

CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
