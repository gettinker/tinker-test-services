output "payments_api_fqdn" {
  description = "FQDN for the payments-api Container App"
  value       = azurerm_container_app.payments_api.latest_revision_fqdn
}

output "auth_service_fqdn" {
  description = "FQDN for the auth-service Container App"
  value       = azurerm_container_app.auth_service.latest_revision_fqdn
}

output "order_service_fqdn" {
  description = "FQDN for the order-service Container App"
  value       = azurerm_container_app.order_service.latest_revision_fqdn
}

output "inventory_service_fqdn" {
  description = "FQDN for the inventory-service Container App"
  value       = azurerm_container_app.inventory_service.latest_revision_fqdn
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "container_app_environment_id" {
  description = "Container Apps environment resource ID"
  value       = azurerm_container_app_environment.main.id
}
