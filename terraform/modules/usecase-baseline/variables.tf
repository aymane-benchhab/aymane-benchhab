variable "use_case" {
  type        = string
  description = "Identifiant du use-case, ex: uc02-hydraulic-schema. Sert de clé de refacturation et d'ABAC."
  validation {
    condition     = can(regex("^uc[0-9]{2}-[a-z0-9-]{3,30}$", var.use_case))
    error_message = "use_case doit suivre le format ucNN-nom (minuscules, chiffres, tirets)."
  }
}

variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment : dev, test ou prod."
  }
}

variable "business_unit" {
  type        = string
  description = "Entité métier demandeuse (refacturation)"
}

variable "cost_center" {
  type        = string
  description = "Centre de coût à refacturer"
}

variable "owner" {
  type        = string
  description = "Responsable technique du use-case"
}

variable "data_classification" {
  type    = string
  default = "public"
  validation {
    condition     = contains(["public", "internal", "confidential"], var.data_classification)
    error_message = "data_classification : public, internal ou confidential."
  }
}

variable "phase" {
  type    = string
  default = "prototype"
  validation {
    condition     = contains(["prototype", "mvp", "run"], var.phase)
    error_message = "phase : prototype, mvp ou run."
  }
}

variable "expiry_date" {
  type        = string
  default     = "none"
  description = "YYYY-MM-DD pour un prototype (nettoyage), 'none' sinon"
  validation {
    condition     = var.expiry_date == "none" || can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.expiry_date))
    error_message = "expiry_date : YYYY-MM-DD ou 'none'."
  }
}

variable "bedrock_models" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Modèles autorisés pour ce use-case : nom court => ARN source (modèle de fondation ou
    profil d'inférence système cross-region). Lister les ARN disponibles avec :
      aws bedrock list-inference-profiles --type-equals SYSTEM_DEFINED
  EOT
}

variable "monthly_budget_usd" {
  type    = number
  default = 200
}

variable "budget_alert_emails" {
  type = list(string)
}

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "Permissions boundary imposée par la plateforme, si elle existe"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
