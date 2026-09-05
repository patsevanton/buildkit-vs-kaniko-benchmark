# Сервисный аккаунт для управления Kubernetes.
resource "yandex_iam_service_account" "sa_k8s_editor" {
  folder_id = var.folder_id
  name      = "sa-k8s-editor"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_k8s_editor_permissions" {
  role      = "editor"
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa_k8s_editor.id}"
}

# Пауза, чтобы изменения IAM успели примениться до создания кластера.
resource "time_sleep" "wait_sa" {
  create_duration = "20s"
  depends_on = [
    yandex_iam_service_account.sa_k8s_editor,
    yandex_resourcemanager_folder_iam_member.sa_k8s_editor_permissions
  ]
}

# Kubernetes-кластер в Yandex Managed Service for Kubernetes.
resource "yandex_kubernetes_cluster" "buildkit" {
  name       = "buildkit"
  folder_id  = var.folder_id
  network_id = local.network_id

  master {
    version = "1.33"
    regional {
      region = "ru-central1"

      location {
        zone      = local.subnet_b_zone
        subnet_id = local.subnet_b_id
      }

      location {
        zone      = local.subnet_d_zone
        subnet_id = local.subnet_d_id
      }

      location {
        zone      = local.subnet_e_zone
        subnet_id = local.subnet_e_id
      }
    }

    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.sa_k8s_editor.id
  node_service_account_id = yandex_iam_service_account.sa_k8s_editor.id

  release_channel = "STABLE"

  depends_on = [
    time_sleep.wait_sa,
    time_sleep.wait_lb_release,
  ]
}

# Группа узлов.
resource "yandex_kubernetes_node_group" "k8s_node_group" {
  description = "Node group for kaniko vs buildkit benchmark"
  name        = "k8s-node-group"
  cluster_id  = yandex_kubernetes_cluster.buildkit.id
  version     = "1.33"

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    location { zone = local.subnet_b_zone }
    location { zone = local.subnet_d_zone }
    location { zone = local.subnet_e_zone }
  }

  instance_template {
    platform_id = "standard-v3"

    scheduling_policy {
      preemptible = true
    }

    network_interface {
      nat = false
      subnet_ids = [
        local.subnet_b_id,
        local.subnet_d_id,
        local.subnet_e_id
      ]
    }

    resources {
      cores  = 4
      memory = 8
    }

    boot_disk {
      type = "network-ssd"
      size = 30
    }
  }
}

# Traefik как ingress-контроллер.
resource "helm_release" "traefik" {
  name             = "traefik"
  chart            = "traefik"
  repository       = "https://traefik.github.io/charts"
  version          = "41.3.0"
  namespace        = "traefik"
  create_namespace = true

  depends_on = [
    yandex_kubernetes_cluster.buildkit,
    yandex_kubernetes_node_group.k8s_node_group,
    time_sleep.wait_lb_release,
  ]

  values = [
    yamlencode({
      image = {
        registry   = "ghcr.io"
        repository = "traefik/traefik"
      }
      service = {
        spec = {
          type           = "LoadBalancer"
          loadBalancerIP = local.ingress_public_ip
        }
      }
    })
  ]
}

output "k8s_cluster_credentials_command" {
  value = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.buildkit.id} --external --force"
}

output "k8s_cluster_id" {
  description = "ID кластера"
  value       = yandex_kubernetes_cluster.buildkit.id
}

output "ingress_public_ip" {
  description = "External Traefik IP"
  value       = local.ingress_public_ip
}

output "grafana_url" {
  description = "URL Grafana (сформирован через sslip.io)"
  value       = "http://${local.grafana_fqdn}"
}

output "grafana_admin_password_command" {
  description = "Команда получения пароля администратора Grafana"
  value       = "kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 --decode; echo"
}