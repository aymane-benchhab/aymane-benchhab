# Enveloppe par use-case : tags de refacturation, clé KMS dédiée, bucket S3 chiffré,
# rôle workload ABAC, Bedrock Application Inference Profiles (coût Bedrock ventilable) et budget.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.82" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "${var.use_case}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  tags = merge(var.extra_tags, {
    UseCase            = var.use_case
    BusinessUnit       = var.business_unit
    CostCenter         = var.cost_center
    Owner              = var.owner
    Environment        = var.environment
    DataClassification = var.data_classification
    Phase              = var.phase
    ExpiryDate         = var.expiry_date
    ManagedBy          = "terraform"
  })
}

# ---------------------------------------------------------------------------
# KMS : une CMK par use-case, utilisable seulement par les principals tagués UseCase=<use_case>
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "UseByUseCasePrincipalsOnly"
    actions = [
      "kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/UseCase"
      values   = [var.use_case]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:/${var.use_case}/*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "CMK ${local.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 14
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# S3 : bucket privé, SSE-KMS (CMK du use-case), TLS obligatoire, versionné
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "data" {
  bucket = "${local.name}-${local.account_id}"
  tags   = local.tags
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

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
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

# ---------------------------------------------------------------------------
# Bedrock : 1 Application Inference Profile tagué par modèle.
# C'est ce qui rend la consommation Bedrock ventilable par tag dans Cost Explorer.
# Le code applicatif doit appeler l'ARN du profil (modelId = profile ARN), pas le modelId brut.
# ---------------------------------------------------------------------------
resource "aws_bedrock_inference_profile" "this" {
  for_each = var.bedrock_models

  name        = "${local.name}-${each.key}"
  description = "Profil ${each.key} pour ${var.use_case}"
  model_source {
    copy_from = each.value
  }
  tags = local.tags
}

# ---------------------------------------------------------------------------
# Rôle workload (Lambda, Step Functions, SageMaker, Bedrock KB) tagué UseCase -> accès à SA clé seulement
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
        "states.amazonaws.com",
        "sagemaker.amazonaws.com",
        "bedrock.amazonaws.com",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "workload" {
  name                 = "${local.name}-workload"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = local.tags
}

data "aws_iam_policy_document" "workload" {
  statement {
    sid       = "S3OwnBucket"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
  }

  statement {
    sid       = "KmsOwnKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }

  dynamic "statement" {
    for_each = length(var.bedrock_models) > 0 ? [1] : []
    content {
      sid       = "InvokeOwnInferenceProfiles"
      actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      resources = [for p in aws_bedrock_inference_profile.this : p.arn]
    }
  }

  # Le profil route vers le modèle de fondation (et éventuellement un profil cross-region) :
  # autorisé uniquement quand l'appel passe par un des profils du use-case.
  dynamic "statement" {
    for_each = length(var.bedrock_models) > 0 ? [1] : []
    content {
      sid     = "InvokeUnderlyingModelsViaProfileOnly"
      actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      resources = concat(
        ["arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"],
        values(var.bedrock_models),
      )
      condition {
        test     = "StringEquals"
        variable = "bedrock:InferenceProfileArn"
        values   = [for p in aws_bedrock_inference_profile.this : p.arn]
      }
    }
  }
}

resource "aws_iam_role_policy" "workload" {
  name   = "baseline"
  role   = aws_iam_role.workload.id
  policy = data.aws_iam_policy_document.workload.json
}

# ---------------------------------------------------------------------------
# Budget mensuel filtré sur le tag UseCase (le tag doit être activé en "cost allocation tag")
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "this" {
  name         = "budget-${local.name}"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:UseCase$%s", var.use_case)]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }

  tags = local.tags
}
