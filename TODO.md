# TODO

## DONE: разбить роль `editor` сервисного аккаунта k8s на минимальные права

Выполнено: аккаунт расщеплён на два (`k8s.tf`):

- `sa_k8s_master` (`service_account_id`): `k8s.clusters.agent` + `vpc.publicAdmin` +
  `load-balancer.admin` (набор из документации Yandex Cloud «Managed K8s — Безопасность»:
  k8s.clusters.agent + vpc.publicAdmin для кластера с публичным доступом; load-balancer.admin —
  для сетевого балансировщика с публичным IP, т.е. Service LoadBalancer Traefik).
- `sa_k8s_node` (`node_service_account_id`): ролей на фолдер не имеет;
  `container-registry.images.pusher`/`puller` выданы ему на конкретный registry в `registry.tf`
  (IAM-токен из метаданных нод для push/pull в CI-джобах).
- Роль `editor` на фолдер больше не назначается; ресурсы `sa_k8s_editor*` удалены.
- `terraform validate`/`plan` проходят (plan: 22 to add — инфраструктура была уничтожена).

Не проверено (инфраструктура удалена, apply не выполнялся): `terraform apply`,
LoadBalancer Traefik, push/pull из джоб GitLab Runner — проверить после следующего развёртывания.

## DONE: отказаться от `$CI_PROJECT_NAME-buildkit-cache`

Выполнено: `--import-cache`/`--export-cache` BuildKit пишут в `$CI_PROJECT_NAME-buildkit`
(тот же репозиторий, что и образ) — отдельная политика очистки для `*-buildkit-cache` не нужна.
Изменены эталон в `README.md` и `.gitlab-ci.yml` во всех 7 репозиториях группы
`gitlab.com/buildkit-vs-kaniko-benchmark` (коммиты в main). Kaniko-кэш (`*-kaniko-cache`) не менялся.

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
