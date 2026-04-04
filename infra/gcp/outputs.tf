output "payments_api_url" {
  description = "Cloud Run URL for payments-api"
  value       = google_cloud_run_v2_service.payments_api.uri
}

output "auth_service_url" {
  description = "Cloud Run URL for auth-service"
  value       = google_cloud_run_v2_service.auth_service.uri
}

output "order_service_url" {
  description = "Cloud Run URL for order-service"
  value       = google_cloud_run_v2_service.order_service.uri
}

output "inventory_service_url" {
  description = "Cloud Run URL for inventory-service"
  value       = google_cloud_run_v2_service.inventory_service.uri
}

output "service_account_email" {
  description = "Service account email used by all Cloud Run services"
  value       = google_service_account.tinker_services.email
}
