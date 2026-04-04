terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  name_prefix = "tinker-${var.environment}"
  common_tags = {
    Project     = "tinker-test-services"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Resource Group (must already exist — or manage it here)
# ---------------------------------------------------------------------------
data "azurerm_resource_group" "main" {
  name = var.resource_group
}

# ---------------------------------------------------------------------------
# Log Analytics Workspace
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-logs"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 7
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Container Apps Environment
# ---------------------------------------------------------------------------
resource "azurerm_container_app_environment" "main" {
  name                       = "${local.name_prefix}-env"
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.common_tags
}

# ---------------------------------------------------------------------------
# Container App — payments-api
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "payments_api" {
  name                         = "${local.name_prefix}-payments-api"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  ingress {
    external_enabled = true
    target_port      = 8001
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "payments-api"
      image  = "${var.acr_login_server}/payments-api:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8001
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8001
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Container App — auth-service
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "auth_service" {
  name                         = "${local.name_prefix}-auth-service"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  ingress {
    external_enabled = true
    target_port      = 8002
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "auth-service"
      image  = "${var.acr_login_server}/auth-service:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8002
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8002
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Container App — order-service
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "order_service" {
  name                         = "${local.name_prefix}-order-service"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  ingress {
    external_enabled = true
    target_port      = 8003
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "order-service"
      image  = "${var.acr_login_server}/order-service:${var.image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "JAVA_OPTS"
        value = "-Xmx512m -Xms256m"
      }

      liveness_probe {
        transport        = "HTTP"
        path             = "/health"
        port             = 8003
        initial_delay    = 30
        period_seconds   = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        transport        = "HTTP"
        path             = "/health"
        port             = 8003
        initial_delay    = 30
        period_seconds   = 10
        failure_count_threshold = 10
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Container App — inventory-service
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "inventory_service" {
  name                         = "${local.name_prefix}-inventory-service"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  ingress {
    external_enabled = true
    target_port      = 8004
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "inventory-service"
      image  = "${var.acr_login_server}/inventory-service:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8004
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8004
      }
    }
  }
}
