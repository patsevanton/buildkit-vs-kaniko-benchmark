# AGENTS.md

Operational notes for working with this repo's infrastructure (Yandex Cloud + Managed K8s).

## Правила коммитов

Все названия коммитов писать в виде существительного/отглагольного существительного (не в инфинитиве). Например: «добавление манифестов kaniko», «уточнение README», «обновление версии buildkit».

## Требования к Terraform-стеку

- Managed K8s: `1.33` (release channel `STABLE`), master regional (3 зоны), node group `standard-v3`, 8 vCPU / 16 ГБ × 6 нод, preemptible.
- Ноды **без публичных IP** (`nat = false`), исходящий трафик через NAT-шлюз + route table.
- VictoriaMetrics k8s-stack (vmks) всегда устанавливается в namespace **`vmks`**, с отключёнными scrape-job и recording-правилами для control-plane (Yandex Managed K8s master вне кластера): см. `values/vmks-values.yaml.tftpl`.
- Провайдер helm/kubernetes подключается к кластеру через `yc k8s create-token`.

## Провайдер yandex (credentials)

`provider "yandex"` не содержит явного `token`/`service_account_key_file` — аутентификация через переменные окружения или профиль `yc` для Terraform (см. документацию Yandex Cloud). Для `terraform apply` требуется авторизованный `yc` или соответствующие env-переменные провайдера.

## Registry и аутентификация push из джобов

- Yandex Container Registry создаётся в `registry.tf`; сервисному аккаунту кластера выданы роли `container-registry.images.pusher` и `container-registry.images.puller`.
- В джобах бенчмарка (kaniko/buildkit) auth выполняется **короткоживущим IAM-токеном из метаданных ноды** (`http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token`, формат Google Compute Engine), username — `iam`. Токен живёт ~12 часов и не хранится в репозитории. Для работы этого механизма ноды должны иметь сервисный аккаунт с ролью на registry (выдана выше).
- Docker config пишет init-контейнер `alpine:3.20` через скрипты из `benchmark/scripts-configmap.yaml`.

## Известные нюансы

- **BuildKit в этом бенчмарке работает от root** (`moby/buildkit:v0.32.2`, обычный образ) в daemonless-режиме — rootless-настройки не нужны. Если вернётесь к rootless-режиму, он требует unprivileged user namespaces на нодах (при падении с `/proc/sys/user/max_user_namespaces` — DaemonSet-воркараунд из `examples/kubernetes/sysctl-userns.privileged.yaml` в moby/buildkit).
- Job-манифесты `benchmark/generated/*` **генерируются Terraform** из `.tftpl` (подставляются реальный `registry_id`, проект и `benchmark_git_repo`). Каталог в `.gitignore` — не коммитить сгенерированные файлы.
- Контекст сборки передаётся **git clone** в init-контейнере `git-clone`: каждый проект собирается из **отдельной ветки** репозитория `benchmark_git_repo` (имя ветки = имя проекта, Dockerfile + исходники в корне ветки). По умолчанию репозиторий `patsevanton/buildkit-vs-kaniko-benchmark`.
- Очередь бенчмарка: пара `kaniko+buildkit` одного проекта параллельно, между проектами — последовательно (`benchmark/run-benchmark.sh`).
- После `terraform apply`, если вы меняете registry/кластер — перепримените джобы заново (`kubectl apply -f benchmark/generated/`), т.к. сгенерированные YAML обновятся.

## Команды проверки

```bash
# K8s ноды
yc managed-kubernetes cluster get-credentials --id <cluster_id> --external --force
kubectl get nodes

# Прогресс сборок
kubectl -n kaniko-benchmark get jobs -w
kubectl -n kaniko-benchmark get pods -w
# Время сборки из логов (по проекту)
kubectl -n kaniko-benchmark logs job/<project>-kaniko-build   | grep elapsed_sec
kubectl -n kaniko-benchmark logs job/<project>-buildkit-build | grep elapsed_sec
```