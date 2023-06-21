resource "azurerm_resource_group" "example" {
  name     = "avd-rg"
  location = "Central India"
}

resource "azurerm_virtual_desktop_workspace" "workspace" {
  location            = azurerm_resource_group.example.location
  name                = "Workspace"
  resource_group_name = azurerm_resource_group.example.name

}

resource "azurerm_virtual_desktop_host_pool" "HP" {
  description              = "Created through the Azure Virtual Desktop extension"
  location                 = azurerm_resource_group.example.location
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 3
  name                     = "HstPool"
  preferred_app_group_type = "Desktop"
  resource_group_name      = azurerm_resource_group.example.name
  start_vm_on_connect      = true
  type                     = "Pooled"
  custom_rdp_properties    = "audiocapturemode:i:1;audiomode:i:0;"
  validate_environment     = true

}

resource "azurerm_virtual_desktop_application_group" "desktopapp" {
  name                = "appgroupdesktop"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  type          = "Desktop"
  host_pool_id  = azurerm_virtual_desktop_host_pool.HP.id
  friendly_name = "TestAppGroup"
  description   = "Acceptance Test: An application group"
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "ws-dag" {
  application_group_id = azurerm_virtual_desktop_application_group.desktopapp.id
  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
}
resource "azurerm_virtual_desktop_host_pool_registration_info" "hpri" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.HP.id
  expiration_date = "2023-06-24T23:40:52Z"
}



resource "random_string" "AVD_local_password" {
  count            = var.rdsh_count
  length           = 16
  special          = true
  min_special      = 2
  override_special = "*!@#?"
}

resource "azurerm_virtual_network" "example" {
  name                = "example-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "sn" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}


resource "azurerm_network_interface" "avd_vm_nic" {
  count               = var.rdsh_count
  name                = "${var.prefix}-${count.index + 1}-nic"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  ip_configuration {
    name                          = "nic${count.index + 1}_config"
    subnet_id                     = azurerm_subnet.sn.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [
    azurerm_resource_group.example
  ]
}

locals {
  registration_token = azurerm_virtual_desktop_host_pool_registration_info.hpri.token
}

resource "azurerm_windows_virtual_machine" "avd_vm" {

    
  count                 = var.rdsh_count
  name                  = "${var.prefix}-${count.index + 1}"
  resource_group_name   = azurerm_resource_group.example.name
  location              = azurerm_resource_group.example.location
  size                  = var.vm_size
  network_interface_ids = ["${azurerm_network_interface.avd_vm_nic.*.id[count.index]}"]
  provision_vm_agent    = true
  admin_username        = var.local_admin_username
  admin_password        = var.local_admin_password

  os_disk {
    name                 = "${lower(var.prefix)}-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    sku       = "20h2-evd"
    version   = "latest"
  }

  depends_on = [
    azurerm_resource_group.example,
    azurerm_network_interface.avd_vm_nic
  ]
}

resource "azurerm_virtual_machine_extension" "vmext_dsc" {
  count                      = var.rdsh_count
  name                       = "${var.prefix}${count.index + 1}-avd_dsc"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm.*.id[count.index]
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_09-08-2022.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "HostPoolName":"${azurerm_virtual_desktop_host_pool.HP.name}"
      }
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
  {
    "properties": {
      "registrationInfoToken": "${local.registration_token}"
    }
  }
PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_desktop_host_pool.HP
  ]
}



