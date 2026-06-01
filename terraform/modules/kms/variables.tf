variable "name" {
  description = "Prefix for all KMS key aliases"
  type        = string
}

variable "deletion_window_in_days" {
  description = "KMS key pending deletion window (7–30 days)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Tags applied to all KMS keys"
  type        = map(string)
  default     = {}
}
