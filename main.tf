terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  backend "remote" {
    organization = "avakil"
    workspaces {
      name = "chargestate"
    }
  }
  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"
}

variable "APNS_CERT" {
  type = string
}

variable "APNS_KEY" {
  type = string
}

resource "aws_sns_platform_application" "platform_app" {
  name                = "ChargestateApp"
  platform            = "APNS_SANDBOX"
  platform_credential = var.APNS_KEY
  platform_principal  = var.APNS_CERT
}

resource "aws_cognito_identity_pool" "id_pool" {
  identity_pool_name               = "ChargestateApp"
  allow_unauthenticated_identities = true
  allow_classic_flow               = false
}

resource "aws_iam_role" "id_pool_role" {
  name = "ChargestateAppUserRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.id_pool.id}"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy" "id_pool_role_policy" {
  name = "ChargestateUserPolicy"
  role = aws_iam_role.id_pool_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": [
          "sns:DeleteEndpoint",
          "sns:SetEndpointAttributes",
          "sns:GetEndpointAttributes",
          "sns:CreatePlatformEndpoint"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VisualEditor1",
      "Effect": "Allow",
      "Action": "states:StartExecution",
      "Resource": "${aws_sfn_state_machine.sfn_state_machine.arn}"
    },
    {
      "Sid": "VisualEditor2",
      "Effect": "Allow",
      "Action": "states:StopExecution",
      "Resource": "arn:aws:states:*:*:execution:${aws_sfn_state_machine.sfn_state_machine.name}:*"
    },
    {
      "Sid": "VisualEditor3",
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "${aws_lambda_function.invoke_sfn_lambda.arn}"
    }
  ]
}
EOF
}

resource "aws_cognito_identity_pool_roles_attachment" "id_pool_role_attachment" {
  identity_pool_id = aws_cognito_identity_pool.id_pool.id

  roles = {
    "unauthenticated" = aws_iam_role.id_pool_role.arn
    "authenticated"   = aws_iam_role.id_pool_role.arn
  }
}

