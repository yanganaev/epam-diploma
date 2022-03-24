variable "azure_region" {
  default = "eastus"
}

variable "location" {
  default = "East US"
}

variable "resource_group_name" {
  default = "flxiangdiploma"
}

variable "agent_count" {
    default = 2
}

variable "db_username" {
  default = "nhltop"
}

variable "db_password" {
  default = "Qwerty12345!"
}

variable "dns_prefix" {
  default = "aks01"
}

variable "cluster_name" {
  default = "aks01"
}

variable "log_analytics_workspace_name" {
  default = "DefaultLogAnalyticsWorkspaceName"
}

# refer https://azure.microsoft.com/global-infrastructure/services/?products=monitor for log analytics available regions
variable "log_analytics_workspace_location" {
  default = "eastus"
}

# refer https://azure.microsoft.com/pricing/details/monitor/ for log analytics pricing
variable "log_analytics_workspace_sku" {
  default = "PerGB2018"
}
