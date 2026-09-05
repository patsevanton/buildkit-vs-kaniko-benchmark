# Отрисовка манифестов бенчмарка c registry_id из созданного Yandex Container Registry.
# Применяются вручную через kubectl apply (порядок описан в README.md).

locals {
  kaniko_job   = templatefile("${path.module}/benchmark/kaniko/kaniko-job.yaml.tftpl", { registry_id = yandex_container_registry.registry.id })
  buildkit_job = templatefile("${path.module}/benchmark/buildkit/buildkit-job.yaml.tftpl", { registry_id = yandex_container_registry.registry.id })
}

resource "local_file" "kaniko_job" {
  content         = local.kaniko_job
  filename        = "${path.module}/benchmark/kaniko/kaniko-job.yaml"
  file_permission = "0644"
}

resource "local_file" "buildkit_job" {
  content         = local.buildkit_job
  filename        = "${path.module}/benchmark/buildkit/buildkit-job.yaml"
  file_permission = "0644"
}

output "registry_server" {
  description = "Полный адрес Yandex Container Registry для пуша образов"
  value       = local.registry_server
}

output "apply_benchmark_command" {
  description = "Команды применения манифестов бенчмарка"
  value       = <<-EOT
    kubectl apply -f benchmark/namespace.yaml \\
      -f benchmark/scripts-configmap.yaml \\
      -f benchmark/build-context-configmap.yaml \\
      -f benchmark/kaniko/kaniko-job.yaml \\
      -f benchmark/buildkit/buildkit-job.yaml
    # Затем смотреть результат:
    kubectl -n kaniko-benchmark get jobs -w
  EOT
}