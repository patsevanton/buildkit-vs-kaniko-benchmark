# S3-бакет с весами ML-модели для проекта ml-pytorch.
# Веса скачиваются в BUILD-стадии Dockerfile обоих инструментов, чтобы замерить
# время сетевого pull большого слоя (~1.28 ГБ — bert-large-uncased/pytorch_model.bin).
#
# Бакет создаётся Terraform'ом и делается публичным (public-read), чтобы ноды
# кластера (без публичных IP, через NAT) могли скачать файл по прямой ссылке.
# Сам файл заливается ОДИН РАЗ вручную — см. TODO.md.
resource "yandex_storage_bucket" "ml_weights" {
  bucket    = "kaniko-vs-buildkit-weights"
  folder_id = var.folder_id

  anonymous_access_flags {
    read = true
    list = true
  }
}

output "ml_weights_url" {
  description = "URL весов ML-модели для BUILD-стадии ml-pytorch"
  value       = "https://storage.yandexcloud.net/${yandex_storage_bucket.ml_weights.bucket}/model.bin"
}