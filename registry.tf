# Yandex Container Registry для пуша собранных образов (kaniko и buildkit).
resource "yandex_container_registry" "registry" {
  name      = local.registry_name
  folder_id = var.folder_id
}

# Кому разрешён push/pull в registry. Бенчмарк-джобы запускаются в подах на нодах
# кластера и берут IAM-токен из метаданных ноды — т.е. выступают от лица
# node-сервисного аккаунта (sa_k8s_node, см. k8s.tf).
# Роли container-registry.images.pusher / puller дают возможности push и pull
# собранных образов; назначаются на конкретный registry, а не на весь фолдер.
resource "yandex_container_registry_iam_binding" "registry_sa" {
  registry_id = yandex_container_registry.registry.id
  role        = "container-registry.images.pusher"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa_k8s_node.id}",
  ]
}

resource "yandex_container_registry_iam_binding" "registry_sa_puller" {
  registry_id = yandex_container_registry.registry.id
  role        = "container-registry.images.puller"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa_k8s_node.id}",
  ]
}

output "registry_id" {
  description = "ID Yandex Container Registry (для переменной YCR_REGISTRY_ID в GitLab CI)"
  value       = yandex_container_registry.registry.id
}

output "registry_server" {
  description = "Полный адрес Yandex Container Registry для пуша образов"
  value       = local.registry_server
}
