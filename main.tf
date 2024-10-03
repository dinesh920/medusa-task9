provider "aws" {
  region = "us-west-1"  # Replace with your desired region
}

# Step 1: Create IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecu"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

# Step 2: Attach the required policy to the role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# Step 3: Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Step 4: Create Subnet
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-1b"  # Adjust based on your needs
}

# Step 5: Create Security Group
resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.main.id
  name   = "ecs_security_group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Adjust to your needs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Step 6: Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "ecs-logs"
  retention_in_days = 7  # Adjust as needed
}

# Step 7: Create ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "task-9-y-cluster"
}

# Step 8: Create ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "din-medusa-task9"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "512"  # Total task CPU
  memory                  = "2048" # Increased task memory to 2048 MiB (2 GB)

  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "medusa-container"
      image     = "dinesh509/medusa-app:latest"  # Ensure this points to your Medusa image
      essential = true
      cpu       = 256  # CPU allocation for Medusa container
      memory    = 1024  # Increased memory limit for Medusa container

      portMappings = [ {
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      } ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = "us-west-1"
          "awslogs-stream-prefix" = "medusa"
        }
      }

      environment = [
        {
          name  = "REDIS_URL"
          value = "redis://medusa-redis:6379"  # Ensure this points to your Redis container
        },
        {
          name  = "DATABASE_URL"
          value = "postgres://postgres:dineshpm15@medusa-postgres:5432/medusa_db"  # Replace with actual values
        }
      ]
    },
    {
      name      = "medusa-postgres"
      image     = "postgres:16"   # Ensure this points to your Postgres image
      essential = true
      cpu       = 256  # CPU allocation for Postgres container
      memory    = 512   # Memory limit for Postgres container

      portMappings = [{
        containerPort = 5432
        hostPort      = 5432
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = "us-west-1"
          "awslogs-stream-prefix" = "postgres"
        }
      }
    }
  ])
}

# Step 9: Create ECS Service
resource "aws_ecs_service" "main" {
  name            = "example-ecs-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1

  launch_type = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.main.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true  # Corrected to boolean
  }
}

# Step 10: Create Autoscaling Target
resource "aws_appautoscaling_target" "main" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"  # Update here
  scalable_dimension  = "ecs:service:DesiredCount"
  service_namespace   = "ecs"
}

# Step 11: Create Autoscaling Policy
resource "aws_appautoscaling_policy" "scale_out" {
  name                   = "scale-out"
  policy_type           = "TargetTrackingScaling"
  resource_id           = aws_appautoscaling_target.main.id
  scalable_dimension     = "ecs:service:DesiredCount"
  service_namespace      = "ecs"

  target_tracking_scaling_policy_configuration {
    target_value       = 75.0 # Adjust based on CPU usage
    scale_in_cooldown  = 300
    scale_out_cooldown = 300

    # Specify predefined metric specifications
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization" # This metric will track CPU utilization
    }
  }
}

# Step 12: Create CloudWatch Alarm for CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "ECS_CPU_Utilization_Alarm"
  alarm_description   = "Alarm when CPU exceeds 75%"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }
  statistic           = "Average"
  period              = 60  # Evaluation period in seconds
  threshold           = 75   # CPU utilization threshold percentage
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2   # Number of periods the condition must be met
  alarm_actions       = []   # Add SNS topic ARN or other action if needed
  ok_actions          = []   # Add actions when the alarm state is OK
  insufficient_data_actions = []  # Add actions when there is insufficient data
}

# Step 13: Create Outputs
output "ecs_service_id" {
  value = aws_ecs_service.main.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_id" {
  value = aws_subnet.main.id
}

output "security_group_id" {
  value = aws_security_group.ecs_sg.id
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.ecs_logs.name
}

output "cloudwatch_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.cpu_alarm.arn
}
