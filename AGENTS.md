# AGENTS.md

Operational notes for working with this repo's infrastructure (Yandex Cloud + Managed K8s).

## Правила коммитов

Все названия коммитов писать в виде существительного/отглагольного существительного (не в инфинитиве). Например: «добавление манифестов kaniko», «уточнение README», «обновление версии buildkit».

## Требования к Terraform-стеку

- Managed K8s: `1.33` (release channel `STABLE`), master regional (3 зоны), node group `standard-v3`, 8 vCPU / 16 ГБ × 6 нод, preemptible.
- Ноды **без публичных IP** (`nat = false`), исходящий трафик через NAT-шлюз + route table.
- VictoriaMetrics k8s-stack (vmks) всегда устанавливается в namespace **`vmks`**, с отключёнными scrape-job и recording-правилами для control-plane (Yandex Managed K8s master вне кластера): см. `values/vmks-values.yaml.tftpl`.
- Провайдер helm/kubernetes подключается к кластеру через `yc k8s create-token`.
- После `terraform apply` обновить переменную GitLab CI `YCR_REGISTRY_ID`: взять новое значение из `terraform output -raw registry_id; echo` и прописать его в группе `gitlab.com/buildkit-vs-kaniko-benchmark` → **Settings → CI/CD → Variables** (`YCR_REGISTRY_ID`).

## Токены в `terraform.tfvars`

В `terraform.tfvars` хранятся два токена, которые **не используются Terraform'ом** — они нужны только для ручных операций вне terraform-стека:

- `gitlab_api_token` — GitLab Personal Access Token (префикс `glpat-`) со **скоупом `api` (read + write)** для работы через `glab` (GitLab CLI, `GITLAB_TOKEN`): мониторинг job'ов **и запуск пайплайнов** (`glab ci run`). Токен имеет права на запись — им можно создавать/отменять пайплайны и job'ы.
- `gitlab_runner_token` — GitLab Runner Registration Token (префикс `glrt-`) для установки GitLab Runner'а.

Обе переменные объявлены в `variables.tf` только ради валидности `terraform.tfvars`; в ресурсах (`*.tf`) они не используются. Сам `terraform.tfvars` в `.gitignore` (`*.tfvars`) и в репозиторий не коммитится.

### Правило запуска пайплайнов: только на свободном раннере

Пайплайн проекта **запускается только после того, как завершатся все джобы на раннере** (пока раннер занят — не стартовать). Причина: пара `kaniko+buildkit` одного проекта должна начаться **одновременно**, иначе две линии на дашборде Grafana (buildkit и kaniko) стартуют в разное время и графики становятся несопоставимыми. Раннер сконфигурирован с `concurrent = 2` (`gitlab-runner/values.yaml`) — ровно под одну пару; при занятой паре джобы нового пайплайна попадают в очередь и разъезжаются по времени.

Для этого есть `scripts/run-pipeline-when-idle.sh`: он опрашивает раннер (по тегу `k8s-benchmark` в группе), ждёт нуля занятых/ожидающих джобов и только затем делает `glab ci run`. Запускать по **одному** проекту за раз.

```bash
export GITLAB_TOKEN=$(sed -n 's/^gitlab_api_token\s*=\s*"\(.*\)"/\1/p' terraform.tfvars)
scripts/run-pipeline-when-idle.sh flask                 # дождаться простоя и запустить
scripts/run-pipeline-when-idle.sh android --dry-run     # только дождаться простоя раннера
```

## Провайдер yandex (credentials)

`provider "yandex"` не содержит явного `token`/`service_account_key_file` — аутентификация через переменные окружения или профиль `yc` для Terraform (см. документацию Yandex Cloud). Для `terraform apply` требуется авторизованный `yc` или соответствующие env-переменные провайдера.

## Registry и аутентификация push из джобов

- Yandex Container Registry создаётся в `registry.tf`; сервисному аккаунту кластера выданы роли `container-registry.images.pusher` и `container-registry.images.puller`.
- В CI-джобах (kaniko/buildkit, см. `.gitlab-ci.yml` в каждом из 7 репозиториев группы `gitlab.com/buildkit-vs-kaniko-benchmark`) auth выполняется **короткоживущим IAM-токеном из метаданных ноды** (`http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token`, формат Google Compute Engine), username — `iam`. Токен живёт ~12 часов и не хранится в репозитории. Для работы этого механизма ноды (и поды раннера на них) должны иметь сервисный аккаунт с ролью на registry (выдана выше).
- Docker config формируется в `before_script` каждого job'а прямо в build-контейнере (без init-контейнеров).

## Известные нюансы

- **BuildKit в этом бенчмарке работает в rootless-режиме** (`moby/buildkit:v0.32.2-rootless`) в daemonless-режиме — условия уравнены с Kaniko (оба без privileged). Rootless требует unprivileged user namespaces на нодах (при падении с `/proc/sys/user/max_user_namespaces` — DaemonSet-воркараунд из `examples/kubernetes/sysctl-userns.privileged.yaml` в moby/buildkit), а build-контейнеру нужен ослабленный securityContext: `seccompProfile: Unconfined` + `appArmorProfile: Unconfined` (задаётся в `gitlab-runner/values.yaml` через `build_container_security_context`).
- Сборка запускается **GitLab Runner'ом (executor kubernetes)**, развёрнутым в этом же кластере через helm (см. `gitlab-runner/`). Токен раннера передаётся скрипту аргументом и в репозиторий не коммитится.
- Контекст сборки — **сам репозиторий проекта** (Dockerfile + исходники в корне main-ветки). Каждый из 7 проектов — отдельный репозиторий группы `gitlab.com/buildkit-vs-kaniko-benchmark`.
- Пара `kaniko+buildkit` одного проекта запускается GitLab'ом параллельно (одна стадия в `.gitlab-ci.yml`); между проектами — независимые пайплайны.

## Установка мониторинга (vmks)

```bash
helm repo add victoriametrics https://victoriametrics.github.io/helm-charts/
helm repo update
helm upgrade --install vmks victoriametrics/victoria-metrics-k8s-stack \
  --version 0.91.2 \
  --namespace vmks \
  --create-namespace \
  --values values/vmks-values.yaml \
  --timeout 15m
```

Перед установкой убедитесь, что кластер доступен (`kubectl get nodes`) и отрендерен `values/vmks-values.yaml` (создаётся при `terraform apply`). `helm upgrade --install` идемпотентен — повторный запуск безопасен.

## Команды проверки

```bash
# K8s ноды
yc managed-kubernetes cluster get-credentials --id <cluster_id> --external --force
kubectl get nodes

# GitLab Runner
kubectl -n gitlab-runner get pods
kubectl -n gitlab-runner logs deploy/gitlab-runner

# Прогресс джобов сборки (поды раннера)
kubectl -n gitlab-runner get pods -w

# Диагностика GitLab CI джобов через glab
# Токен gitlab_api_token находится в terraform.tfvars (/home/user/github/patsevanton/buildkit-vs-kaniko-benchmark/terraform.tfvars)
# Использование: export GITLAB_TOKEN=$(sed -n 's/^gitlab_api_token\s*=\s*"\(.*\)"/\1/p' terraform.tfvars)
glab ci status -R buildkit-vs-kaniko-benchmark/<repo-name>
glab ci trace -R buildkit-vs-kaniko-benchmark/<repo-name> <job_id>
glab ci list -R buildkit-vs-kaniko-benchmark/<repo-name>
```
