# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
   client_id       = var.client_id
   features {}
}

resource "random_string" "resource_code" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_resource_group" "tfstate" {
  name     = "tfstate"
  location = "East US"
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "tfstate${random_string.resource_code.result}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = true

  tags = {
    Owner = "feliks_ianganaev@epam.com"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "blob"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.azure_region

  tags = {
    Owner = "feliks_ianganaev@epam.com"
  }
}

### Kubernetes cluster

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.dns_prefix

  linux_profile {
    admin_username = "ubuntu"

    ssh_key {
      key_data = file(var.ssh_public_key)
    }
  }

  default_node_pool {
    name                = "agentpool"
    node_count      = var.agent_count
    vm_size         = "Standard_D2_v2"
  }

  auto_scaler_profile {
    scale_down_delay_after_add = "2m"
    scale_down_unneeded        = "2m"
  }
  
  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id
    }
  }

  identity {
    type = "SystemAssigned"
  }

}

# Container registry
resource "azurerm_container_registry" "acr" {
  name                = "epmacr9081"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Allow AKS to pull images from ACR
resource "azurerm_role_assignment" "aks_to_acr_role" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.k8s.kubelet_identity[0].object_id
}

### Database resources

resource "azurerm_mariadb_server" "dbsrv" {
  name                = "epmdb9081"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "B_Gen5_1"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  administrator_login          = "nhlapp"
  administrator_login_password = var.DB_PASSWORD
  version                      = "10.3"
  ssl_enforcement_enabled      = false
}

resource "azurerm_mariadb_database" "dbprod" {
  name                = "nhlapp"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mariadb_server.dbsrv.name
  charset             = "utf8"
  collation           = "utf8_general_ci"
}

resource "azurerm_mariadb_firewall_rule" "db_firewall_rule" {
  name                = "permit-azure"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mariadb_server.dbsrv.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

### Logging and monitoring resources

resource "random_id" "log_analytics_workspace_name_suffix" {
  byte_length = 8
}

resource "azurerm_log_analytics_workspace" "default" {
  name                = "${var.log_analytics_workspace_name}-${random_id.log_analytics_workspace_name_suffix.dec}"
  location            = var.log_analytics_workspace_location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.log_analytics_workspace_sku
}

resource "azurerm_log_analytics_solution" "ContainerInsights" {
  solution_name         = "ContainerInsights"
  location              = azurerm_log_analytics_workspace.default.location
  resource_group_name   = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.default.id
  workspace_name        = azurerm_log_analytics_workspace.default.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_setting_aks" {
  name                       = "diag_setting_aks"
  target_resource_id         = azurerm_kubernetes_cluster.k8s.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id

  log {
    category = "kube-apiserver"
  }
  log {
    category = "cloud-controller-manager"
  }
  log {
    category = "cluster-autoscaler"
  }
  log {
    category = "guard"
  }
  log {
    category = "kube-apiserver"
  }
  log {
    category = "kube-audit"
  }
  log {
    category = "kube-audit-admin"
  }
  log {
    category = "kube-controller-manager"
  }
  log {
    category = "kube-scheduler"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_setting_acr" {
  name                       = "diag_setting_acr"
  target_resource_id         = azurerm_container_registry.acr.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id

  log {
    category = "ContainerRegistryRepositoryEvents"
  }
  log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_setting_db" {
  name                       = "diag_setting_db"
  target_resource_id         = azurerm_mariadb_server.dbsrv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id

  log {
    category = "MySqlSlowLogs"
  }
  log {
    category = "MySqlAuditLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
