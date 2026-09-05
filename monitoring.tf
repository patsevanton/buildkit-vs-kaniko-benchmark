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