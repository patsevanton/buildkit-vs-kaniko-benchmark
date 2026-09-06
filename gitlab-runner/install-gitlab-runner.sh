#!/usr/bin/env bash
# Установка/обновление GitLab Runner (executor: kubernetes) в кластере стенда.
#
# Использование:
#   ./gitlab-runner/install-gitlab-runner.sh <runner-token>
#
# runner-token — токен зарегистрированного раннера (glrt-…) либо регистрационный
# токен (для создания нового раннера). Взять в gitlab.com:
#   группа buildkit-vs-kaniko-benchmark -> Build -> Runners -> New group runner
#   (или Settings -> CI/CD -> Runners).
#
# Идемпотентен: helm upgrade --install безопасно запускать повторно.
set -euo pipefail

TOKEN="${1:?usage: install-gitlab-runner.sh <runner-token>}"

CHART_REPO="https://charts.gitlab.io/"
CHART_NAME="gitlab-runner"
CHART_VERSION="0.92.1"
RELEASE_NAME="gitlab-runner"
NAMESPACE="gitlab-runner"
VALUES_FILE="$(dirname "$0")/values.yaml"

echo "==> Проверка готовности кластера (kubectl get nodes)"
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ОШИБКА: kubectl не найден." >&2
  exit 1
fi
if ! kubectl get nodes >/dev/null 2>&1; then
  echo "ОШИБКА: кластер недоступен. Проверьте контекст kubectl:" >&2
  echo "  yc managed-kubernetes cluster get-credentials --id <cluster_id> --external --force" >&2
  exit 1
fi

echo "==> Добавление helm-репозитория gitlab-runner"
helm repo add gitlab-runner "$CHART_REPO" >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "==> Установка ${RELEASE_NAME} в namespace ${NAMESPACE}"
helm upgrade --install "$RELEASE_NAME" "$CHART_NAME" \
  --repo "$CHART_REPO" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  --set-string "runnerToken=${TOKEN}" \
  --timeout 10m

echo
echo "==> GitLab Runner установлен."
echo "Проверить статус:"
echo "  kubectl -n ${NAMESPACE} get pods"
echo "  kubectl -n ${NAMESPACE} logs deploy/${RELEASE_NAME}"
