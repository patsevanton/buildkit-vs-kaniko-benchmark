# GitLab Runner (executor: kubernetes)

Развёртывание GitLab Runner в кластере стенда для сборки 7 проектов бенчмарка
(группа `gitlab.com/buildkit-vs-kaniko-benchmark`).

## Что это

Официальный [helm-чарт GitLab Runner](https://gitlab.com/gitlab-org/charts/gitlab-runner)
с executor **kubernetes**: для каждого CI-джоба раннер создаёт отдельный под в
namespace `gitlab-runner`. Именно в этом поде выполняется `kaniko-build` или
`buildkit-build` (см. `.gitlab-ci.yml` в репозиториях проектов).

Метрики CPU/RAM этих подов снимает cAdvisor (через vmks) — они попадают в
VictoriaMetrics и отображаются в Grafana.

## Требования

- Кластер стенда развёрнут (`terraform apply`), доступен `kubectl`;
- `helm` v3;
- токен раннера для группы `buildkit-vs-kaniko-benchmark`.

## Получение токена

1. Откройте группу https://gitlab.com/buildkit-vs-kaniko-benchmark;
2. **Build → Runners → New group runner** (или Settings → CI/CD → Runners);
3. Скопируйте токен (`glrt-…`).

Токен в репозиторий **не коммитится** — он передаётся команде через
`--set-string "runnerToken=<runner-token>"`.

## Установка

```bash
helm repo add gitlab-runner https://charts.gitlab.io/
helm repo update
helm upgrade --install gitlab-runner gitlab-runner/gitlab-runner \
  --version 0.92.1 \
  --namespace gitlab-runner \
  --create-namespace \
  --values gitlab-runner/values.yaml \
  --set-string "runnerToken=<runner-token>" \
  --timeout 10m
```

Команда выполняет `helm upgrade --install gitlab-runner gitlab-runner/gitlab-runner`
в namespace `gitlab-runner`, поэтому идемпотентна — безопасна при повторном
запуске.

Проверка:

```bash
kubectl -n gitlab-runner get pods
kubectl -n gitlab-runner logs deploy/gitlab-runner
```

## Конфигурация (values.yaml)

Основные параметры:

| Параметр | Значение |
|---|---|
| `gitlabUrl` | `https://gitlab.com/` |
| `concurrent` | `2` (пара kaniko+buildkit одного проекта параллельно) |
| `rbac.create` | `true` (права на создание подов) |
| `runners.executor` | `kubernetes` |
| `runners.tags` | `k8s-benchmark` (тег, по которому джобы выбирают раннер) |
| `runners.runUntagged` | `false` (принимает только джобы с тегом) |
| build-контейнер CPU/RAM | request 1 CPU / 1 GiB, limit 4 CPU / 4 GiB |

Лимиты build-контейнера (`cpu_limit = "4"`, `memory_limit = "4Gi"`) совпадают с
лимитами старых K8s-джобов бенчмарка — условия замеров сохраняются.

Build-контейнер работает от root (как kaniko, так и buildkit) с
`privileged = false` и `allow_privilege_escalation = true` — daemonless-сборка
без docker.sock и без privileged-ноды.

## Примечания

- Auth в Yandex Container Registry выполняется IAM-токеном из метаданных ноды
  (в `before_script` каждого job'а) — сервисный аккаунт нод кластера уже имеет
  роли `container-registry.images.pusher/puller` (см. `registry.tf`).
- Имена подов джобов не важны для Grafana: инструменты различаются по label
  `image` метрик cAdvisor (`…/moby/buildkit…` vs `…/kaniko-project/executor…`).
- Если требуется сменить версию чарта/образа — поменяйте `--version` в команде
  установки (актуальная версия в https://charts.gitlab.io/index.yaml).
