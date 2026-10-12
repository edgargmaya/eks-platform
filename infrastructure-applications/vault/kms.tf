resource "aws_kms_key" "unseal" {
  description             = "Auto-unseal key for Vault on ${var.cluster_name}. Not the EKS secrets encryption key."
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "unseal" {
  name          = "alias/${var.cluster_name}-vault-unseal"
  target_key_id = aws_kms_key.unseal.key_id
}
