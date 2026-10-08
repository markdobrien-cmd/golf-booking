# Email alerts before spend gets out of hand. A forgotten EKS cluster costs about $220 a month.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = {
      actual-50    = { type = "ACTUAL", threshold = 50 }
      actual-100   = { type = "ACTUAL", threshold = 100 }
      forecast-100 = { type = "FORECASTED", threshold = 100 }
    }

    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = notification.value.type
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
