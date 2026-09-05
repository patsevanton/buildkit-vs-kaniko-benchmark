# Kaniko vs BuildKit в Managed Yandex K8s: что выбрать для сборки образов

## Введение

В Kubernetes-кластере рано или поздно встаёт вопрос: **где собирать Docker/OCI-образы приложений?** Вариант «на своей машине разработчика» не масштабируется на команду, а `docker build` прямо в поде невозможен — в контейнере нет демона Docker, а запускать privileged-контейнер с `/var/run/docker.sock` хотят не все (в managed-кластере это, как правило, и нельзя).

Классических ответов два — **Kaniko** и **BuildKit**:

- **Kaniko** (`gcr.io/kaniko-project/executor`) — инструмент от Google, который собирает образы **без privileged-контейнера**, запускаясь из обычного контейнера (внутри работает от root, но без привилегий ноды). Репозиторий [GoogleContainerTools/kaniko](https://github.com/GoogleContainerTools/kaniko) **архивирован владельцем 3 июня 2025 года** и доступен только для чтения — проект больше не развивается.
- **BuildKit** (`moby/buildkit`) — движок сборки, который с 2022 года стоит за `docker build` в десктопном Docker (через `buildx`). В Kubernetes запускается **daemonless**: один контейнер поднимает свой встроенный демон `buildkitd`, собирает и пушит образ. В этом бенчмарке демон работает **от root** (как у Kaniko) — без user namespaces, без `Unconfined`/apparmor-нюансов, условия для обоих инструментов уравнены.

Этот репозиторий — **воспроизводимый бенчмарк** на Managed Yandex K8s: **7 проектов** разных языков и фреймворков собираются обоими инструментами в одних и тех же условиях, с замером времени, потребления CPU/RAM и поведения кэша. В конце — **итоговая сводная таблица** и разбор **преимуществ и недостатков** каждого подхода для продакшна.

## Что измеряем

| Категория | Как измеряем |
|---|---|
| **Время сборки** (без кэша / с кэшем) | `time-build.sh` замеряет `date +%s` до/после команды сборки внутри Job, пишет в `/artifacts/times.txt` |
| **Потребление CPU/RAM** | node-exporter + cAdvisor → VictoriaMetrics → дашборд Grafana «Kaniko vs BuildKit» (с фильтром по проекту) |
| **Кэширование слоёв** | повторный запуск того же Dockerfile с включённым кэшем: kaniko `--cache` (registry-кэш) и BuildKit `--import-cache`/`--export-cache type=registry` (тоже registry-кэш) |
| **Особенности Managed Yandex K8s** | auth в Registry через IAM-токен из метаданных ноды, отсутствие потребности в privileged-контейнерах, daemonless-сборка без docker.sock |
| **Поддержка Dockerfile-синтаксиса** | одинаковые Dockerfile (apt, multi-stage, COPY --from) — сравнение совместимости |

## Сравниваемые проекты

Бенчмарк собирает **7 проектов** — по одному на характерный «профиль сборки»:

| № | Проект | Язык/Framework | Профиль сборки | Контекст |
|---|---|---|---|---|
| 1 | **Flask + Gunicorn** | Python | `pip install` multi-stage | `benchmark/projects/flask` |
| 2 | **NestJS** | Node/TS | тяжёлый `npm ci` + декораторы, tsc | `benchmark/projects/nestjs` |
| 3 | **Next.js** | Node/React SSR | `npm ci` + сборка клиента | `benchmark/projects/nextjs` |
| 4 | **Nuxt 3** | Node/Vue SSR | `npm ci` + сборка клиента | `benchmark/projects/nuxt` |
| 5 | **Go HTTP-сервис** | Go | `go build` → статический бинарник (из scratch) | `benchmark/projects/go` |
| 6 | **Android APK** | Java/Kotlin, Gradle | `assembleRelease`, тяжёлый Gradle/SDK | `benchmark/projects/android` |
| 7 | **ML: PyTorch inference** | Python | `pip install torch` + скачивание ~1.3 ГБ весов в BUILD-стадии (public S3-бакет) | `benchmark/projects/ml-pytorch` |

## Архитектура стенда

```mermaid
flowchart LR
    subgraph K8s["Managed Yandex K8s (1.33)"]
        F1["Job kaniko: <project>-kaniko-build × 7"]
        F2["Job buildkit: <project>-buildkit-build × 7"]
        subgraph NS["namespace kaniko-benchmark"]
            F1
            F2
        end
    end

    subgraph YCR["Yandex Container Registry"]
        R["registry.yandex.cloud/&lt;id&gt;<br/>&lt;project&gt;-kaniko / &lt;project&gt;-buildkit<br/>+ &lt;project&gt;-*-cache"]
    end

    MET["IAM-токен из метаданных ноды<br/>169.254.169.254 (сервисный аккаунт)"]
    VM["VictoriaMetrics (vmks)"]
    G["Grafana"]

    F1 -->|"push"| R
    F2 -->|"push"| R
    MET -.->|"auth"| F1
    MET -.->|"auth"| F2
    F1 -->|"node metrics"| VM
    F2 -->|"node metrics"| VM
    VM --> G
```

Terraform поднимает:

- VPC + 3 приватные подсети (по одной в зонах `ru-central1-b/-d/-e`), NAT-шлюз с route table — ноды **без публичных IP** (согласно AGENTS.md);
- Managed K8s master 1.33 (regional, 3 зоны), node group из 6 preemptible нод `standard-v3` 8 vCPU / 16 ГБ (по 2 ноды на зону);
- Traefik (ingress) для доступа к Grafana через `sslip.io`;
- **Yandex Container Registry** + IAM-привязку для сервисного аккаунта кластера (`container-registry.images.pusher` / `container-registry.images.puller`);
- VictoriaMetrics k8s-stack в namespace **`vmks`** (с отключёнными scrape и правилами для control-plane — как того требует AGENTS.md для Managed Yandex K8s). Устанавливается **отдельным шагом** через скрипт `install-vmks.sh` после `terraform apply` — terraform только рендерит `values/vmks-values.yaml`.

## Сравниваемые варианты

| Вариант | Образ | Запуск | Auth в registry |
|---|---|---|---|
| **Kaniko** | `gcr.io/kaniko-project/executor:v1.23.2-debug` | Job, обычный контейнер без privileged (root, но внутри) | IAM-токен из метаданных ноды → `config.json` в `/kaniko/.docker` |
| **BuildKit** | `moby/buildkit:v0.32.2` | Job, **daemonless** (`buildctl-daemonless.sh`), демон `buildkitd` от root | IAM-токен из метаданных ноды → `/root/.docker/config.json` |

Оба пушат в один и тот же Yandex Container Registry (`registry.yandex.cloud/<registry-id>/`), по своему репозиторию на проект (`<project>-kaniko`, `<project>-buildkit`). Оба инструмента работают **от root** и **daemonless** — условия замеров уравнены, разница — только в самом инструменте сборки.

## Развёртывание

### 1. Terraform

```bash
terraform init
terraform apply -auto-approve
```

После apply Terraform выводит:

- `k8s_cluster_credentials_command` — команда получения доступа к K8s;
- `grafana_url` + `grafana_admin_password_command` — доступ к дашборду;
- `registry_server` — адрес `registry.yandex.cloud/<id>`;
- `ml_weights_url` — URL весов ML-модели (бакет `kaniko-vs-buildkit-weights`);
- `apply_benchmark_command` — команда применения манифестов бенчмарка.

> Для проекта `ml-pytorch` перед прогоном нужно **один раз залить веса** в созданный бакет (см. `TODO.md`). Без этого джобы ml-pytorch упадут на скачивании.

> Terraform **не устанавливает** VictoriaMetrics k8s-stack (vmks): он только рендерит `values/vmks-values.yaml`. Сама установка — отдельным шагом ниже.

### 1a. Установка мониторинга (vmks)

```bash
./install-vmks.sh
```

Скрипт проверяет доступность кластера, наличие отрендеренного `values/vmks-values.yaml` (создаётся при `terraform apply`) и выполняет `helm upgrade --install` в namespace `vmks`. Идемпотентен — повторный запуск безопасен.

### 2. Доступ к кластеру

```bash
yc managed-kubernetes cluster get-credentials --id $(terraform output -raw k8s_cluster_id) --external --force
kubectl get nodes
```

### 3. Применить манифесты бенчмарка

```bash
kubectl apply -f benchmark/namespace.yaml \
  -f benchmark/scripts-configmap.yaml \
  -f benchmark/generated/
```

<details>
<summary>Что внутри манифестов</summary>

- `benchmark/namespace.yaml` — namespace `kaniko-benchmark`;
- `benchmark/scripts-configmap.yaml` — скрипты: замер времени (`time-build.sh`), получение IAM-токена, запись docker-config и материализация дерева контекста (`setup-workspace.sh`). Никаких секретов в манифестах нет — токен живёт 12 часов и берётся из метаданных ноды прямо во время запуска;
- `benchmark/generated/` — **отрендеренные Terraform** манифесты:
  - `build-context-<project>.yaml` — ConfigMap контекста (плоские ключи, вложенные пути — через `__` → `/`);
  - `<project>-kaniko-job.yaml` — Job Kaniko на проект;
  - `<project>-buildkit-job.yaml` — Job BuildKit на проект (daemonless, от root);
  - (`benchmark/generated/` в `.gitignore` — файлы регенерируются при `terraform apply`.)
</details>

### 4. Запуск прогона

Пары `kaniko+buildkit` одного проекта запускаются **параллельно**, между проектами — **последовательно** (скрипт `benchmark/run-benchmark.sh`):

```bash
./benchmark/run-benchmark.sh            # все 7 проектов
# или по одному:
./benchmark/run-benchmark.sh go android
```

Скрипт для каждого проекта: удаляет старые Job, применяет пару, ждёт завершения (`kubectl wait --for=condition=complete`) и печатает `elapsed_sec` из логов.

Наблюдение вручную:

```bash
kubectl -n kaniko-benchmark get jobs -w
kubectl -n kaniko-benchmark get pods -w
```

По завершении — сводка времени в `times.txt` каждого Job:

```bash
kubectl -n kaniko-benchmark logs job/go-kaniko-build   | grep elapsed_sec
kubectl -n kaniko-benchmark logs job/go-buildkit-build | grep elapsed_sec
```

Собрать итоговую таблицу из всех проектов:

```bash
./benchmark/parse-results.sh   # печатает и пишет results.md
```

### 5. Дашборд в Grafana

Откройте дашборд **«Kaniko vs BuildKit — ресурсы во время сборки»** (`UID: kaniko-vs-buildkit`): CPU rate, memory working set и сетевой трафик каждого пода на время его сборки. Файл `dashboards/kaniko-vs-buildkit-dashboard.json` — импортируйте его в Grafana вручную (Grafana → Dashboards → Import → Upload JSON), либо применён через ConfigMap-подход автоматически (см. ниже).

## Ожидаемые результаты

Таблица заполняется после реального прогона (см. «Как заполнить результаты» ниже). Ожидания из практики:

| Метрика | Kaniko | BuildKit |
|---|---|---|
| Время сборки **без кэша** (полный `apt install` + pip) | ~3–5 мин | ~1.5–3 мин (параллельные шаги) |
| Время сборки **с кэшем** (повторный прогон) | быстрее через `--cache` (registry-кэш): слой берётся из registry без пересборки | registry-кэш через `--import-cache`/`--export-cache type=registry`, push только новых слоёв |
| CPU (max) | монотонно по слоям | многопоточный (несколько воркеров за раз) |
| RAM (max) | выше из-за полного `apt`/pip в процессе | зависит от параллелизма |
| Итоговый образ | OCI | OCI |

> Это **ожидания**, а не результат. Ниже методика, как получить числа на вашем стенде, и таблицы для заполнения.

## Как заполнить сводную таблицу результатов

1. Выполните **первый прогон** (холодный кэш):
   ```bash
   ./benchmark/run-benchmark.sh   # пары kaniko+buildkit на проект, последовательно по проектам
   ```
   Время каждого Job — строка `<project>-<tool> elapsed_sec=N` в логах:
   ```bash
   kubectl -n kaniko-benchmark logs job/go-kaniko-build   | grep elapsed_sec
   kubectl -n kaniko-benchmark logs job/go-buildkit-build | grep elapsed_sec
   ```
2. Выполните **второй прогон** (тёплый кэш) тем же способом — запишите вторые числа.
3. Снимите CPU/RAM с дашборда Grafana за соответствующий интервал (фильтр по проекту).
4. Соберите итог:
   ```bash
   ./benchmark/parse-results.sh   # -> results.md
   ```
5. Внесите числа в таблицу ниже и сформулируйте вывод.

### Итоговая сводная таблица (7 проектов)

Заполняется после реального прогона. Пример формата (числа — как вставить):

| Проект | Время kaniko (с) | Время buildkit (с) | Выигрыш BuildKit % |
|---|---|---|---|
| flask | _заполнить_ | _заполнить_ | _заполнить_ |
| nestjs | _заполнить_ | _заполнить_ | _заполнить_ |
| nextjs | _заполнить_ | _заполнить_ | _заполнить_ |
| nuxt | _заполнить_ | _заполнить_ | _заполнить_ |
| go | _заполнить_ | _заполнить_ | _заполнить_ |
| android | _заполнить_ | _заполнить_ | _заполнить_ |
| ml-pytorch | _заполнить_ | _заполнить_ | _заполнить_ |

### Детализация по метрикам (пример на проекте go)

#### Прогон 1: холодный кэш

| Метрика | Kaniko | BuildKit |
|---|---|---|
| Время сборки (сек) | _заполнить_ | _заполнить_ |
| Пиковый CPU (rate, cores) | _заполнить_ | _заполнить_ |
| Пиковая RAM (working set, GiB) | _заполнить_ | _заполнить_ |
| Ошибки/retries | _заполнить_ | _заполнить_ |

#### Прогон 2: тёплый кэш

| Метрика | Kaniko | BuildKit |
|---|---|---|
| Время сборки (сек) | _заполнить_ | _заполнить_ |
| Пиковый CPU (rate, cores) | _заполнить_ | _заполнить_ |
| Пиковая RAM (working set, GiB) | _заполнить_ | _заполнить_ |
| Ошибки/retries | _заполнить_ | _заполнить_ |

## Преимущества и недостатки

### Kaniko

**Преимущества:**

- **Работает без привилегий.** Обычный контейнер без privileged, никакого docker.sock — подходит для managed-кластера и строгих политик безопасности.
- **Простота.** Один бинарник-джоб хорошо известен, огромное количество документации и примеров.
- **Кэш в registry.** `--cache-repo` позволяет переиспользовать слои между сборками непротиворечиво, даже если сам кластер/нода меняются (кэш живёт в registry, а не на диске пода).
- **Можно собирать в любом кластере** — без настройки daemon, без sysctl, без user-namespace.

**Недостатки:**

- **Скорость.** Сборка идёт последовательно по слоям (несколько слоёв параллельно не строятся), что на тяжёлых Dockerfile заметно медленнее BuildKit.
- **Слабое кэширование на диске.** По умолчанию кэш пишется в registry (медленнее и дороже), локального кэша между прогонами нет.
- **Ограниченный синтаксис.** Не поддерживает продвинутые фичи BuildKit: `RUN --mount=type=cache`, `RUN --mount=type=secret`, `--mount=type=ssh` и т.п. (часть поддерживается через флаги, но не вся).
- **Контекст и большие слои.** Kaniko должен скачивать и разворачивать базовый образ и предыдущие слои целиком; при большом контексте это занимает время и место.

### BuildKit

**Преимущества:**

- **Скорость.** Многопоточная сборка (параллельные шаги), кэш слоёв и быстрый инкрементальный пересбор. На реальных Dockerfile часто в 2–3 раза быстрее Kaniko.
- **Родная поддержка кэша.** `buildkitd` умеет хранить кэш локально и поддерживает внешние кэши (registry, S3). В этом бенчмарке локальный кэш не используется — BuildKit работает с registry-кэшем через `--import-cache`/`--export-cache type=registry` (аналог `--cache-repo` Kaniko).
- **Богатый синтаксис.** `RUN --mount=type=cache|secret|ssh`, `RUN --mount=type=bind`, BuildKit-составные шаги, возможность подключать внешние кэши.
- **Та же технология, что у `docker build`.** Что собирается в CI/local docker, то и BuildKit — единый синтаксис.

**Недостатки:**

- **Сложнее.** Daemonless-джоб поднимает встроенный демон, требует понимания `buildctl`/`buildkitd` и кэша.
- **Ресурсы.** Многопоточность = большее пиковое потребление CPU/RAM, которое нужно учитывать в requests/limits.
- **Оба кэша эфемерны.** В этом бенчмарке ни Kaniko, ни BuildKit не хранят локальный кэш между прогонами (Kaniko не пишет кэш на диск по умолчанию, BuildKit живёт в daemonless-поде без PVC) — теплота кэша обеспечивается только registry-кэшем. Kaniko-кэш в `--cache-repo` и BuildKit-кэш в `--export-cache type=registry` в равной степени переживают пересоздание подов.
- **Rootless-режим (если он нужен) имеет нюансы.** В этом бенчмарке BuildKit работает от root (как и Kaniko), поэтому rootless-настройки не нужны. Если в продакшне потребуется rootless — там будут уместны user namespaces, `oci-worker-no-process-sandbox` и отключение seccomp/apparmor на уровне пода.

## Вывод

Kaniko — «заниженный порог входа» для безопасной сборки без привилегий (без privileged); подходит, когда нужно просто и надёжно собрать типовой образ в managed-кластере. BuildKit — значительный прирост скорости и выразительности Dockerfile ценой сложности daemonless-настройки и большего потребления ресурсов. В этом бенчмарке оба инструмента работают **от root** в одинаковых условиях, поэтому разница сводится к скорости и кэшированию.

Итоговую рекомендацию нужно давать по числам из сводной таблицы: если сборка редкая и Dockerfile типовой, Kaniko достаточно; если собираете часто, образы тяжёлые (Node/Gradle/ML) и хочется скорости — BuildKit, но с правильной конфигурацией кэша и ресурсов.

## Файлы

| Файл | Назначение |
|------|-----------|
| `versions.tf`, `providers.tf`, `variables.tf`, `locals.tf` | Провайдеры и общие настройки Terraform |
| `net.tf` | VPC, 3 приватные подсети, NAT-шлюз, route table |
| `ip-dns.tf` | Публичный IP балансировщика Traefik |
| `k8s.tf` | Managed K8s (master 1.33, региональный), node group 6×8 vCPU/16 ГБ, Traefik |
| `registry.tf` | Yandex Container Registry + IAM-привязка для SA кластера |
| `weights.tf` | S3-бакет `kaniko-vs-buildkit-weights` (public-read) для весов ML-проекта, вывод `ml_weights_url` |
| `monitoring.tf`, `values/vmks-values.yaml.tftpl` | Рендер values для VictoriaMetrics k8s-stack в namespace `vmks` (с отключёнными scrape control-plane); установка — через `install-vmks.sh` |
| `install-vmks.sh` | Установка vmks после `terraform apply` (`helm upgrade --install`, идемпотентно) |
| `benchmark.tf` | Рендер 7 ConfigMap контекста + 14 job-манифестов из `.tftpl` (registry_id, project) |
| `benchmark/namespace.yaml` | Namespace `kaniko-benchmark` |
| `benchmark/scripts-configmap.yaml` | Скрипты: замер времени, IAM-токен, docker-config, `setup-workspace.sh` |
| `benchmark/build-context-configmap.yaml.tftpl` | Шаблон ConfigMap контекста (плоские ключи `__` → `/`) |
| `benchmark/kaniko/kaniko-job.yaml.tftpl` | Job kaniko на проект (генерируется в `benchmark/generated/`) |
| `benchmark/buildkit/buildkit-job.yaml.tftpl` | Job buildkit daemonless от root (генерируется) |
| `benchmark/projects/<project>/` | 7 мини-проектов: flask, nestjs, nextjs, nuxt, go, android, ml-pytorch |
| `benchmark/run-benchmark.sh` | Оркестрация: пары kaniko+buildkit параллельно, проекты последовательно |
| `benchmark/parse-results.sh` | Сбор `elapsed_sec` из всех Job → `results.md` |
| `TODO.md` | Как залить веса ML-модели (~1.3 ГБ) в S3-бакет |
| `dashboards/kaniko-vs-buildkit-dashboard.json` | Дашборд Grafana (с фильтром по проекту) |

## Требования

- Yandex Cloud CLI (`yc`) с авторизацией, Terraform ≥ 1.3;
- `folder_id` в `terraform.tfvars`;
- `helm` v3 (для установки vmks через `install-vmks.sh`);
- (для прогона) кластер развёрнут `terraform apply`, установлен `kubectl`.