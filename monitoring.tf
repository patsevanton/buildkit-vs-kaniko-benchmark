locals {
  # ----- vmks (victoria-metrics-k8s-stack) -----
  vmks_retention = "14d"
  vmks_pv_size   = "20Gi"

  # ----- Values, отрендеренные из шаблонов *.tftpl -----
  vmks_values = templatefile("${path.module}/values/vmks-values.yaml.tftpl", {
    grafana_fqdn   = local.grafana_fqdn
    vmks_retention = local.vmks_retention
    vmks_pv_size   = local.vmks_pv_size
  })
}

resource "local_file" "write_vmks_values" {
  content         = local.vmks_values
  filename        = "${path.module}/values/vmks-values.yaml"
  file_permission = "0644"
}

# Helm-релиз vmks в namespace vmks.
resource "helm_release" "vmks" {
  name             = "vmks"
  chart            = "victoriametrics/victoria-metrics-k8s-stack"
  repository       = "https://victoriametrics.github.io/helm-charts/"
  version          = "0.91.2"
  namespace        = "vmks"
  create_namespace = true

  values = [
    local.vmks_values
  ]

  depends_on = [
    yandex_kubernetes_cluster.buildkit,
    yandex_kubernetes_node_group.k8s_node_group,
    helm_release.traefik,
  ]

  timeout = 900
}