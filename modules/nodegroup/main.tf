data "aws_ssm_parameter" "eks_ami" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/${var.ami_architecture}/${var.ami_variant}/recommended/image_id"
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.eks_ami[0].value)

  autoscaler_tags = {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
  }
}

resource "aws_launch_template" "this" {
  name_prefix = "${var.cluster_name}-${var.node_group_name}-"
  image_id    = local.ami_id

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user_data.tpl", {
    cluster_name     = var.cluster_name
    cluster_endpoint = var.cluster_endpoint
    cluster_ca       = var.cluster_certificate_authority_data
    service_cidr     = var.service_ipv4_cidr
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.autoscaler_tags, {
      Name = "${var.cluster_name}-${var.node_group_name}"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.cluster_name}-${var.node_group_name}"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-${var.node_group_name}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  ami_type        = "CUSTOM"
  capacity_type   = var.capacity_type
  instance_types  = var.instance_types
  labels          = var.labels

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  tags = local.autoscaler_tags

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
