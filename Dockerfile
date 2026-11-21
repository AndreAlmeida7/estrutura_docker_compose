FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY run.py .
COPY guess/ guess/
COPY repository/ repository/
COPY docker/healthcheck.py /healthcheck.py

ENV FLASK_APP=run.py
EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
  CMD ["python", "/healthcheck.py"]

CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
