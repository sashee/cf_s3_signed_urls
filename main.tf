provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_s3_bucket" "bucket" {
	force_destroy = "true"
}

resource "aws_s3_bucket_object" "object" {
  bucket = "${aws_s3_bucket.bucket.bucket}"
  key    = "index.html"
  content = "Hello world!"
	content_type = "text/html"
}

# signer lambda + api gw

data "archive_file" "lambda_zip" {
	type = "zip"
	source_dir = "src"
	output_path = "/tmp/lambda.zip"
}

resource "aws_lambda_function" "signer_lambda" {
	function_name = "cf-signer-${random_id.id.hex}-function"

  filename = "${data.archive_file.lambda_zip.output_path}"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"

  handler = "main.handler"
  runtime = "nodejs10.x"
  role = "${aws_iam_role.lambda_exec.arn}"
	environment {
		variables = {
			BUCKET = "${aws_s3_bucket.bucket.bucket}"
			DISTRIBUTION_DOMAIN = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
		}
	}
}

data "aws_iam_policy_document" "lambda_exec_role_policy" {
	statement {
		sid = "1"
		actions = [
			"logs:CreateLogGroup",
			"logs:CreateLogStream",
			"logs:PutLogEvents"
		]
		resources = [
			"arn:aws:logs:*:*:*"
		]
	}
	statement {
		sid = "2"
		actions = [
			"s3:GetObject",
		]
		resources = [
			"${aws_s3_bucket.bucket.arn}/*"
		]
	}
}

resource "aws_iam_role_policy" "lambda_exec_role" {
	role = "${aws_iam_role.lambda_exec.id}"
	policy = "${data.aws_iam_policy_document.lambda_exec_role_policy.json}"
}

# IAM role which dictates what other AWS services the Lambda function
# may access.
resource "aws_iam_role" "lambda_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# api gw

resource "aws_api_gateway_rest_api" "rest_api" {
	name = "cf-signer-${random_id.id.hex}-rest-api"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  parent_id   = "${aws_api_gateway_rest_api.rest_api.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.signer_lambda.invoke_arn}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id   = "${aws_api_gateway_rest_api.rest_api.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.signer_lambda.invoke_arn}"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  stage_name  = "test"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.signer_lambda.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.deployment.execution_arn}/*/*"
}

output "signer_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.bucket.bucket_regional_domain_name}"
    origin_id   = "1"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "1"

		# limit caching
		default_ttl = 1800
		min_ttl = 1800
		max_ttl = 1800

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }
	restrictions {
		geo_restriction {
			restriction_type = "none"
		}
	}
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "domain_name" {
	value = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
}
