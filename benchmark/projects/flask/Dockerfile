# Multi-stage Dockerfile для замера kaniko vs buildkit — проект flask.
# Одинаковый для обоих инструментов: сравниваем только время сборки,
# потребление ресурсов и кэширование.
#
# Профиль: базовый «pip install» в multi-stage (baseline).

# ---- Stage 1: build ----
FROM debian:bookworm-slim AS builder

RUN echo "deb http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list.d/base.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git build-essential python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

RUN pip3 install --no-cache-dir \
       --no-warn-script-location \
       flask==3.0.3 requests==2.32.3 gunicorn==23.0.0 \
    && chmod +x /src/app.sh

# ---- Stage 2: runtime ----
FROM debian:bookworm-slim

COPY --from=builder /usr/local/bin/python3 /usr/local/bin/
COPY --from=builder /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/
COPY --from=builder /src/app.sh /app/app.sh

RUN useradd -m app \
    && mkdir -p /app \
    && chown -R app:app /app

USER app
WORKDIR /app

EXPOSE 8080
CMD ["/bin/sh", "/app/app.sh"]