#!/usr/bin/env bash
#
# Удаление всех образов (и, опционально, репозиториев) из Yandex Container Registry
# через REST API (gRPC-gateway) — без CLI `yc`.
#
# Использование:
#   delete-registry-images.sh <registry_id> [--with-repositories]
#
# Аутентификация — через IAM-токен (переменная окружения YC_TOKEN).
# Получить токен: export YC_TOKEN=$(yc iam create-token)

set -euo pipefail

REGISTRY_ENDPOINT="https://container-registry.api.cloud.yandex.net/container-registry/v1"

usage() {
  echo "Использование: $0 <registry_id> [--with-repositories]" >&2
  echo "  registry_id         ID реестра (cr...); можно получить: terraform output -raw registry_id; echo" >&2
  echo "  --with-repositories дополнительно удалить пустые репозитории реестра" >&2
  echo "Env: YC_TOKEN — IAM-токен сервисного аккаунта (yc iam create-token)" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
REGISTRY_ID="$1"
WITH_REPOS=false
[[ $# -ge 2 && "$2" == "--with-repositories" ]] && WITH_REPOS=true

: "${YC_TOKEN:?Установите YC_TOKEN (yc iam create-token)}"

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }

api() { # api <method> <path> [json_body]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" -H "Authorization: Bearer $TOKEN")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")
  curl "${args[@]}" "$REGISTRY_ENDPOINT$path"
}

TOKEN="$YC_TOKEN"

log "Получение списка образов реестра $REGISTRY_ID..."
PAGE_TOKEN=""
DELETED=0
while :; do
  URL="/images?registryId=$REGISTRY_ID"
  [[ -n "$PAGE_TOKEN" ]] && URL="$URL&pageToken=$PAGE_TOKEN"
  RESP=$(api GET "$URL")
  IMAGE_IDS=$(jq -r '.images[]?.id' <<<"$RESP" 2>/dev/null || true)
  PAGE_TOKEN=$(jq -r '.nextPageToken // empty' <<<"$RESP")

  while read -r id; do
    [[ -n "$id" ]] || continue
    log "Удаление образа $id..."
    api DELETE "/images/$id" >/dev/null
    DELETED=$((DELETED + 1))
  done <<<"$IMAGE_IDS"

  [[ -n "$PAGE_TOKEN" ]] || break
done
log "Удалено образов: $DELETED"

if $WITH_REPOS; then
  log "Получение списка репозиториев реестра $REGISTRY_ID..."
  PAGE_TOKEN=""
  REPOS=0
  while :; do
    URL="/repositories?registryId=$REGISTRY_ID"
    [[ -n "$PAGE_TOKEN" ]] && URL="$URL&pageToken=$PAGE_TOKEN"
    RESP=$(api GET "$URL")
    REPO_IDS=$(jq -r '.repositories[]?.id' <<<"$RESP" 2>/dev/null || true)
    PAGE_TOKEN=$(jq -r '.nextPageToken // empty' <<<"$RESP")

    while read -r id; do
      [[ -n "$id" ]] || continue
      log "Удаление репозитория $id..."
      api DELETE "/repositories/$id" >/dev/null
      REPOS=$((REPOS + 1))
    done <<<"$REPO_IDS"

    [[ -n "$PAGE_TOKEN" ]] || break
  done
  log "Удалено репозиториев: $REPOS"
fi

log "Готово. Теперь можно выполнить 'terraform destroy'."
