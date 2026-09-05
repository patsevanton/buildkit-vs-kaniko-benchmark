#!/bin/sh
# Замеряет время выполнения команды сборки и пишет результат в /workspace/times.txt,
# а также логи сборки в /workspace/build.log.
#
# Использование: time-build.sh <tool_name> <аргументы сборки...>
set -eu

TOOL_NAME="${1:?tool name is required}"
shift

START="$(date +%s%3N)"
echo "=== $(date -Is) START $TOOL_NAME ===" >> /workspace/times.txt

set +e
"$@" > /workspace/build.log 2>&1
BUILD_RC=$?
set -e

END="$(date +%s%3N)"
echo "=== $(date -Is) END $TOOL_NAME (rc=$BUILD_RC) ===" >> /workspace/times.txt

ELAPSED_MS=$((END - START))
echo "$TOOL_NAME elapsed_ms=$ELAPSED_MS rc=$BUILD_RC" >> /workspace/times.txt

echo "BUILD_RC=$BUILD_RC"
echo "ELAPSED_MS=$ELAPSED_MS"
exit "$BUILD_RC"