FROM python:3.13-slim-bookworm@sha256:a5a7017efc5969e00ae2b91c8eb0631049a569652aa4ffc4501769049ae45c72
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY app/backend/requirements.txt .
RUN pip install --no-cache-dir --require-hashes --only-binary=:all: -r requirements.txt
COPY app/backend/api.py app/backend/bootstrap.py app/backend/schema.sql ./
USER 10001:10001
CMD ["sh", "-c", "python bootstrap.py && exec gunicorn --bind 0.0.0.0:8000 --worker-class gthread --workers 2 --threads 2 --timeout 15 --access-logfile - --access-logformat '%(m)s %(U)s %(s)s %(L)s' api:app"]
