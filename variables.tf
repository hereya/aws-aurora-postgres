variable "minimum_acu" {
  description = "The minimum allowed ACU for Aurora Serverless V2. Set to 0 to enable scale-to-zero (the cluster auto-pauses when idle)."
  type        = number
  default     = 0.5
}

variable "seconds_until_auto_pause" {
  description = "Idle time in seconds before the cluster scales to zero. Only applies when minimum_acu is 0. Must be between 300 (5 min) and 86400 (1 day)."
  type        = number
  default     = 300

  validation {
    condition     = var.seconds_until_auto_pause >= 300 && var.seconds_until_auto_pause <= 86400
    error_message = "seconds_until_auto_pause must be between 300 and 86400."
  }
}

variable "maximum_acu" {
  description = "The maximum allowed ACU for Aurora Serverless V2."
  type        = number
  default     = 4.0
}

variable "db_version" {
  description = "The Aurora Serverless V2 engine version."
  type        = string
  default     = "17.6"
}

variable "require_ssl" {
  description = "Whether to require SSL connections to the database."
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Aurora cluster. If not provided, new private subnets will be created."
  type        = list(string)
  default     = []
}