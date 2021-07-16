data "archive_file" "lambda_zip_inline" {
  type        = "zip"
  output_path = "lambda_zip_inline.zip"
  source {
    content  = <<EOF
import json
import boto3

client = boto3.client('stepfunctions')

def lambda_handler(event, context):
    print(event)
    didRemoveArn = False
    try:
        if event.get('AlsoCancel', None):
            client.stop_execution(executionArn=event['AlsoCancel'])
            didRemoveArn = True
    except:
        pass
    result = client.start_execution(
        stateMachineArn='arn:aws:states:us-west-2:017451542414:stateMachine:ChargestateStepFunction',
        name=event['Name'],
        input=json.dumps(event['Input'])
    )
    # TODO implement
    return {
        'statusCode': 200,
        'body': {
            "executionArn": result['executionArn'],
            "didRemoveArn": didRemoveArn
        }
    }
EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "invoke_sfn_lambda" {
  function_name = "ChargestateTriggerLambda"
  role          = aws_iam_role.id_pool_role.arn
  runtime       = "python3.8"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.lambda_zip_inline.output_path
  source_code_hash = data.archive_file.lambda_zip_inline.output_base64sha256
}

data "archive_file" "teslafi_lambda_zip" {
  type        = "zip"
  output_path = "lambda_zip_inline_2.zip"
  source {
    content  = <<EOF
const https = require('https');

const doPostRequest = (event) => {
  return new Promise((resolve, reject) => {
    //create the request object with the callback with the result
    const url = "https://www.teslafi.com/feed.php?token=" + event.Token + "&command=set_charge_limit&charge_limit_soc=" + event.Percent + "&wake=60";
    console.log(url);
    const req = https.get(url,
    (res) => {
      // TODO: Check the response. They return 200 even if the token is bad, so parse their JSON to figure it out
      resolve(JSON.stringify(res.statusCode));
    });

    // handle the possible errors
    req.on('error', (e) => {
      reject(e.message);
    });

    //finish the request
    req.end();
  });
};

exports.handler = async (event) => {
  await doPostRequest(event)
    .then(result => console.log(`Status code: $${result}`))
    .catch(err => console.error(`Error doing the request for the event: $${JSON.stringify(event)} => $${err}`));
};
EOF
    filename = "index.js"
  }
}

resource "aws_lambda_function" "teslafi_lambda" {
  function_name = "ChargestateTeslafiLambda"
  role          = aws_iam_role.id_pool_role.arn
  runtime       = "nodejs14.x"
  timeout       = 600
  handler = "index.handler"

  filename         = data.archive_file.teslafi_lambda_zip.output_path
  source_code_hash = data.archive_file.teslafi_lambda_zip.output_base64sha256
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "ChargestateStepFunction"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<EOF
{
  "Comment": "This is your state machine",
  "StartAt": "Parallel",
  "States": {
    "Parallel": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "Wait 1 Day",
          "States": {
            "Wait 1 Day": {
              "Type": "Wait",
              "Next": "Request Refresh from App",
              "Seconds": 86400
            },
            "Request Refresh from App": {
              "Type": "Task",
              "Resource": "arn:aws:states:::sns:publish",
              "Parameters": {
                "Message.$": "$.Message",
                "TargetArn.$": "$.TargetEndpoint",
                "MessageAttributes": {
                  "AWS.SNS.MOBILE.APNS.PUSH_TYPE": {
                    "DataType": "String",
                    "StringValue": "background"
                  }
                }
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "Map",
          "States": {
            "Map": {
              "Type": "Map",
              "End": true,
              "Iterator": {
                "StartAt": "Wait",
                "States": {
                  "Wait": {
                    "Type": "Wait",
                    "Next": "Send Request to TeslaFi",
                    "TimestampPath": "$.TriggerTime"
                  },
                  "Send Request to TeslaFi": {
                    "Type": "Task",
                    "Resource": "arn:aws:states:::lambda:invoke",
                    "Parameters": {
                      "Payload.$": "$",
                      "FunctionName": "arn:aws:lambda:us-west-2:017451542414:function:ChargestateTeslafiLambda:$LATEST"
                    },
                    "ResultPath": null,
                    "Retry": [
                      {
                        "ErrorEquals": [
                          "Lambda.ServiceException",
                          "Lambda.AWSLambdaException",
                          "Lambda.SdkClientException",
                          "States.TaskFailed"
                        ],
                        "IntervalSeconds": 2,
                        "MaxAttempts": 6,
                        "BackoffRate": 2
                      }
                    ],
                    "Catch": [
                      {
                        "ErrorEquals": [
                          "States.TaskFailed"
                        ],
                        "Next": "Notify Failure"
                      }
                    ],
                    "Next": "Notify Success",
                    "ResultPath": null
                  },
                  "Notify Failure": {
                    "Type": "Task",
                    "Resource": "arn:aws:states:::sns:publish",
                    "Parameters": {
                      "Message.$": "$.NotificationMessageFailure",
                      "TargetArn.$": "$.NotificationEndpoint",
                      "MessageAttributes": {}
                    },
                    "End": true
                  },
                  "Notify Success": {
                    "Type": "Task",
                    "Resource": "arn:aws:states:::sns:publish",
                    "Parameters": {
                      "Message.$": "$.NotificationMessageSuccess",
                      "TargetArn.$": "$.NotificationEndpoint",
                      "MessageAttributes": {}
                    },
                    "End": true
                  }
                }
              },
              "ItemsPath": "$.Events",
              "MaxConcurrency": 1
            }
          }
        }
      ],
      "End": true
    }
  }
}
EOF
}


resource "aws_iam_role" "sfn_role" {
  name = "ChargestateStepFunctionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "states.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "InlinePolicy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          "Sid" : "VisualEditor0",
          "Effect" : "Allow",
          "Action" : "sns:Publish",
          "Resource" : "arn:aws:sns:*:017451542414:*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "*"
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "xray:PutTraceSegments",
            "xray:PutTelemetryRecords",
            "xray:GetSamplingRules",
            "xray:GetSamplingTargets"
          ],
          "Resource" : [
            "*"
          ]
        }
      ]
    })
  }
}
