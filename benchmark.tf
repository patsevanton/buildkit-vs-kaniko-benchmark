# Отрисовка манифестов бенчмарка c registry_id из созданного Yandex Container Registry.
# Применяются вручную через kubectl apply (порядок описан в README.md).

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

  # Формирует data-блок ConfigMap из файлов benchmark/projects/<project>.
  # Вложенные пути кодируются "__" -> "/" (ключи ConfigMap не могут содержать '/').
  # Каждый файл -> "  key: |\n" + строки с 4-пробельным отступом.
  context_body = {
    for p in local.benchmark_projects :
    p => join("\n", [
      for f in fileset(path.module, "benchmark/projects/${p}/**/*") :
      format("  %s: |\n%s",
        replace(trimprefix(f, "benchmark/projects/${p}/"), "/", "__"),
        indent(4, file(f))
      )
    ])
  }

  # Имя и контент context ConfigMap для каждого проекта.
  context_configmaps = [for p in local.benchmark_projects : {
    name = "build-context-${p}"
    content = templatefile("${path.module}/benchmark/build-context-configmap.yaml.tftpl", {
      project      = p
      context_data = local.context_body[p]
    })
  }]

  # Пара джобой на проект: kaniko + buildkit.
  job_templates = flatten([for p in local.benchmark_projects : [
    {
      name = "${p}-kaniko"
      content = templatefile("${path.module}/benchmark/kaniko/kaniko-job.yaml.tftpl", {
        registry_id = yandex_container_registry.registry.id
        project     = p
      })
    },
    {
      name = "${p}-buildkit"
      content = templatefile("${path.module}/benchmark/buildkit/buildkit-job.yaml.tftpl", {
        registry_id = yandex_container_registry.registry.id
        project     = p
      })
    },
  ]])
}

resource "local_file" "benchmark_configmaps" {
  for_each        = { for cm in local.context_configmaps : cm.name => cm.content }
  content         = each.value
  filename        = "${path.module}/benchmark/generated/${each.key}.yaml"
  file_permission = "0644"
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