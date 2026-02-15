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