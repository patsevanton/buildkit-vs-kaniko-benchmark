#!/usr/bin/env bash
# Прогон бенчмарка: пара kaniko+buildkit одного проекта параллельно,
# между проектами — последовательно. 7 проектов.
#
# Требует: kubectl, отрендеренные манифесты в benchmark/generated/ (terraform apply).
# Usage: ./run-benchmark.sh [project...]  # по умолчанию все 7
set -euo pipefail

NS=${NS:-kaniko-benchmark}
PROJECTS=("$@")
if [ ${#PROJECTS[@]} -eq 0 ]; then
  PROJECTS=(flask nestjs nextjs nuxt go android ml-pytorch)
fi

MANIFEST_DIR="${MANIFEST_DIR:-benchmark/generated}"

wait_for_job() {
  local job=$1
  echo "  waiting for $job ..."
  kubectl -n "$NS" wait --for=condition=complete --timeout=5400s "job/$job"
}

for p in "${PROJECTS[@]}"; do
  echo "=== Project: $p ==="

  kubectl -n "$NS" delete job "${p}-kaniko-build" "${p}-buildkit-build" --ignore-not-found=true >/dev/null

  kubectl apply -f "$MANIFEST_DIR/${p}-kaniko-job.yaml" -f "$MANIFEST_DIR/${p}-buildkit-job.yaml"
  wait_for_job "${p}-kaniko-build"
  wait_for_job "${p}-buildkit-build"

  echo "--- times.txt ---"
  kubectl -n "$NS" logs "job/${p}-kaniko-build" | grep -E "elapsed_sec" || true
  kubectl -n "$NS" logs "job/${p}-buildkit-build" | grep -E "elapsed_sec" || true

  echo "=== project $p done ==="
done

echo
echo "All done. Run ./parse-results.sh to build the summary table."