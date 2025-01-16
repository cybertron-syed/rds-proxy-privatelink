resource "aws_iam_role" "rds_proxy_role" {
  name               = "rds_proxy_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "rds_proxy_policy" {
  name        = "rds_proxy_policy"
  description = "Policy for RDS Proxy"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "secretsmanager:GetSecretValue",
        "rds:DescribeDBInstances"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "rds_proxy_policy_attach" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.rds_proxy_policy.arn
}
