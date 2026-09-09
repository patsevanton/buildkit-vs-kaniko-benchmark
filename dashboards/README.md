# Dashboard бенчмарка Kaniko vs BuildKit vs Buildah

`kaniko-vs-buildkit-per-project.json` — Grafana-дашборд с двумя панелями для
сравнения инструментов (**BuildKit** vs **Kaniko** vs **Buildah**) **по одному выбранному проекту**:

- **CPU** — CPU rate (cores) build-контейнеров джобов `buildkit-build`, `kaniko-build` и `buildah-build`;
- **Memory** — memory working set (bytes) build-контейнеров.

## Как различаются инструмент и проект

**Инструмент** — по label `image` метрик cAdvisor
(`…/moby/buildkit…` vs `…/kaniko-project/executor…` vs `…/buildah…`). Поды джобов GitLab Runner
(executor kubernetes) создаются в namespace `gitlab-runner` с build-контейнером
по имени `build`.

**Проект** — по GitLab project ID внутри имени пода джоба и по template-переменной
`$project`. GitLab Runner формирует имена подов по шаблону:

```
runner-vy3wuq-9w-project-86139409-concurrent-0-c6pxqt2m
                         ^^^^^^^^ GitLab project ID
```

В запросы панелей встроен фильтр `pod=~".*-project-$project-concurrent-.*"`.

Переменная `$project` — custom-список «имя : ID» пяти проектов группы:

| Проект | ID |
|---|---|
| nextjs | 86139390 |
| nuxtjs | 86139396 |
| golang | 86139398 |
| android | 86139404 |
| ml-pytorch | 86139409 |

ID нового проекта берётся из GitLab API
(`GET /api/v4/groups/buildkit-vs-kaniko-benchmark/projects?simple=true`) и
добавляется в `templating.list[0]` дашборда (и в поле `query`, и в `options`).
ID стабилен для существующего проекта, но **меняется при пересоздании** проекта
в GitLab — тогда список нужно обновить.

Метрики скрейпятся vmagent'ом стека VictoriaMetrics (namespace `vmks`) с kubelet
(cAdvisor) и пишутся в VictoriaMetrics.

## Установка

ConfigMap с лейблом `grafana_dashboard: "1"` в namespace `vmks` — sidecar
`grafana-sc-dashboard` чарта vmks подхватывает его автоматически:

```bash
kubectl -n vmks create configmap benchmark-per-project-dashboard \
  --from-file=kaniko-vs-buildkit-per-project.json=dashboards/kaniko-vs-buildkit-per-project.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n vmks label configmap benchmark-per-project-dashboard grafana_dashboard=1 --overwrite
```

Альтернативно — импорт вручную: Grafana → Dashboards → Import → Upload JSON.
Datasource — `VictoriaMetrics` (UID `VictoriaMetrics`).

## Нюансы

- Серии визуально различаются на всех панелях через `fieldConfig.overrides`
  (matcher `byFrameRefID`): **buildkit** (refId A) — зелёная сплошная линия,
  **kaniko** (refId B) — оранжевая пунктирная (`lineStyle.dash`),
  **buildah** (refId C) — синяя точечная (`lineStyle.dot`).
- Легенды серий — `buildkit` / `kaniko` / `buildah`. Если в выбранном тайм-рейндже было
  несколько прогонов одного проекта, на панели будет несколько серий с одинаковой
  легендой (по одной на под джоба); различать их по времени и по подсказке с
  именем пода (`graphTooltip` = shared crosshair).
- Дашборд показывает **ресурсы build-контейнера во время сборки**. Итоговая
  длительность сборки каждого инструмента = длительность соответствующего job
  в GitLab (на странице пайплайна или в API).
