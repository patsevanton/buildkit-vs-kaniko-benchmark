# Multi-stage Dockerfile — проект ml-pytorch (PyTorch inference).
# Профиль: лёгкая pip-установка torch + скачивание ~1.28 ГБ весов
# (bert-large-uncased/pytorch_model.bin) в BUILD-стадии.
# Слой кэшируется; замеряется именно время сетевого pull большого слоя.
# Бакет создаётся Terraform'ом (weights.tf), файл заливается один раз — см. TODO.md.
FROM python:3.11-slim AS builder
WORKDIR /src
COPY requirements.txt ./
# torch качаем только CPU-версию из официального индекса PyTorch
# (без CUDA-зависимостей — иначе слои раздуются на ГБ).
RUN pip3 install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cpu \
      --extra-index-url https://pypi.org/simple \
      torch==2.8.0 \
    && pip3 install --no-cache-dir -r requirements.txt

ARG WEIGHTS_URL=https://storage.yandexcloud.net/kaniko-vs-buildkit-weights/model.bin
RUN curl -fSL -o /src/model.bin "$WEIGHTS_URL"

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /src/model.bin ./model.bin
COPY app.py ./
EXPOSE 8080
CMD ["python3", "app.py"]