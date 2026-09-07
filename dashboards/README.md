# Dashboard бенчмарка Kaniko vs BuildKit (GitLab Runner)

`kaniko-vs-buildkit-gitlab-runner.json` — Grafana-дашборд с тремя панелями для прямого сравнения инструментов (**BuildKit** vs **Kaniko**):

- **CPU** — CPU rate (cores) build-контейнеров джобов `buildkit-build` и `kaniko-build` за время сборки;
- **Memory** — memory working set (bytes) build-контейнеров за время сборки;
- **Elapsed** — растущее время сборки (seconds) build-контейнеров.

Инструменты различаются по label `image` метрик cAdvisor
(`…/moby/buildkit…` vs `…/kaniko-project/executor…`), а поды джобов GitLab Runner
(executor kubernetes) создаются в namespace `gitlab-runner` с build-контейнером
по имени `build`.

Метрики скрейпятся vmagent'ом стека VictoriaMetrics (namespace `vmks`) с kubelet
(cAdvisor) и пишутся в VictoriaMetrics.

Импорт: Grafana → Dashboards → Import → Upload JSON
(`kaniko-vs-buildkit-gitlab-runner.json`). Datasource — `VictoriaMetrics`
(UID `VictoriaMetrics`).

Альтернативно ConfigMap-подход: положить JSON как
`dashboards/kaniko-vs-buildkit-gitlab-runner.json` в ConfigMap с лейблом
`grafana_dashboard: "1"` в namespace `vmks` — sidecar `grafana-sc-dashboard`
чарта vmks подхватит его автоматически.

Длительность сборки каждого инструмента = длительность соответствующего job
в GitLab (на странице пайплайна или в API). Итоговую сводку по всем проектам
удобно собирать из длительностей джобов.
