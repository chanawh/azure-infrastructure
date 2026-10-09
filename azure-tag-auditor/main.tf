terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "audit_lab" {
  name     = "rg-tag-auditor-lab"
  location = "eastus"

  tags = {
    owner       = "your-name"
    environment = "dev"
  }
}

resource "azurerm_storage_account" "compliant" {
  name                     = "tagauditgood${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.audit_lab.name
  location                 = azurerm_resource_group.audit_lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    owner       = "your-name"
    environment = "dev"
  }
}

resource "azurerm_storage_account" "missing_environment" {
  name                     = "tagauditbad${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.audit_lab.name
  location                 = azurerm_resource_group.audit_lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    owner = "your-name"
  }
}
