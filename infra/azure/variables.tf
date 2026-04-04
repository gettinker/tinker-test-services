variable "resource_group" {
  description = "Azure resource group name"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus, westeurope)"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "image_tag" {
  description = "Docker image tag for all services"
  type        = string
  default     = "latest"
}

variable "acr_login_server" {
  description = "Azure Container Registry login server (e.g. myregistry.azurecr.io)"
  type        = string
}

variable "min_replicas" {
  description = "Minimum number of replicas for each Container App"
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of replicas for each Container App"
  type        = number
  default     = 3
}
