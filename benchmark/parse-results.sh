#!/usr/bin/env bash
# Собирает времена сборки из завершённых Jobs в markdown-таблицу для README.
# Вывод: stdout (таблица) + файл results.md в каталоге запуска.
#
# Требует: kubectl. На каждом job ищем строку "<tool> elapsed_sec=<N>".
# Usage: ./parse-results.sh [project...]
set -euo pipefail

NS=${NS:-kaniko-benchmark}
PROJECTS=("$@")
if [ ${#PROJECTS[@]} -eq 0 ]; then
  PROJECTS=(flask nestjs nextjs nuxt go android ml-pytorch)
fi

OUT="results.md"
{
  echo "| Проект | Время kaniko (с) | Время buildkit (с) | Выигрыш BuildKit % |"
  echo "|---|---|---|---|"

  for p in "${PROJECTS[@]}"; do
    kaniko_time=$(kubectl -n "$NS" logs "job/${p}-kaniko-build" 2>/dev/null | sed -n 's/.*elapsed_sec=\([0-9]*\).*/\1/p' | tail -1)
    buildkit_time=$(kubectl -n "$NS" logs "job/${p}-buildkit-build" 2>/dev/null | sed -n 's/.*elapsed_sec=\([0-9]*\).*/\1/p' | tail -1)

    if [ -n "$kaniko_time" ] && [ -n "$buildkit_time" ] && [ "$buildkit_time" -gt 0 ]; then
      win=$(awk "BEGIN{printf \"%.0f\", ($kaniko_time-$buildkit_time)/$kaniko_time*100}")
    else
      win=""
    fi

    echo "| ${p} | ${kaniko_time:-_заполнить_} | ${buildkit_time:-_заполнить_} | ${win:-_заполнить_}% |"
  done
} | tee "$OUT"

echo "Таблица записана в $OUT"