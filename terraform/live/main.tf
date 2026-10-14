# Exemple d'instanciation des deux besoins. Une nouvelle demande = un nouveau bloc module.
# Les ARN de modèles sont des exemples : vérifier ceux ouverts sur le compte avec
#   aws bedrock list-inference-profiles --type-equals SYSTEM_DEFINED --region eu-west-1

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.82" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "account_id" {
  type    = string
  default = "000000000000"
}

variable "alert_emails" {
  type    = list(string)
  default = ["prenom.nom@example.com"]
}

locals {
  eu_profile = "arn:aws:bedrock:${var.region}:${var.account_id}:inference-profile"
}

module "uc01_agents_lab" {
  source = "../modules/usecase-baseline"

  use_case            = "uc01-agents-lab"
  business_unit       = "a-renseigner"
  cost_center         = "a-renseigner"
  owner               = "a-renseigner"
  data_classification = "public"
  phase               = "prototype"
  expiry_date         = "2027-06-30"
  monthly_budget_usd  = 300
  budget_alert_emails = var.alert_emails

  bedrock_models = {
    haiku = "${local.eu_profile}/eu.anthropic.claude-haiku-4-5-20251001-v1:0"
  }
}

module "uc02_hydraulic_schema" {
  source = "../modules/usecase-baseline"

  use_case            = "uc02-hydraulic-schema"
  business_unit       = "a-renseigner"
  cost_center         = "a-renseigner"
  owner               = "a-renseigner"
  data_classification = "public"
  phase               = "prototype"
  expiry_date         = "2027-06-30"
  monthly_budget_usd  = 400
  budget_alert_emails = var.alert_emails

  bedrock_models = {
    haiku  = "${local.eu_profile}/eu.anthropic.claude-haiku-4-5-20251001-v1:0"
    sonnet = "${local.eu_profile}/eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
    nova   = "${local.eu_profile}/eu.amazon.nova-pro-v1:0"
  }
}

output "uc01" {
  value = {
    bucket   = module.uc01_agents_lab.bucket_name
    role     = module.uc01_agents_lab.workload_role_arn
    profiles = module.uc01_agents_lab.inference_profile_arns
  }
}

output "uc02" {
  value = {
    bucket   = module.uc02_hydraulic_schema.bucket_name
    role     = module.uc02_hydraulic_schema.workload_role_arn
    profiles = module.uc02_hydraulic_schema.inference_profile_arns
  }
}
