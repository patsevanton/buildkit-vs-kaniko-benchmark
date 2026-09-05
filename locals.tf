locals {
  network_id = yandex_vpc_network.buildkit.id

  subnet_b_id   = yandex_vpc_subnet.buildkit-b.id
  subnet_d_id   = yandex_vpc_subnet.buildkit-d.id
  subnet_e_id   = yandex_vpc_subnet.buildkit-e.id
  subnet_b_zone = yandex_vpc_subnet.buildkit-b.zone
  subnet_d_zone = yandex_vpc_subnet.buildkit-d.zone
  subnet_e_zone = yandex_vpc_subnet.buildkit-e.zone

  # Публичный IP балансировщика Traefik. FQDN сервисов формируются через sslip.io.
  ingress_public_ip = yandex_vpc_address.addr.external_ipv4_address[0].address

  grafana_fqdn = "grafana.${local.ingress_public_ip}.sslip.io"

  # Мониторинг живёт в namespace vmks (по AGENTS.md).
  monitoring_namespace = "vmks"

  # ----- Yandex Container Registry -----
  # Имя registry и полный адрес для пуша собранных образов.
  # Стандартный формат Yandex Container Registry: registry.yandex.cloud/<registry_id>/<repo>:<tag>.
  registry_name   = "kaniko-buildkit"
  registry_id     = yandex_container_registry.registry.id
  registry_server = "registry.yandex.cloud/${yandex_container_registry.registry.id}"
}