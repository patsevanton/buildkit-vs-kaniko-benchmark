variable "folder_id" {
  type        = string
  description = "Yandex Cloud folder id"
}

variable "gitlab_api_token" {
  type        = string
  description = "Токен для мониторинга job (не используется в Terraform)"
}

variable "gitlab_runner_token" {
  type        = string
  description = "Токен для установки GitLab Runner (не используется в Terraform)"
}