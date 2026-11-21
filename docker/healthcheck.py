# Healthcheck do backend. Faz um palpite no jogo "__healthcheck__" (criado no init do banco)
# para testar a conexão com o Postgres. O backend não reconecta sozinho se o banco reiniciar,
# então, se a resposta for 500, o processo é encerrado e o Docker sobe o container de novo.
import os
import signal
import sys
import urllib.error
import urllib.request

req = urllib.request.Request(
    "http://127.0.0.1:5000/guess/__healthcheck__",
    data=b'{"guess": "x"}',
    headers={"Content-Type": "application/json"},
)

try:
    urllib.request.urlopen(req, timeout=3)
except urllib.error.HTTPError as e:
    if e.code >= 500:
        os.kill(1, signal.SIGINT)  # SIGINT porque o Python, como PID 1, ignora SIGTERM
    sys.exit(1)
except Exception:
    sys.exit(1)  # app ainda subindo
