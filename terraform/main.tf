terraform {
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

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "lambda_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "concurrency-test-lambda"
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (set to -1 for unreserved)"
  type        = number
  default     = 5
}

variable "use_unreserved_concurrency" {
  description = "Whether to use unreserved concurrency (no limits)"
  type        = bool
  default     = false
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy attachment for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function
resource "aws_lambda_function" "concurrency_test" {
  filename      = "lambda_function.zip"
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  # Set reserved concurrency (null means unreserved)
  reserved_concurrent_executions = var.use_unreserved_concurrency ? null : var.reserved_concurrency

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "concurrency_api" {
  name        = "${var.lambda_name}-api"
  description = "API Gateway for Lambda concurrency testing"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Resource
resource "aws_api_gateway_resource" "test_resource" {
  rest_api_id = aws_api_gateway_rest_api.concurrency_api.id
  parent_id   = aws_api_gateway_rest_api.concurrency_api.root_resource_id
  path_part   = "test"
}

# API Gateway Method
resource "aws_api_gateway_method" "test_method" {
  rest_api_id   = aws_api_gateway_rest_api.concurrency_api.id
  resource_id   = aws_api_gateway_resource.test_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Method (OPTIONS for CORS)
resource "aws_api_gateway_method" "test_options" {
  rest_api_id   = aws_api_gateway_rest_api.concurrency_api.id
  resource_id   = aws_api_gateway_resource.test_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.concurrency_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.concurrency_test.invoke_arn
}

# API Gateway Integration (OPTIONS)
resource "aws_api_gateway_integration" "lambda_integration_options" {
  rest_api_id = aws_api_gateway_rest_api.concurrency_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_options.http_method

  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway Method Response (OPTIONS)
resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.concurrency_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# API Gateway Integration Response (OPTIONS)
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.concurrency_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_options.http_method
  status_code = aws_api_gateway_method_response.options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.concurrency_test.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.concurrency_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.lambda_integration_options,
  ]

  rest_api_id = aws_api_gateway_rest_api.concurrency_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.test_resource.id,
      aws_api_gateway_method.test_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.concurrency_api.id
  stage_name    = "prod"
}

# Outputs
output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.concurrency_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/test"
}

output "lambda_function_name" {
  value = aws_lambda_function.concurrency_test.function_name
}

output "reserved_concurrency" {
  value = aws_lambda_function.concurrency_test.reserved_concurrent_executions
}

output "concurrency_type" {
  value = var.use_unreserved_concurrency ? "unreserved" : "reserved"
}
