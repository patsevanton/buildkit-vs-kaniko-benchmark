# Yandex Container Registry для пуша собранных образов (kaniko и buildkit).
resource "yandex_container_registry" "registry" {
  name      = local.registry_name
  folder_id = var.folder_id
}

# Кому разрешён push/pull в registry. Бенчмарк-джобы запускаются в кластере,
# а сервисный аккаунт кластера (sa_k8s_editor) используется как его node_service_account.
# Право container-registrypusher/reader даёт возможности и push, и pull собранных образов.
resource "yandex_container_registry_iam_binding" "registry_sa" {
  registry_id = yandex_container_registry.registry.id
  role        = "container-registry.images.pusher"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa_k8s_editor.id}",
  ]
}

resource "yandex_container_registry_iam_binding" "registry_sa_puller" {
  registry_id = yandex_container_registry.registry.id
  role        = "container-registry.images.puller"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa_k8s_editor.id}",
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