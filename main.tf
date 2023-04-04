terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-2" # Change to the region you want to create the resources in
}

# Create an ECS cluster
resource "aws_ecs_cluster" "tera_cluster" {
  name = "tera-cluster"
}

# Create an ECS task definition
resource "aws_ecs_task_definition" "tera_task_definition" {
  family                   = "tera-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  container_definitions = <<DEFINITION
  [
    {
      "name": "tera-container",
      "image": "nginx:latest",
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ]
    }
  ]
  DEFINITION
}

# Create an ECS service
resource "aws_ecs_service" "tera_service" {
  name            = "tera-service"
  cluster         = aws_ecs_cluster.tera_cluster.id
  task_definition = aws_ecs_task_definition.tera_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_controller {
    type = "ECS"
  }

  network_configuration {
      security_groups  = ["sg-0f119123eae8fe6c9"] # Change to your own security group IDs
      subnets          = ["subnet-075657eeaf652bc83", "subnet-0309d9064f5ce66f9"] # Change to your own subnet IDs
       assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tera_target_group.arn
    container_name   = "tera-container"
    container_port   = 80
  }

  depends_on = [
    aws_ecs_task_definition.tera_task_definition,
    aws_lb_target_group.tera_target_group, # This dependency causes the cycle
  ]

  lifecycle {
    create_before_destroy = true
  }
}


# Create an Application Load Balancer (ALB)
resource "aws_lb" "tera_alb" {
  name               = "tera-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["subnet-075657eeaf652bc83", "subnet-0309d9064f5ce66f9"] # Change to your own subnet IDs
  security_groups    = ["sg-0f119123eae8fe6c9"] # Change to your own security group IDs

  tags = {
    Name = "tera-alb"
  }
}

# Create a listener for the ALB to forward traffic to the ECS service
resource "aws_lb_listener" "tera_listener" {
  load_balancer_arn = aws_lb.tera_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.tera_target_group.arn
    type             = "forward"
  }
}

# Create a target group for the ECS service
resource "aws_lb_target_group" "tera_target_group" {
  name_prefix       = "tera"
  port              = 80
  protocol          = "HTTP"
  vpc_id            = "vpc-0143dac887e83b3c6" # Change to your own VPC ID
  target_type       = "ip"
  deregistration_delay = 60

  health_check {
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  depends_on = [
    aws_lb.tera_alb
  ]
}

# Create a rule for the ALB listener to forward traffic to the target group
resource "aws_lb_listener_rule" "tera_rule" {
  listener_arn = aws_lb_listener.tera_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tera_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/tera"]
    }
  }
}