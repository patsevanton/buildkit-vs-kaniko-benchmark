#!/bin/sh
# Помощник: получить короткоживущий IAM-токен сервисного аккаунта ноды
# из метаданных Yandex Compute (GCE-формат). Токен живёт ~12 часов.
# Используется для аутентификации push в Yandex Container Registry
# (username=iam, password=access_token), а также для Kaniko/BuildKit.
set -eu

curl -s -H "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])"