# Define provider
provider "azurerm" {
  features {}
}

terraform {
  required_version = ">= 1.5.0"
   
  backend "azurerm" {
    resource_group_name  = "MyResourceGroup"
    storage_account_name = "statestoragecase"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

# Variables
variable "location" {
  default = "East US"
}
variable "resource_group_name" {
  default = "MyResourceGroup"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network and Subnets
resource "azurerm_virtual_network" "main" {
  name                = "my-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "public" {
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private" {
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
