// Copyright (c) 2017, 2021, Oracle and/or its affiliates. All rights reserved.
// Licensed under the Mozilla Public License v2.0
// Copyright (c) 2017, 2021, Oracle and/or its affiliates. All rights reserved.
// Licensed under the Mozilla Public License v2.0
#-------------------------------------------------------------------------------------------------
# Purpose: Deploy Highly Available web application using Load Balancer and Auto scaling inside OCI
# Application Name: Praful's Professional Portfolio 
# Infrastructure Automation: Terraform
# Version Control: GitHub
# State Managment & Pipeline: Terraform Cloud
# ------------------------------------------  
# Author: Praful Patel
# Date & Time: Apr 24, 2022 
# ------------------------------------------
variable "compartment_ocid" {}
variable "region" {}
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key" {}
variable "ssh_public_key" {}
variable "instance_shape" {
  default = "VM.Standard.E2.1.Micro"
}
variable instance_fault_domain_1 {
default = "FAULT-DOMAIN-1"
}
variable instance_fault_domain_2 {
default = "FAULT-DOMAIN-2"
}


#Define provider
provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid = var.user_ocid
  fingerprint = var.fingerprint
  private_key = var.private_key
  region = var.region
}

#Region mapping
variable "ad_region_mapping" {
  type = map(string)

  default = {
    us-phoenix-1 = 1
    us-ashburn-1 = 1
    sa-saopaulo-1 = 1
  }
}

variable "images" {
  type = map(string)

  default = {
    # See https://docs.us-phoenix-1.oraclecloud.com/images/
    # Oracle-provided image "Oracle-Linux-7.9-2020.10.26-0"
    us-phoenix-1   = "ocid1.image.oc1.phx.aaaaaaaacirjuulpw2vbdiogz3jtcw3cdd3u5iuangemxq5f5ajfox3aplxa"
    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaabbg2rypwy5pwnzinrutzjbrs3r35vqzwhfjui7yibmydzl7qgn6a"
    sa-saopaulo-1   = "ocid1.image.oc1.sa-saopaulo-1.aaaaaaaaudio63gdicxwujhfok7jdyewf6iwl6sgcaqlyk4fvttg3bw6gbpq"
  }
}

data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = var.ad_region_mapping[var.region]
}

################################################################################################################
# Networking Components
#1. Create Virtual Cloud Network
#2. Create Subnet
#3. Create Internet Gateway
#4. Create Route Table
#5. Create Security List

resource "oci_core_virtual_network" "prp_vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "prpVCN"
  dns_label      = "prpvcn"
}

resource "oci_core_subnet" "prp_subnet_one" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "prpsubnet1"
  dns_label         = "prpsubnet1"
  security_list_ids = [oci_core_security_list.prp_security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.prp_vcn.id
  route_table_id    = oci_core_route_table.prp_route_table.id
  dhcp_options_id   = oci_core_virtual_network.prp_vcn.default_dhcp_options_id
}

resource "oci_core_subnet" "prp_subnet_two" {
  cidr_block        = "10.1.30.0/24"
  display_name      = "prpsubnet2"
  dns_label         = "prpsubnet2"
  security_list_ids = [oci_core_security_list.prp_security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.prp_vcn.id
  route_table_id    = oci_core_route_table.prp_route_table.id
  dhcp_options_id   = oci_core_virtual_network.prp_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "prp_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "prpIGW"
  vcn_id         = oci_core_virtual_network.prp_vcn.id
}

resource "oci_core_route_table" "prp_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.prp_vcn.id
  display_name   = "prpRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.prp_internet_gateway.id
  }
}

resource "oci_core_security_list" "prp_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.prp_vcn.id
  display_name   = "prpSecurityList"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "22"
      min = "22"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "80"
      min = "80"
    }
  }
}

#webserver01
resource "oci_core_instance" "webserver01" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "webserver01"
  shape               = "VM.Standard.E2.1.Micro"


  create_vnic_details {
    subnet_id        = oci_core_subnet.prp_subnet_one.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "webserver01"
  }

  source_details {
    source_type = "image"
    source_id   = var.images[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(var.user-data-web01)
    
  }
}

