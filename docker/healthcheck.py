"""Healthcheck/liveness do backend (infraestrutura, não altera a aplicação).

O backend abre UMA conexão psycopg2 no boot e não reconecta. Se o Postgres reiniciar,
o processo continua de pé (e /health continua 200), mas toda rota que usa o banco
passa a responder 500. Este check consulta o banco de verdade via /guess de um jogo
semeado em postgres/init/01-schema.sql:

  - 200          -> saudável
  - HTTP 500     -> conexão com o banco quebrada: envia SIGINT ao PID 1 (flask),
                    o container termina e a restart policy sobe um novo, que reconecta
  - sem conexão  -> app ainda subindo: apenas reporta unhealthy, sem matar
"""
import json
import os
import signal
import sys
import urllib.error
import urllib.request

URL = "http://127.0.0.1:5000/guess/__healthcheck__"

req = urllib.request.Request(
    URL,
    data=json.dumps({"guess": "x"}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(req, timeout=3):
        sys.exit(0)
except urllib.error.HTTPError as e:
    if e.code >= 500:
        # SIGINT porque o Python trata esse sinal (KeyboardInterrupt) mesmo como PID 1;
        # SIGTERM/SIGKILL enviados de dentro do container ao PID 1 seriam ignorados.
        os.kill(int(os.environ.get("HEALTHCHECK_TARGET_PID", "1")), signal.SIGINT)
    sys.exit(1)
except Exception:
    sys.exit(1)
