resource "aws_iam_role" "iam_for_stop_start_lambda" {
  name               = "iam_for_stop_start_lambda"
  assume_role_policy = file("${path.module}/policies/lambda-role.json")
}

data "template_file" "iam_policy" {
  template = file("${path.module}/policies/lambda-policy.json")
  vars = {
    instance_arn = var.instance_arn
  }
}

resource "aws_iam_role_policy" "iam_for_stop_start_lambda" {
  name   = "iam_for_stop_start_lambda"
  role   = aws_iam_role.iam_for_stop_start_lambda.id
  policy = data.template_file.iam_policy.rendered
}

data "archive_file" "zip_the_lambda_code" {
  type        = "zip"
  source_dir  = "${path.module}/code/"
  output_path = "${path.module}/code/lambda.zip"
}

resource "aws_lambda_function" "start_lambda" {
  filename      = "${path.module}/code/lambda.zip"
  function_name = "start_lambda"
  role          = aws_iam_role.iam_for_stop_start_lambda.arn
  handler       = "index.start"

  runtime = "nodejs14.x"

  environment {
    variables = {
      instanceArn = var.instance_arn
    }
  }
}

resource "aws_lambda_function" "stop_lambda" {
  filename      = "${path.module}/code/lambda.zip"
  function_name = "stop_lambda"
  role          = aws_iam_role.iam_for_stop_start_lambda.arn
  handler       = "index.stop"

  runtime = "nodejs14.x"

  environment {
    variables = {
      instanceArn = var.instance_arn
    }
  }
}

resource "aws_api_gateway_rest_api" "start-stop-api" {
  name        = "StartStopMinecraftAPI"
  description = "A REST API to start and stop the minecraft server"
}

resource "aws_lambda_permission" "allow_start_api_gateway" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_lambda.arn
  statement_id  = "AllowExecutionFromApiGateway"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.start-stop-api.execution_arn}/*/*/*"
}

resource "aws_lambda_permission" "allow_stop_api_gateway" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_lambda.arn
  statement_id  = "AllowExecutionFromApiGateway"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.start-stop-api.execution_arn}/*/*/*"
}


resource "aws_api_gateway_resource" "start-resource" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  parent_id   = aws_api_gateway_rest_api.start-stop-api.root_resource_id
  path_part   = "start"
}

resource "aws_api_gateway_resource" "stop-resource" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  parent_id   = aws_api_gateway_rest_api.start-stop-api.root_resource_id
  path_part   = "stop"
}

resource "aws_api_gateway_method" "start-action-method" {
  rest_api_id   = aws_api_gateway_rest_api.start-stop-api.id
  resource_id   = aws_api_gateway_resource.start-resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "stop-action-method" {
  rest_api_id   = aws_api_gateway_rest_api.start-stop-api.id
  resource_id   = aws_api_gateway_resource.stop-resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "start-integration" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  resource_id = aws_api_gateway_resource.start-resource.id

  # The HTTP method to integrate with the Lambda function
  http_method = aws_api_gateway_method.start-action-method.http_method

  # AWS is used for Lambda proxy integration when you want to use a Velocity template
  type = "AWS"

  # The URI at which the API is invoked
  uri = aws_lambda_function.start_lambda.invoke_arn

  # Lambda functions can only be invoked via HTTP POST - https://amzn.to/2owMYNh
  integration_http_method = "POST"

  # Configure the Velocity request template for the application/json MIME type
  request_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_integration" "stop-integration" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  resource_id = aws_api_gateway_resource.stop-resource.id

  # The HTTP method to integrate with the Lambda function
  http_method = aws_api_gateway_method.stop-action-method.http_method

  # AWS is used for Lambda proxy integration when you want to use a Velocity template
  type = "AWS"

  # The URI at which the API is invoked
  uri = aws_lambda_function.stop_lambda.invoke_arn

  # Lambda functions can only be invoked via HTTP POST - https://amzn.to/2owMYNh
  integration_http_method = "POST"

  # Configure the Velocity request template for the application/json MIME type
  request_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_method_response" "start-api-method-response" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  resource_id = aws_api_gateway_resource.start-resource.id
  http_method = aws_api_gateway_method.start-action-method.http_method
  status_code = "200"
}

# Configure the API Gateway and Lambda functions response
resource "aws_api_gateway_integration_response" "start-api-integration-response" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  resource_id = aws_api_gateway_resource.start-resource.id
  http_method = aws_api_gateway_method.start-action-method.http_method

  status_code = aws_api_gateway_method_response.start-api-method-response.status_code

  response_templates = {
    "application/json" = ""
  }
  # Remove race condition where the integration response is built before the lambda integration
  depends_on = [
    aws_api_gateway_integration.start-integration
  ]
}

resource "aws_api_gateway_method_response" "stop-api-method-response" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  resource_id = aws_api_gateway_resource.stop-resource.id
  http_method = aws_api_gateway_method.stop-action-method.http_method
  status_code = "200"
}

# Configure the API Gateway and Lambda functions response
resource "aws_api_gateway_integration_response" "stop-api-integration-response" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  resource_id = aws_api_gateway_resource.stop-resource.id
  http_method = aws_api_gateway_method.stop-action-method.http_method

  status_code = aws_api_gateway_method_response.stop-api-method-response.status_code

  response_templates = {
    "application/json" = ""
  }

  # Remove race condition where the integration response is built before the lambda integration
  depends_on = [
    aws_api_gateway_integration.stop-integration
  ]
}

resource "aws_api_gateway_deployment" "start-stop-api-dev-deployment" {
  rest_api_id = aws_api_gateway_rest_api.start-stop-api.id
  stage_name  = "dev"

  # Remove race conditions - deployment should always occur after lambda integration
  depends_on = [
    aws_api_gateway_integration.start-integration,
    aws_api_gateway_integration.stop-integration,
    aws_api_gateway_integration_response.start-api-integration-response,
    aws_api_gateway_integration_response.stop-api-integration-response
  ]
}

# URL to invoke the API
output "url" {
  value = aws_api_gateway_deployment.start-stop-api-dev-deployment.invoke_url
}
