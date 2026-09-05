variable "folder_id" {
  type        = string
  description = "Yandex Cloud folder id"
}

variable "benchmark_git_repo" {
  type        = string
  default     = "patsevanton/buildkit-vs-kaniko-benchmark"
  description = "GitHub-репозиторий (owner/repo) с контекстом сборки. Ветка для каждого проекта = имя проекта (flask, nestjs, ...)"
}