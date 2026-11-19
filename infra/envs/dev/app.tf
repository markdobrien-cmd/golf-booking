# --- The golf booking app, from charts/golf-booking ---
# A stop-gap until Argo CD (Phase 6) takes over app deploys: then Git, not Terraform, decides
# which version runs. Until then this keeps "apply" as the single command that brings dev up.

# Images are in the ECR repositories from infra/bootstrap. Reading one by name gives the
# registry address without writing the account ID in code.
data "aws_ecr_repository" "web" {
  name = "${var.project}/web"
}

resource "helm_release" "golf_booking" {
  name             = "golf-booking"
  chart            = "${path.module}/../../../charts/golf-booking"
  namespace        = "golf"
  create_namespace = true
  timeout          = 600 # waits until every pod is ready, so a bad image fails the apply

  values = [yamlencode({
    image = {
      registry = split("/", data.aws_ecr_repository.web.repository_url)[0]
      tag      = var.app_image_tag
    }
  })]

  # Needs the ServiceMonitor/PrometheusRule types that kube-prometheus-stack installs.
  depends_on = [helm_release.kube_prometheus_stack]
}
