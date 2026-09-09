#!/usr/bin/env bash
#
# Запуск пайплайна бенчмарка только после освобождения GitLab Runner'а:
# скрипт ждёт, пока на раннере не останется джобов (running/pending), и лишь
# затем создаёт пайплайн.
#
# Зачем: тройка kaniko+buildkit+buildah одного проекта должна стартовать
# одновременно, иначе линии на дашборде Grafana начинаются в разное время.
# Раннер с concurrent=3 (gitlab-runner/values.yaml) при занятой тройке
# ставит джобы нового пайплайна в очередь, и тройка разъезжается по времени.
#
# Использование:
#   run-pipeline-when-idle.sh <project> [--branch main] [--interval 15] [--timeout 3600] [--dry-run]
#
#   <project>  имя репозитория в группе buildkit-vs-kaniko-benchmark
#              (nextjs, nuxtjs, golang, android, ml-pytorch)
#
# Примеры:
#   run-pipeline-when-idle.sh nextjs
#   run-pipeline-when-idle.sh ml-pytorch --branch main --interval 10
#   run-pipeline-when-idle.sh android --dry-run   # только дождаться простоя раннера
#
# Env:
#   GITLAB_TOKEN — GitLab Personal Access Token со скоупом api (read+write),
#                  нужен для запуска пайплайна. Берётся из terraform.tfvars:
#                    export GITLAB_TOKEN=$(sed -n 's/^gitlab_api_token\s*=\s*"\(.*\)"/\1/p' terraform.tfvars)
#   RUNNER_ID    — ID раннера; по умолчанию ищется в группе по тегу RUNNER_TAG.
#   RUNNER_TAG   — тег раннера (по умолчанию k8s-benchmark, см. gitlab-runner/values.yaml).
#   GITLAB_GROUP — группа проектов (по умолчанию buildkit-vs-kaniko-benchmark).

set -euo pipefail

GROUP="${GITLAB_GROUP:-buildkit-vs-kaniko-benchmark}"
RUNNER_TAG="${RUNNER_TAG:-k8s-benchmark}"
BRANCH="main"
INTERVAL=15
TIMEOUT=3600
DRY_RUN=false

usage() {
  sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }

[[ $# -ge 1 ]] || usage
PROJECT="$1"
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)  BRANCH="${2:?}"; shift 2 ;;
    --interval) INTERVAL="${2:?}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Неизвестный аргумент: $1" >&2; usage ;;
  esac
done

for cmd in glab jq; do
  command -v "$cmd" >/dev/null || { echo "Требуется $cmd" >&2; exit 1; }
done
: "${GITLAB_TOKEN:?Установите GITLAB_TOKEN (gitlab_api_token из terraform.tfvars)}"
export GITLAB_TOKEN

# Джобы в этих статусах занимают слоты раннера или ждут их.
BUSY_STATUSES=(running pending created preparing waiting_for_resource scheduled)

api() { glab api "$1"; }

runner_id() {
  if [[ -n "${RUNNER_ID:-}" ]]; then
    echo "$RUNNER_ID"
    return
  fi
  api "groups/$GROUP/runners?tag_list=$RUNNER_TAG&per_page=100" \
    | jq -r 'if type == "array" then (.[0].id // empty) else empty end'
}

RUNNER="$(runner_id)"
[[ -n "$RUNNER" ]] || { echo "Раннер с тегом $RUNNER_TAG в группе $GROUP не найден (задайте RUNNER_ID)" >&2; exit 1; }
log "Раннер: $RUNNER (тег $RUNNER_TAG)"

busy_jobs() { # общее число занятых/ожидающих джобов на раннере
  local status total=0 count
  for status in "${BUSY_STATUSES[@]}"; do
    count=$(api "runners/$RUNNER/jobs?status=$status&per_page=100" \
      | jq -r 'if type == "array" then length else 0 end')
    total=$((total + count))
  done
  echo "$total"
}

log "Ожидание простоя раннера (интервал ${INTERVAL}s, таймаут ${TIMEOUT}s)..."
deadline=$(( $(date -u +%s) + TIMEOUT ))
while :; do
  BUSY="$(busy_jobs)"
  if [[ "$BUSY" -eq 0 ]]; then
    log "Раннер свободен."
    break
  fi
  log "Занято джобов: $BUSY"
  [[ $(date -u +%s) -lt $deadline ]] || { echo "Таймаут ожидания (${TIMEOUT}s) — пайплайн не запущен" >&2; exit 1; }
  sleep "$INTERVAL"
done

if $DRY_RUN; then
  log "--dry-run: пайплайн не запускается."
  exit 0
fi

# Проверка и запуск не атомарны: между ними слоты раннера может занять другой
# пайплайн. Запускайте по одному проекту за раз.
log "Запуск пайплайна $GROUP/$PROJECT ($BRANCH)..."
glab ci run -R "$GROUP/$PROJECT" -b "$BRANCH"
log "Готово."
