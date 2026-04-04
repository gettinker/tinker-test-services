output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "payments_api_url" {
  description = "URL for the payments-api service"
  value       = "http://${aws_lb.main.dns_name}/payments"
}

output "auth_service_url" {
  description = "URL for the auth-service"
  value       = "http://${aws_lb.main.dns_name}/auth"
}

output "order_service_url" {
  description = "URL for the order-service"
  value       = "http://${aws_lb.main.dns_name}/orders"
}

output "inventory_service_url" {
  description = "URL for the inventory-service"
  value       = "http://${aws_lb.main.dns_name}/inventory"
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cloudwatch_log_group_payments" {
  description = "CloudWatch log group for payments-api"
  value       = aws_cloudwatch_log_group.payments_api.name
}

output "cloudwatch_log_group_auth" {
  description = "CloudWatch log group for auth-service"
  value       = aws_cloudwatch_log_group.auth_service.name
}

output "cloudwatch_log_group_orders" {
  description = "CloudWatch log group for order-service"
  value       = aws_cloudwatch_log_group.order_service.name
}

output "cloudwatch_log_group_inventory" {
  description = "CloudWatch log group for inventory-service"
  value       = aws_cloudwatch_log_group.inventory_service.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}
