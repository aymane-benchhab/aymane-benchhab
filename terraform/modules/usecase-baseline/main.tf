# Enveloppe d'isolation par use-case : tags, clé KMS dédiée, bucket S3 chiffré, budget.
# Usage :
#   module "uc02" {
#     source             = "./modules/usecase-baseline"
#     use_case           = "uc02-hydraulic-schema"
#     environment        = "dev"
#     cost_center        = "engie-xxxx"
#     owner              = "prenom.nom"
#     data_classification = "public"
#     monthly_budget_usd = 300
#   }

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.60" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name = "${var.use_case}-${var.environment}"
  tags = {
    UseCase            = var.use_case
    Environment        = var.environment
    CostCenter         = var.cost_center
    Owner              = var.owner
    DataClassification = var.data_classification
    Phase              = var.phase
    ExpiryDate         = var.expiry_date
    ManagedBy          = "terraform"
  }
}

# --- KMS : une clé par use-case, utilisable uniquement par les rôles du même use-case (ABAC) ---
data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "Admin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "UseByTaggedRolesOnly"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/UseCase"
      values   = [var.use_case]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Services AWS (Bedrock KB, Neptune, SageMaker...) agissant via un rôle du use-case sont couverts par
  # la condition ci-dessus ; ajouter ici des grants de service si un service n'utilise pas de rôle.
}

resource "aws_kms_key" "this" {
  description             = "CMK ${local.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 14
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

# --- S3 : chiffré CMK, privé, TLS obligatoire ---
resource "aws_s3_bucket" "data" {
  bucket = "${local.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration { status = "Enabled" }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = data.aws_iam_policy_document.bucket.json
}

# --- Budget par use-case (filtré sur le tag UseCase, nécessite l'activation du cost allocation tag) ---
resource "aws_budgets_budget" "this" {
  name         = "budget-${local.name}"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:UseCase$${var.use_case}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# Les ressources de ce module héritent des tags via default_tags du provider :
#   provider "aws" { default_tags { tags = module.<uc>.tags } }
# ou plus simplement, définir default_tags dans le provider avec les mêmes valeurs.
