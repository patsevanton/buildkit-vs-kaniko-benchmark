# Dashboards бенчмарка kaniko vs buildkit

`kaniko-vs-buildkit-dashboard.json` — Grafana-дашборд с панелями:

- CPU rate по подам `kaniko-build` / `buildkit-build`;
- memory working set по подам;
- сетевой трафик пода (push/pull в registry);

метрики берутся из node-exporter/cAdvisor, скрейпятся vmagent стека VictoriaMetrics (namespace `vmks`).

Импорт: Grafana → Dashboards → Import → Upload JSON (`kaniko-vs-buildkit-dashboard.json`).
Datasource — `VictoriaMetrics` (UID `VictoriaMetrics`).

Альтернативно ConfigMap-подход: положить JSON как `dashboards/kaniko-vs-buildkit.json` в ConfigMap с лейблом `grafana_dashboard: "1"` в namespace `vmks` — sidecar `grafana-sc-dashboard` чарта vmks подхватит его автоматически.

Время сборки дублируется в `times.txt` каждого Job (из `time-build.sh`) и сводится в таблицы README.