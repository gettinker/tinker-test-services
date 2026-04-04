terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "tinker-${var.environment}"
  common_tags = {
    Project     = "tinker-test-services"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  services = {
    payments_api      = { port = 8001, path = "/payments*", priority = 10 }
    auth_service      = { port = 8002, path = "/auth*",     priority = 20 }
    order_service     = { port = 8003, path = "/orders*",   priority = 30 }
    inventory_service = { port = 8004, path = "/inventory*",priority = 40 }
  }
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-public-${count.index}" })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-private-${count.index}" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-nat" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP/HTTPS inbound to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Allow inbound from ALB to ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8001
    to_port         = 8004
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-tasks-sg" })
}

# ---------------------------------------------------------------------------
# IAM — ECS Task Execution Role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.common_tags
}

# ---------------------------------------------------------------------------
# CloudWatch Log Groups
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "payments_api" {
  name              = "/tinker/${var.environment}/payments-api"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "auth_service" {
  name              = "/tinker/${var.environment}/auth-service"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/tinker/${var.environment}/order-service"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "inventory_service" {
  name              = "/tinker/${var.environment}/inventory-service"
  retention_in_days = 7
  tags              = local.common_tags
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ---------------------------------------------------------------------------
# ECS Task Definitions
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "payments_api" {
  family                   = "${local.name_prefix}-payments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "payments-api"
    image     = "${var.ecr_registry}/payments-api:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = 8001, protocol = "tcp" }]
    environment  = [{ name = "PYTHONUNBUFFERED", value = "1" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.payments_api.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "payments-api"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8001/health')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "auth_service" {
  family                   = "${local.name_prefix}-auth-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "auth-service"
    image     = "${var.ecr_registry}/auth-service:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = 8002, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.auth_service.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "auth-service"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "node -e \"require('http').get('http://localhost:8002/health', r => process.exit(r.statusCode === 200 ? 0 : 1))\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "order_service" {
  family                   = "${local.name_prefix}-order-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "order-service"
    image     = "${var.ecr_registry}/order-service:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = 8003, protocol = "tcp" }]
    environment = [{ name = "JAVA_OPTS", value = "-Xmx512m -Xms256m" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.order_service.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "order-service"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -sf http://localhost:8003/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 5
      startPeriod = 60
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "inventory_service" {
  family                   = "${local.name_prefix}-inventory-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "inventory-service"
    image     = "${var.ecr_registry}/inventory-service:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = 8004, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.inventory_service.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "inventory-service"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:8004/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = local.common_tags
}

resource "aws_lb_target_group" "payments_api" {
  name        = "${local.name_prefix}-payments-tg"
  port        = 8001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
  tags = local.common_tags
}

resource "aws_lb_target_group" "auth_service" {
  name        = "${local.name_prefix}-auth-tg"
  port        = 8002
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
  tags = local.common_tags
}

resource "aws_lb_target_group" "order_service" {
  name        = "${local.name_prefix}-orders-tg"
  port        = 8003
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
  tags = local.common_tags
}

resource "aws_lb_target_group" "inventory_service" {
  name        = "${local.name_prefix}-inventory-tg"
  port        = 8004
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payments_api.arn
  }
}

resource "aws_lb_listener_rule" "auth" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth_service.arn
  }
  condition {
    path_pattern { values = ["/auth*"] }
  }
}

resource "aws_lb_listener_rule" "orders" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.order_service.arn
  }
  condition {
    path_pattern { values = ["/orders*", "/trigger-error*"] }
  }
}

resource "aws_lb_listener_rule" "inventory" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 40
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inventory_service.arn
  }
  condition {
    path_pattern { values = ["/inventory*", "/items*", "/reserve*"] }
  }
}

# ---------------------------------------------------------------------------
# ECS Services
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "payments_api" {
  name            = "${local.name_prefix}-payments-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.payments_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.payments_api.arn
    container_name   = "payments-api"
    container_port   = 8001
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.common_tags
}

resource "aws_ecs_service" "auth_service" {
  name            = "${local.name_prefix}-auth-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.auth_service.arn
    container_name   = "auth-service"
    container_port   = 8002
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.common_tags
}

resource "aws_ecs_service" "order_service" {
  name            = "${local.name_prefix}-order-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.order_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.order_service.arn
    container_name   = "order-service"
    container_port   = 8003
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.common_tags
}

resource "aws_ecs_service" "inventory_service" {
  name            = "${local.name_prefix}-inventory-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.inventory_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.inventory_service.arn
    container_name   = "inventory-service"
    container_port   = 8004
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.common_tags
}
