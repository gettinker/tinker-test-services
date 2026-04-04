terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  name_prefix = "tinker-${var.environment}"
  common_labels = {
    project     = "tinker-test-services"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Enable required APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Service Account for Cloud Run services
# ---------------------------------------------------------------------------
resource "google_service_account" "tinker_services" {
  account_id   = "${local.name_prefix}-svc"
  display_name = "Tinker Test Services — Cloud Run SA"
}

# Grant the SA permission to write logs
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.tinker_services.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.tinker_services.email}"
}

# ---------------------------------------------------------------------------
# Cloud Run — payments-api
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "payments_api" {
  name     = "${local.name_prefix}-payments-api"
  location = var.region

  template {
    service_account = google_service_account.tinker_services.email
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    containers {
      image = "${var.artifact_registry}/payments-api:${var.image_tag}"
      ports { container_port = 8001 }
      env {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
      startup_probe {
        http_get { path = "/health" port = 8001 }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }
      liveness_probe {
        http_get { path = "/health" port = 8001 }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  labels     = local.common_labels
  depends_on = [google_project_service.run]
}

resource "google_cloud_run_v2_service_iam_member" "payments_api_invoker" {
  for_each = toset(var.cloud_run_invoker_members)
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.payments_api.name
  role     = "roles/run.invoker"
  member   = each.value
}

# ---------------------------------------------------------------------------
# Cloud Run — auth-service
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "auth_service" {
  name     = "${local.name_prefix}-auth-service"
  location = var.region

  template {
    service_account = google_service_account.tinker_services.email
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    containers {
      image = "${var.artifact_registry}/auth-service:${var.image_tag}"
      ports { container_port = 8002 }
      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
      startup_probe {
        http_get { path = "/health" port = 8002 }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }
      liveness_probe {
        http_get { path = "/health" port = 8002 }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  labels     = local.common_labels
  depends_on = [google_project_service.run]
}

resource "google_cloud_run_v2_service_iam_member" "auth_service_invoker" {
  for_each = toset(var.cloud_run_invoker_members)
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.auth_service.name
  role     = "roles/run.invoker"
  member   = each.value
}

# ---------------------------------------------------------------------------
# Cloud Run — order-service
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "order_service" {
  name     = "${local.name_prefix}-order-service"
  location = var.region

  template {
    service_account = google_service_account.tinker_services.email
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    containers {
      image = "${var.artifact_registry}/order-service:${var.image_tag}"
      ports { container_port = 8003 }
      env {
        name  = "JAVA_OPTS"
        value = "-Xmx512m -Xms256m"
      }
      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
      }
      startup_probe {
        http_get { path = "/health" port = 8003 }
        initial_delay_seconds = 30
        period_seconds        = 10
        failure_threshold     = 12
      }
      liveness_probe {
        http_get { path = "/health" port = 8003 }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  labels     = local.common_labels
  depends_on = [google_project_service.run]
}

resource "google_cloud_run_v2_service_iam_member" "order_service_invoker" {
  for_each = toset(var.cloud_run_invoker_members)
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.order_service.name
  role     = "roles/run.invoker"
  member   = each.value
}

# ---------------------------------------------------------------------------
# Cloud Run — inventory-service
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "inventory_service" {
  name     = "${local.name_prefix}-inventory-service"
  location = var.region

  template {
    service_account = google_service_account.tinker_services.email
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    containers {
      image = "${var.artifact_registry}/inventory-service:${var.image_tag}"
      ports { container_port = 8004 }
      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
      startup_probe {
        http_get { path = "/health" port = 8004 }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }
      liveness_probe {
        http_get { path = "/health" port = 8004 }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  labels     = local.common_labels
  depends_on = [google_project_service.run]
}

resource "google_cloud_run_v2_service_iam_member" "inventory_service_invoker" {
  for_each = toset(var.cloud_run_invoker_members)
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.inventory_service.name
  role     = "roles/run.invoker"
  member   = each.value
}
