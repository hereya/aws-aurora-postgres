variable "minimum_acu" {
  description = "The minimum allowed ACU for Aurora Serverless V2."
  type        = number
  default     = 0.5
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

variable "subnet_ids" {
  description = "List of subnet IDs for the Aurora cluster. If not provided, new private subnets will be created."
  type        = list(string)
  default     = []
}

variable "storage_encrypted" {
  description = "Whether the cluster storage is encrypted. Changing it on an existing cluster forces replacement: only set it to match a cluster that is already encrypted."
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "ARN of the KMS key encrypting the cluster (with storage_encrypted = true). Null = AWS default key."
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "Days of automated backups to keep (1-35)."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "When true, AWS refuses to delete the cluster (destroy fails instead of dropping the data)."
  type        = bool
  default     = false
}
