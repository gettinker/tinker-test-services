variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region to deploy Cloud Run services"
  type        = string
  default     = "us-central1"
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

variable "artifact_registry" {
  description = "Artifact Registry host (e.g. us-central1-docker.pkg.dev/my-project/tinker)"
  type        = string
}

variable "cloud_run_invoker_members" {
  description = "IAM members allowed to invoke Cloud Run services (e.g. ['allUsers'] for public)"
  type        = list(string)
  default     = ["allUsers"]
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances per service"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances per service"
  type        = number
  default     = 3
}
