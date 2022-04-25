// Copyright (c) 2017, 2021, Oracle and/or its affiliates. All rights reserved.
// Licensed under the Mozilla Public License v2.0


variable "compartment_ocid" {}
variable "region" {}
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key" {}
variable "ssh_public_key1" {}
variable "ssh_public_key2" {}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid = var.user_ocid
  fingerprint = var.fingerprint
  private_key = var.private_key
  region = var.region
}

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
    ssh_authorized_keys = var.ssh_public_key1
    user_data = base64encode(var.user-data-web01)
  }
}

#webserver02
resource "oci_core_instance" "webserver02" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "webserver02"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.prp_subnet_two.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "webserver02"
  }

  source_details {
    source_type = "image"
    source_id   = var.images[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key2
    user_data = base64encode(var.user-data-web02)
  }
}

# User data Variable for deploying webapplication01
variable "user-data-web01" {
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
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --reload
sudo systemctl enable  firewalld
sudo systemctl restart  firewalld  

# echo '########## install git #############'
sudo yum install git -y 

# echo '########### Copy web application source code from GIT to apachwe root directory ##########'
sudo git clone https://github.com/prafulpatel16/prafuls-portfolio-webapp1.git
sudo cp -r prafuls-portfolio-webapp1/src/* /var/www/html/  

touch ~opc/userdata-web01.`date +%s`.finish
echo '################### webserver userdata ends #######################'
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
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --reload
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