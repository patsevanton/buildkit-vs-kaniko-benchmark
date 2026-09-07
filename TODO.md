# TODO

## TODO: разбить роль `editor` сервисного аккаунта k8s на минимальные права

Ресурс: `yandex_resourcemanager_folder_iam_member.sa_k8s_editor_permissions` в `k8s.tf` — сейчас
сервисный аккаунт `sa_k8s_editor` (используется и как `service_account_id`, и как
`node_service_account_id` кластера) получает роль `editor` на весь фолдер. Это избыточно и опасно.

План:

- Разбить одну роль `editor` на несколько минимальных ролей (набор сверить с актуальной
  документацией Yandex Cloud по Managed K8s «минимально необходимые роли»), кандидаты:
  - `k8s.clusters.agent` — управление ресурсами кластера от лица мастера;
  - `vpc.publicAdmin` — работа с сетями/подсетями;
  - `load-balancer.admin` — нужен Traefik'у (Service типа LoadBalancer);
  - `container-registry.images.puller` / `container-registry.images.pusher` — уже выданы в
    `registry.tf` на конкретный registry, не дублировать на фолдер.
- Отдельно рассмотреть расщепление аккаунта: `service_account_id` (мастер) и
  `node_service_account_id` (ноды) — разные SA с разными наборами прав вместо одного
  `sa_k8s_editor` на обе роли.
- Не забыть: IAM-токен из метаданных нод (`169.254.169.254/.../token`) используется в CI-джобах
  для push в YCR — после дробления прав проверить, что push/pull из джобов работает.
- Проверить существующий кластер/ноды: применить изменения и убедиться, что `terraform apply`
  проходит, кластер не пересоздаётся, Traefik создаёт LoadBalancer, GitLab Runner джобы
  завершаются успешно.
- Переименовать `sa_k8s_editor` / `sa_k8s_editor_permissions` (имя больше не отражает суть).

## TODO: отказаться от `$CI_PROJECT_NAME-buildkit-cache`

Отправлять кеш в `$CI_PROJECT_NAME-buildkit`, так как для `$CI_PROJECT_NAME-buildkit-cache`
нужно делать отдельную политику очистки.

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
