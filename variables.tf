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
  default     = "14.9"
}