# create a resource group if it doesn't exist
resource "azurerm_resource_group" "rg" {
  name = var.resource_group_name
  location = var.resource_group_location

  tags = {
    "environment" = "production"
  }
}

#create Virtual network
resource "azurerm_virtual_network" "vnet" {
    name = var.virtual_network_name
    address_space = ["10.0.0.0/16"]
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    tags = {
        "environment" = "production"
    }
}

#create Subnet
resource "azurerm_subnet" "subnet" {
    name = var.subnet_name
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes = ["10.0.1.0/24"]
}

#create Public IP
resource "azurerm_public_ip" "public_ip" {
    name = var.public_ip_name
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    allocation_method = "Dynamic"

    tags = {
        "environment" = "production"
    }
}


#create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
    name = var.network_security_group_name
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    security_rule {
    name                       = "allow-ssh"
    priority                   = 500
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    }

    security_rule {
    name                       = "allow-jenkins-service"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    }

    tags = {
        "environment" = "production"

    }
}

#create Network Interface
resource "azurerm_network_interface" "nic" {
    name = var.network_interface_name
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
      name = "myNicConfiguration"
      subnet_id = azurerm_subnet.subnet.id
      private_ip_address_allocation = "Dynamic"
      public_ip_address_id = azurerm_public_ip.public_ip.id
    }
    
    tags = {
        "environment" = "production"
    }
}

#connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "association" {
    network_interface_id = azurerm_network_interface.nic.id
    network_security_group_id = azurerm_network_security_group.nsg.id  
}

#generate random text for a unique storage name
resource "random_id" "randomId" {
   #generate a new ID only when a new resource group is defined
   keepers = {
     resource_group = azurerm_resource_group.rg.name
   }

   byte_length = 8 
}

#create  storage account for boot diagnostics
resource "azurerm_storage_account" "storage" {
  name = "diag${random_id.randomId.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  account_replication_type = "LRS"
  account_tier = "Standard"

  tags = {
    "environment" = "production"
  }
}

#create (and display) an SSH key
resource "tls_private_key" "example_ssh" {
    algorithm = "RSA"
    rsa_bits = 4096
 }

 #create Virtual Machine
 resource "azurerm_linux_virtual_machine" "linuxvm" {
    name = var.linux_virtual_machine_name
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.nic.id]
    size = "Standard_DS1_v2"

    os_disk {
      name = "myOsDisk"
      caching = "ReadWrite"
      storage_account_type = "Premium_LRS"
      // a tester avec Standard_LRS 
    }

    source_image_reference {
      publisher = "Canonical"
      offer = "UbuntuServer"
      sku = "18.04-LTS"
      version = "latest"
    }

    computer_name = "myvm"
    admin_username = "azureuser"
    disable_password_authentication = true

    admin_ssh_key {
      username = "azureuser"
      public_key = tls_private_key.example_ssh.public_key_openssh
    }

    boot_diagnostics {
      storage_account_uri = azurerm_storage_account.storage.primary_blob_endpoint
    }

    tags = {
        "environment" = "production"
    }

 }


 # Connecting ansible from local system
resource "null_resource" "nullremote1" {
  depends_on = [ azurerm_linux_virtual_machine.linuxvm ]

  connection {
    type   = "ssh"
    host  = azurerm_linux_virtual_machine.linuxvm.public_ip_address
    user   ="azureuser"
    private_key = tls_private_key.example_ssh.private_key_pem
  } 

  #copying the init script to the aws instance from local system
  provisioner "file" {
    source = "init.sh"
    destination = "/home/azureuser/init.sh"
  }

   #provisioner "remote-exec" {
   # inline = [
   #   "ansible-playbook /home/azureuser/init.sh"
  #]    
  #}

}