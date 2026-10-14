variable "use_case" {
  type        = string
  description = "Identifiant du use-case, ex: uc02-hydraulic-schema"
  validation {
    condition     = can(regex("^uc[0-9]{2}-[a-z0-9-]+$", var.use_case))
    error_message = "use_case doit suivre le format ucNN-nom (minuscules)."
  }
}

variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment: dev, test ou prod."
  }
}

variable "cost_center" {
  type        = string
  description = "Centre de coût / entité métier à refacturer"
}

variable "owner" {
  type        = string
  description = "Responsable du use-case"
}

variable "data_classification" {
  type    = string
  default = "public"
  validation {
    condition     = contains(["public", "internal", "confidential"], var.data_classification)
    error_message = "data_classification: public, internal ou confidential."
  }
}

variable "phase" {
  type    = string
  default = "prototype"
}

variable "expiry_date" {
  type        = string
  default     = "none"
  description = "YYYY-MM-DD pour les prototypes, 'none' sinon"
}

variable "monthly_budget_usd" {
  type    = number
  default = 200
}

variable "budget_alert_email" {
  type = string
}
