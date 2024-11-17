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


###Resources for Private Subnet

resource "azurerm_subnet" "private" {
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  
  enforce_private_link_endpoint_network_policies = true
}


resource "azurerm_api_management" "apim" {
  name                = "private-apim"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_email     = "admin@apim.com"
  publisher_name      = "API Team"

  sku {
    name     = "Developer"
    capacity = 1
  }

  virtual_network_configuration {
    subnet_id = azurerm_subnet.private.id
  }

  identity {
    type = "SystemAssigned"
  }
}


resource "azurerm_api_management_api" "backend_api" {
  name                = "backend-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Backend API"
  path                = "backend"
  protocols           = ["https"]
}

resource "azurerm_api_management_api_operation" "backend_api_operation" {
  operation_id        = "post-operation"
  api_name            = azurerm_api_management_api.backend_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Post Data"
  method              = "POST"
  url_template        = "/data"
}

resource "azurerm_api_management_backend" "backend_service" {
  name                = "backend-service"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.apim.name
  url                 = "http://10.0.1.XX:8080" # Backend service private IP and port just example
  protocol            = "http"
}


resource "azurerm_network_security_group" "backend_service_nsg" {
  name                = "backend-service-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-apim"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "10.0.1.0/24" # Private subnet only traffic
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "deny-all"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_network_security_group" "backend_outbound_nsg" {
  name                = "backend-outbound-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-bank"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "203.0.113.0/24" # Bank's IP range
    destination_port_range     = "443"
  }

  security_rule {
    name                       = "deny-all-outbound"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}


resource "azurerm_subnet_network_security_group_association" "pvtsubnet_nsg_outbound" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.backend_outbound_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "pvtsubnet_nsg_inbound" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.backend_service_nsg.id
}


resource "azurerm_private_endpoint" "apim_endpoint" {
  name                = "apim-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private.id

  private_service_connection {
    name                           = "apim-connection"
    private_connection_resource_id = azurerm_api_management.apim.id
    subresource_names              = ["gateway"]
  }
}

# App Service for Backend Service #1 (Bank Integration)
resource "azurerm_app_service_plan" "backend1_plan" {
  name                = "backend1-plan"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "backend1" {
  name                = "backend-service1"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  app_service_plan_id = azurerm_app_service_plan.backend1_plan.id

  site_config {
    ip_restriction {
      ip_address = "203.0.113.0/24" # Bank's IP range
    }
    always_on = true
    linux_fx_version = "DOCKER|my-backend-service:latest"
  }
}


resource "azurerm_sql_server" "backend1_server" {
  name                         = "backend1-sql-server"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "your-strong-password"
}

resource "azurerm_sql_database" "backend_db1" {
  name                = "backend_db1-sql-database"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  server_name         = azurerm_sql_server.backend1_server.name
  edition             = "Basic"
}

# Storage Account for React App
resource "azurerm_storage_account" "static_site" {
  name                     = "mystaticwebapp"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


resource "azurerm_storage_blob" "static_site_blob" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.static_site.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "path/to/index.html" ### Index.html file can be placed to Repository only and same path can be placed here.
}

resource "azurerm_cdn_profile" "cdn" {
  name                = "cdn-profile"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard_Microsoft"
}

resource "azurerm_cdn_endpoint" "cdn_endpoint" {
  name                = "cdn-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  profile_name        = azurerm_cdn_profile.cdn.name
  location            = var.location
  origin {
    name      = "static-site"
    host_name = "${azurerm_storage_account.static_site.primary_web_endpoint}"
  }
}

##Public Subnet backedn application.

resource "azurerm_subnet" "public" {
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}


resource "azurerm_app_service_plan" "backend2_plan" {
  name                = "backend2-plan"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "backend2" {
  name                = "backend-service2"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  app_service_plan_id = azurerm_app_service_plan.backend2_plan.id

  site_config {
    ip_restriction {
      ip_address = "0.0.0.0/0" # Publicly accessible
    }
  }
  always_on = true
  linux_fx_version = "DOCKER|my-backend-service:latest"
}

resource "azurerm_sql_server" "backend2_server" {
  name                         = "backend2-sql-server"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "your-strong-password"
}

resource "azurerm_sql_database" "backend_db2" {
  name                = "backend_db2-sql-database"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  server_name         = azurerm_sql_server.backend2_server.name
  edition             = "Basic"
}

resource "azurerm_api_management" "apim_public" {
  name                = "apim_public"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "apim_public"
  publisher_email     = "apim_public@apim.com"
  sku_name            = "Consumption_ExtraSmall"
}

resource "azurerm_api_management_api" "backend_api_public" {
  name                = "backend_api_public"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.apim_public.name
  revision            = "1"
  display_name        = "Public API"
  path                = "backend_api_public"
  protocols           = ["https"]

  import {
    content_format = "swagger-link-json"
    content_value  = "https://path-to-your-swagger-file.json" # Contract build with source system can be imported.
  }
  
  service_url = "https://example-api-app.azurewebsites.net" # URL of Backend Service.
}

resource "azurerm_api_management_api_operation" "rate_limited_operation" {
  operation_id        = "rate-limited-operation"
  api_name            = azurerm_api_management_api.backend_api_public.name
  api_management_name = azurerm_api_management.apim_public.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Rate Limited Operation"
  method              = "GET"
  url_template        = "/operation"

  response {
    status = 200
    description = "Successful response"
  }

  request {
    description = "Request to the operation"
  }

  rate_limit {
    max_requests_per_second = 10
  }
}