#2.Create custom image from instance-template
resource "oci_core_image" "webapp_custom_image" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.webserver01.id
  launch_mode    = "NATIVE"

  timeouts {
    create = "30m"
  }
}

#3.Create instance congifurations
resource "oci_core_instance_configuration" "prpInstanceConfiguration" {
  compartment_id = var.compartment_ocid
  display_name   = "prpInstanceConfiguration"

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      ipxe_script    = "ipxeScript"
      shape          = var.instance_shape
      display_name   = "prpInstanceConfigurationLaunchDetails"

      create_vnic_details {
        assign_public_ip       = true
        display_name           = "prpInstanceConfigurationVNIC"
        skip_source_dest_check = false
        subnet_id              = oci_core_subnet.prp_subnet_one.id
      }

      extended_metadata = {
        some_string   = "stringA"
        nested_object = "{\"some_string\": \"stringB\", \"object\": {\"some_string\": \"stringC\"}}"
        
        
      }

      source_details {
        source_type = "image"
        image_id    = oci_core_image.webapp_custom_image.id
      }
    }
  }
}

#4.Create instance pool

resource "oci_core_instance_pool" "prpInstancePool" {
  compartment_id            = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.prpInstanceConfiguration.id
  size                      = 2
  state                     = "RUNNING"
  display_name              = "WebServer"

  placement_configurations {
    availability_domain = data.oci_identity_availability_domain.ad.name
    fault_domains = [
      var.instance_fault_domain_1, var.instance_fault_domain_2]
    primary_subnet_id   = oci_core_subnet.prp_subnet_one.id
   
  }

  load_balancers {
    #Required
    backend_set_name = oci_load_balancer_backend_set.prp-lb-backset.name
    load_balancer_id = oci_load_balancer.prp-lb.id
    port = 80
    vnic_selection = "primaryvnic"  
  }
  lifecycle {
    ignore_changes = [size]
  }
  
}

##################################################################################################################
#Create datasets
data "oci_core_instance_configuration" "prpInstanceConfiguration" {
  instance_configuration_id = oci_core_instance_configuration.prpInstanceConfiguration.id
}

data "oci_core_instance_pool" "prpInstancePool" {
  instance_pool_id = oci_core_instance_pool.prpInstancePool.id
}

data "oci_core_instance_pool_load_balancer_attachment" "prp_instance_pool_load_balancer_attachment" {
  instance_pool_id                          = oci_core_instance_pool.prpInstancePool.id
  instance_pool_load_balancer_attachment_id = oci_core_instance_pool.prpInstancePool.load_balancers[0].id
}

###################################################################################################################
#Auto scaling process
#1. Create Auto Scaling configurations
resource "oci_autoscaling_auto_scaling_configuration" "prpAutoScalingConfiguration" {
  compartment_id       = var.compartment_ocid
  cool_down_in_seconds = "300"
  display_name         = "prpAutoScalingConfiguration"
  is_enabled           = "true"

  policies {
    capacity {
      initial = "2"
      max     = "4"
      min     = "2"
    }

    display_name = "TFPolicy"
    policy_type  = "threshold"

    rules {
      action {
        type  = "CHANGE_COUNT_BY"
        value = "1"
      }

      display_name = "TFScaleOutRule"

      metric {
        metric_type = "CPU_UTILIZATION"

        threshold {
          operator = "GT"
          value    = "60"
        }
      }
    }

    rules {
      action {
        type  = "CHANGE_COUNT_BY"
        value = "-1"
      }

      display_name = "TFScaleInRule"

      metric {
        metric_type = "CPU_UTILIZATION"

        threshold {
          operator = "LT"
          value    = "1"
        }
      }
    }
  }

  auto_scaling_resources {
    id   = oci_core_instance_pool.prpInstancePool.id
    type = "instancePool"
  }
}


