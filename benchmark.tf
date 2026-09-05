# Отрисовка манифестов бенчмарка c registry_id из созданного Yandex Container Registry.
# Применяются вручную через kubectl apply (порядок описан в README.md).
#
# Контекст сборки передаётся из git-репозитория: init-контейнер git-clone в каждой
# Job клонирует отдельную ветку <project> (Dockerfile + исходники в корне ветки)
# прямо в /workspace (классическая схема: контекст — git-репозиторий, ветка на проект).

locals {
  benchmark_projects = [
    "flask",
    "nestjs",
    "nextjs",
    "nuxt",
    "go",
    "android",
    "ml-pytorch",
  ]

  # URL публичного git-репозитория с контекстом сборки.
  # Ветка для каждого проекта = имя проекта (benchmark_projects). Базовый
  # git-репозиторий настраивается переменной benchmark_git_repo.
  benchmark_git_url = "https://github.com/${var.benchmark_git_repo}.git"

  # Пара джобой на проект: kaniko + buildkit.
  job_templates = flatten([for p in local.benchmark_projects : [
    {
      name = "${p}-kaniko"
      content = templatefile("${path.module}/benchmark/kaniko/kaniko-job.yaml.tftpl", {
        registry_id = yandex_container_registry.registry.id
        project     = p
        git_url     = local.benchmark_git_url
        git_branch  = p
      })
    },
    {
      name = "${p}-buildkit"
      content = templatefile("${path.module}/benchmark/buildkit/buildkit-job.yaml.tftpl", {
        registry_id = yandex_container_registry.registry.id
        project     = p
        git_url     = local.benchmark_git_url
        git_branch  = p
      })
    },
  ]])
}

resource "local_file" "benchmark_jobs" {
  for_each        = { for j in local.job_templates : j.name => j.content }
  content         = each.value
  filename        = "${path.module}/benchmark/generated/${each.key}-job.yaml"
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
      -f benchmark/generated/
    # Затем смотреть результат:
    kubectl -n kaniko-benchmark get jobs -w
  EOT
}