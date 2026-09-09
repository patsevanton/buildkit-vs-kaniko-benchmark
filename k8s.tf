# Сервисные аккаунты кластера Managed K8s: отдельно для мастера и для нод.
# Права — минимальные (вместо прежней роли `editor` на весь фолдер),
# согласно документации Yandex Cloud «Managed Service for Kubernetes. Безопасность»:
#   https://yandex.cloud/ru/docs/managed-kubernetes/security/

# Мастер (service_account_id): управление ресурсами кластера от лица мастера.
#   - k8s.clusters.agent    — создание групп узлов, дисков, внутренних балансировщиков
#                             (включает compute.admin, vpc.privateAdmin и др.);
#   - vpc.publicAdmin       — требуется для кластера с публичным доступом;
#   - load-balancer.admin   — в комбинации с k8s.clusters.agent позволяет создавать
#                             сетевой балансировщик с публичным IP (Service LoadBalancer
#                             Traefik через cloud-controller-manager).
resource "yandex_iam_service_account" "sa_k8s_master" {
  folder_id   = var.folder_id
  name        = "sa-k8s-master"
  description = "Master service account of the buildkit Managed K8s cluster"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_k8s_master_clusters_agent" {
  role      = "k8s.clusters.agent"
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa_k8s_master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_k8s_master_vpc_public_admin" {
  role      = "vpc.publicAdmin"
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa_k8s_master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_k8s_master_lb_admin" {
  role      = "load-balancer.admin"
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa_k8s_master.id}"
}

# Ноды (node_service_account_id): IAM-токен из метаданных нод используется
# CI-джобами для push/pull в YCR — роли container-registry.images.pusher/puller
# выданы этому аккаунту на конкретный registry в registry.tf, на фолдер не дублируются.
resource "yandex_iam_service_account" "sa_k8s_node" {
  folder_id   = var.folder_id
  name        = "sa-k8s-node"
  description = "Node service account of the buildkit Managed K8s cluster"
}

# Пауза, чтобы изменения IAM успели примениться до создания кластера.
resource "time_sleep" "wait_sa" {
  create_duration = "20s"
  depends_on = [
    yandex_resourcemanager_folder_iam_member.sa_k8s_master_clusters_agent,
    yandex_resourcemanager_folder_iam_member.sa_k8s_master_vpc_public_admin,
    yandex_resourcemanager_folder_iam_member.sa_k8s_master_lb_admin,
    yandex_container_registry_iam_binding.registry_sa,
    yandex_container_registry_iam_binding.registry_sa_puller,
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

  service_account_id      = yandex_iam_service_account.sa_k8s_master.id
  node_service_account_id = yandex_iam_service_account.sa_k8s_node.id

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
      ]
    }

    resources {
      cores  = 8
      memory = 16
    }

    boot_disk {
      type = "network-ssd"
      size = 100
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