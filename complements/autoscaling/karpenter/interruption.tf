resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid    = "AllowEventBridgeSend"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

locals {
  interruption_events = {
    health    = { source = "aws.health", detail_type = "AWS Health Event" }
    spot      = { source = "aws.ec2", detail_type = "EC2 Spot Instance Interruption Warning" }
    rebalance = { source = "aws.ec2", detail_type = "EC2 Instance Rebalance Recommendation" }
    state     = { source = "aws.ec2", detail_type = "EC2 Instance State-change Notification" }
    capacity  = { source = "aws.ec2", detail_type = "EC2 Capacity Reservation Instance Interruption Warning" }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name = "${var.cluster_name}-karpenter-${each.key}"
  event_pattern = jsonencode({
    source      = [each.value.source]
    detail-type = [each.value.detail_type]
  })
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = aws_cloudwatch_event_rule.interruption

  rule = each.value.name
  arn  = aws_sqs_queue.interruption.arn

  depends_on = [aws_sqs_queue_policy.interruption]
}
