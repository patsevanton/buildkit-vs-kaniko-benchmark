provider "yandex" {
  folder_id = var.folder_id
}

# Провайдер Helm: доступ к кластеру через yc CLI.
provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.buildkit.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.buildkit.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}

# Провайдер kubernetes: применяет Namespace/Secret/Job бенчмарка в кластер.
provider "kubernetes" {
  host                   = yandex_kubernetes_cluster.buildkit.master[0].external_v4_endpoint
  cluster_ca_certificate = yandex_kubernetes_cluster.buildkit.master[0].cluster_ca_certificate
  exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["k8s", "create-token"]
    command     = "yc"
  }
}