# User data Variable for deploying webapplication01
variable "user-data-web01" {
  default = <<EOF
#!/bin/bash -x

# Purpose: Install apache webserver, Copy Praful's portfolio web application source code from github to apache webserver root
# Author: Praful Patel
# Date & Time: Apr 24, 2022 
# ------------------------------------------

echo '################### webserver userdata begins #####################'
touch ~opc/userdata-web01.`date +%s`.start
# echo '########## yum update all ###############'
# sudo yum update -y
echo '########## basic webserver ##############'
sudo yum install -y httpd
sudo systemctl enable  httpd.service
sudo systemctl start  httpd.service

# echo '########## install firewall ############'
sudo firewall-offline-cmd --add-service=http
sudo systemctl enable  firewalld
sudo systemctl restart  firewalld  

# echo '########## install git #############'
sudo yum install git -y 

# echo '########### Copy web application source code from GIT to apachwe root directory ##########'

sudo git clone https://github.com/prafulpatel16/prafuls-portfolio-webapp1.git
sudo cp -r prafuls-portfolio-webapp1/src/* /var/www/html/  

touch ~opc/userdata-web01.`date +%s`.finish
echo '################### webserver userdata ends ##########################'
EOF

}

# User data Variable for deploying webapplication02
variable "user-data-web02" {
  default = <<EOF
#!/bin/bash -x

# Purpose: Install apache webserver and copy praful's portfolio web application from github to apache webserver
# Author: Praful Patel
# Date & Time: Apr 24, 2022 
# ------------------------------------------

echo '################### webserver userdata begins #####################'
touch ~opc/userdata-web01.`date +%s`.start
# echo '########## yum update all ###############'
# sudo yum update -y
echo '########## basic webserver ##############'
sudo yum install -y httpd
sudo systemctl enable  httpd.service
sudo systemctl start  httpd.service

# echo '########## install firewall ############'
sudo firewall-offline-cmd --add-service=http
sudo systemctl enable  firewalld
sudo systemctl restart  firewalld  

# echo '########## install git #############'
sudo yum install git -y 

# echo '########### Copy web application source code from GIT to apachwe root directory ##########'
sudo git clone https://github.com/prafulpatel16/prafuls-portfolio-webapp2.git
sudo cp -r prafuls-portfolio-webapp2/src/* /var/www/html/  

touch ~opc/userdata-web01.`date +%s`.finish
echo '################### webserver userdata ends #######################'
EOF

}

# reserve public ip
resource "oci_core_public_ip" "prp_reserved_ip" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"

  lifecycle {
    ignore_changes = [private_ip_id]
  }
}

###############################################################################################
# Load Balancer Components:
#1.Add details
#2.Create Backendset
#3.Configure Listner
#4.Create Backend1
/* Load Balancer */
# Add Details
resource "oci_load_balancer" "prp-lb" {
  shape          = "10Mbps"
  compartment_id = var.compartment_ocid

  subnet_ids = [
    oci_core_subnet.prp_subnet_one.id,
    
  ]

  display_name = "prp-lb"
  reserved_ips {
    id = oci_core_public_ip.prp_reserved_ip.id
  }
}

# Choose BackendSet
resource "oci_load_balancer_backend_set" "prp-lb-backset" {
  name             = "prp-lb-backset"
  load_balancer_id = oci_load_balancer.prp-lb.id
  policy           = "ROUND_ROBIN"

  health_checker {
    port                = "80"
    protocol            = "TCP"
    response_body_regex = ".*"
    url_path            = "/"
  }
}
# Create Backend 1
resource "oci_load_balancer_backend" "prp-lb-backend1" {
  load_balancer_id = oci_load_balancer.prp-lb.id
  backendset_name  = oci_load_balancer_backend_set.prp-lb-backset.name
  ip_address       = oci_core_instance.webserver01.private_ip
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

#Configure Listner
resource "oci_load_balancer_listener" "prp-lb-listener" {
  load_balancer_id         = oci_load_balancer.prp-lb.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.prp-lb-backset.name
  port                     = 80
  protocol                 = "HTTP"
  

  connection_configuration {
    idle_timeout_in_seconds = "2"
  }
}


output "lb_public_ip" {
  value = [oci_load_balancer.prp-lb.ip_address_details]
}