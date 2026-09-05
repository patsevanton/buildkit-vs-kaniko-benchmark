# AGENTS.md

Operational notes for working with this repo's infrastructure (Yandex Cloud + Managed K8s).

## Правила коммитов

Все названия коммитов писать в виде существительного/отглагольного существительного (не в инфинитиве). Например: «добавление манифестов kaniko», «уточнение README», «обновление версии buildkit».

## Требования к Terraform-стеку

- Managed K8s: `1.33` (release channel `STABLE`), master regional (3 зоны), node group `standard-v3`, 4 vCPU / 8 ГБ, preemptible.
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

- **Rootless-режим BuildKit** требует unprivileged user namespaces на нодах. На Yandex Managed K8s обычно работает из коробки; если Job падает с `/proc/sys/user/max_user_namespaces` — нужен DaemonSet-воркараунд (см. официальный `examples/kubernetes/sysctl-userns.privileged.yaml` в moby/buildkit).
- Job-манифесты `benchmark/kaniko/kaniko-job.yaml` и `benchmark/buildkit/buildkit-job.yaml` **генерируются Terraform** из `.tftpl` (в них подставляется реальный `registry_id`). Они в `.gitignore` — не коммитить сгенерированные файлы.
- После `terraform apply`, если вы меняете registry/кластер — перепримените джобы заново (`kubectl apply -f ...`), т.к. сгенерированные YAML обновятся.

## Команды проверки

```bash
# K8s ноды
yc managed-kubernetes cluster get-credentials --id <cluster_id> --external --force
kubectl get nodes

# Прогресс сборок
kubectl -n kaniko-benchmark get jobs -w
kubectl -n kaniko-benchmark get pods -w
# Время сборки из логов
kubectl -n kaniko-benchmark logs job/kaniko-build
kubectl -n kaniko-benchmark logs job/buildkit-build
```