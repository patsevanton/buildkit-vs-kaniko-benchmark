#!/usr/bin/env bash
set -euo pipefail

# Установка VictoriaMetrics k8s-stack (vmks) после terraform apply.
# Сам terraform больше не ставит vmks — только рендерит values/vmks-values.yaml
# (файл генерируется из values/vmks-values.yaml.tftpl). Этот скрипт выполняет
# helm upgrade --install, поэтому идемпотентен и безопасен для повторных запусков.

CHART_REPO="https://victoriametrics.github.io/helm-charts/"
CHART_NAME="victoriametrics/victoria-metrics-k8s-stack"
CHART_VERSION="0.91.2"
RELEASE_NAME="vmks"
NAMESPACE="vmks"
VALUES_FILE="$(dirname "$0")/values/vmks-values.yaml"

echo "==> Проверка готовности кластера (kubectl get nodes)"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ОШИБКА: kubectl не найден. Установите и настройте kubectl." >&2
  exit 1
fi

if ! kubectl get nodes >/dev/null 2>&1; then
  echo "ОШИБКА: кластер недоступен. Проверьте контекст kubectl:"
  echo "  yc managed-kubernetes cluster get-credentials --id <cluster_id> --external --force"
  exit 1
fi

echo "==> Проверка наличия values-файла (генерируется terraform apply)"
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "ОШИБКА: ${VALUES_FILE} не найден." >&2
  echo "Рендер происходит при terraform apply из values/vmks-values.yaml.tftpl." >&2
  echo "Выполните terraform apply или отрендерьте файл вручную." >&2
  exit 1
fi

echo "==> Добавление helm-репозитория и установка ${RELEASE_NAME} в namespace ${NAMESPACE}"
helm repo add victoriametrics "$CHART_REPO" >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install "$RELEASE_NAME" "$CHART_NAME" \
  --repo "$CHART_REPO" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  --timeout 15m

echo "==> Установка vmks завершена."
echo "Получить пароль admin Grafana:"
echo "  kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 --decode; echo"