# TODO

## TODO: Android SDK в базовом образе

Для проекта `android` перейти на базовый образ, в котором **уже установлен Android SDK**
(вместо установки SDK «на лету» в build-стадии: `sdkmanager` + `platforms;android-34` +
`build-tools;34.0.0`). Это уберёт многоминутное скачивание SDK на каждом холодном прогоне
(особенно заметно у rootless BuildKit).

**Выбранный образ — `mobiledevops/android-sdk-image:36.1.0`** (SDK android-36/35,
build-tools 36.1.0/35.0.1, JDK 21, Gradle 9.6.1, ~1.79 ГБ сжатый). Требует перехода
проекта на AGP 9.x (совместим с Gradle 9.x и JDK 21) и поднятия `compileSdk` до 36.

Если с этим образом не получится (несовместимость AGP 9.x со сборкой, проблемы с base
`ubuntu:24.04`, размер и т.п.), запасные варианты — в порядке предпочтения:

- `simplatex/android-lightweight:latest` — SDK android-37, build-tools 37.0.0, JDK 17,
  Gradle 9.2.1, ~1.81 ГБ (base `ubuntu:26.04`); тоже нужен AGP 9.x, но JDK 17.
- `mobiledevops/android-sdk-image:34.0.0-jdk17` — SDK android-34, build-tools 34.0.0, JDK 17,
  Gradle 8.2, ~1.86 ГБ; позволяет остаться на AGP 8.x (8.2.0), но base `ubuntu:23.10` (EOL).
- `cimg/android:2026.08` — SDK android-34…37, но build-tools 34.0.0 отсутствует (35/36/37),
  JDK 17/21, Gradle 9.6.1, ~3.18 ГБ; нужен AGP 9.x + compileSdk 35+, лишний балласт
  (gcloud/fastlane/maven).
- свой образ на базе `gradle:8.11.1-jdk17` с предустановленным SDK (`platforms;android-34`,
  `build-tools;34.0.0`) и запушенный в Yandex Container Registry — самый контролируемый
  вариант, если ни один community-образ не подойдёт.

### Почему DaemonSet с прогревом образа не решает задачу

Идея: запустить DaemonSet с Android-образом, чтобы kubelet заранее закачал его на каждую ноду,
а kaniko/buildkit потом переиспользовали уже скачанный образ. Это не сработает — потому что
**слои base image читаются не из containerd ноды, а из подового storage самого инструмента сборки**:

- DaemonSet качает образ в **store containerd ноды** (через kubelet). Образ «на ноде» есть.
- **Kaniko** (`gcr.io/kaniko-project/executor`) не обращается к containerd ноды: он сам ходит
  в registry за `FROM ...`, тянет слои и распаковывает их в собственный снапшот внутри пода
  (`/kaniko`). Из containerd ноды он читать не умеет.
- **BuildKit** здесь работает в daemonless-режиме (`buildctl-daemonless.sh`): поднимает временный
  `buildkitd` в том же поде со своим content store (`/root/.local/share/buildkit`), и base image
  тянет сам из registry в этот подовый store — тоже минуя containerd ноды.

Итог: DaemonSet сэкономит только pull runner-образа из `image:` в `.gitlab-ci.yml`
(kaniko executor ~100 МБ, `moby/buildkit` ~100 МБ), а не base image с Android SDK (1.8–5 ГБ).

Что реально убирает pull base image из замера:
- **self-contained образ** (SDK уже внутри), запушенный в Yandex Container Registry — первый pull
  из YCR быстрее `dl.google.com` и является честной частью холодного прогона;
- **pull-through registry mirror (cache)** в кластере, на который смотрят и Kaniko
  (`--registry-mirror`), и BuildKit (mirrors в `buildkitd.toml`) — повторные прогоны берут
  base image из локального кэша, но первый прогон всё равно miss, а «холодный прогон»
  перестаёт быть честно холодным.

## TODO: исследование — ускорит ли registry-кэш (NORA/Harbor/Artifactory/Nexus) pull образов

**Не реализовывать до завершения исследования и явного решения.**

Вопрос: ускорит ли размещение pull-through registry-кэша (NORA / Harbor / Artifactory / Nexus)
в кластере скачивание base image (в первую очередь Android SDK, 1.8–5 ГБ) в Kaniko/BuildKit.

Тезисы, которые надо проверить:

- **Кэш-хит**: при повторном pull одного и того же образа прокси-кэш отдаёт слои изнутри кластера
  (S3/локальный диск), а не из Docker Hub — повторные прогоны должны стать быстрее.
- **Кэш-мисс (холодный прогон)**: первый pull идёт транзитом через прокси в апстрим
  (`registry-1.docker.io`) и может оказаться даже медленнее прямого pull — индирекция на стороне
  прокси. Это критично для бенчмарка, где меряется именно холодное время.
- **Yandex Container Registry (`cr.yandex`)**: образ, переложенный в YCR, уже тянется быстро изнутри
  облака и, в отличие от прокси-кэша, не добавляет индирекцию. Возможно, это дешевле и проще,
  чем поднимать отдельный registry.
- **Rate limit Docker Hub**: прокси-кэш защищает от rate-limit'а — аргумент в пользу прокси при
  многих параллельных джобах.
- **Сравнение решений**: NORA (Rust, < 50 МБ RAM, 15 форматов, S3, MIT) vs Harbor / Artifactory /
  Nexus (Java-стек, 2–4 ГБ RAM, PostgreSQL/Redis) — по ресурсам и скорости отдачи Docker/OCI.

Кандидат для пилота — **NORA** (развёртывание описано в репозитории
`patsevanton/nora-yandex-k8s-deploy`: Helm-чарт `nora/nora` v0.4.4, S3-бэкенд, ingress через Traefik,
cert-manager). Нужно оценить:

1. замер pull Android-образа напрямую из Docker Hub vs через NORA (холодный и тёплый прогон);
2. замер против варианта «образ в Yandex Container Registry»;
3. насколько дешевле/проще поднять NORA против полноценного Harbor/Nexus/Artifactory.

Критерий приёмки: НЕ меняет честность «холодного прогона» (первый pull — реальный замер) и даёт
повторяемое ускорение повторных прогонов без индирекции, перевешивающей выгоду от кэша.
