#!/bin/sh
# Помощник: записать docker config (/.docker/config.json) для аутентификации
# в Yandex Container Registry через IAM-токен сервисного аккаунта ноды.
# Аргументы: $1 = registry server (registry.yandex.cloud/<registry-id>), $2 = IAM-токен.
set -eu

REGISTRY="${1:?registry server is required}"
TOKEN="${2:?iam token is required}"
mkdir -p "${DOCKER_CONFIG:-/kaniko/.docker}"
AUTH_B64="$(printf 'iam:%s' "$TOKEN" | base64 | tr -d '\n')"
cat > "${DOCKER_CONFIG:-/kaniko/.docker}/config.json" <<EOF
{
  "auths": {
    "cr.yandex": {"auth": "$AUTH_B64"},
    "registry.yandex.cloud": {"auth": "$AUTH_B64"}
  }
}
EOF
echo "docker config written to ${DOCKER_CONFIG:-/kaniko/.docker}/config.json"