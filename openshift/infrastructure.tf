terraform {
  required_version = ">= 1.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.38.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.1"
    }
  }
}

# Reginal Infrastructure Terraform Provider
provider "oci" {
  region = var.region
}

data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_regions" "regions" {}

locals {
  region_map = {
    for r in data.oci_identity_regions.regions.regions :
    r.key => r.name
  }

  home_region = local.region_map[data.oci_identity_tenancy.tenancy.home_region_key]
}

# Home Region Terraform Provider
provider "oci" {
  alias  = "home"
  region = local.home_region
}

locals {
  all_protocols                   = "all"
  anywhere                        = "0.0.0.0/0"
  create_openshift_instance_pools = true
  pool_formatter_id               = join("", ["$", "{launchCount}"])
}

data "oci_identity_availability_domain" "availability_domain" {
  compartment_id = var.compartment_ocid
  ad_number      = "1"
}

data "oci_core_compute_global_image_capability_schemas" "image_capability_schemas" {
}

locals {
  global_image_capability_schemas = data.oci_core_compute_global_image_capability_schemas.image_capability_schemas.compute_global_image_capability_schemas
  image_schema_data = {
    "Compute.Firmware" = "{\"values\": [\"UEFI_64\"],\"defaultValue\": \"UEFI_64\",\"descriptorType\": \"enumstring\",\"source\": \"IMAGE\"}"
  }
}

resource "oci_core_image" "openshift_image" {
  count          = local.create_openshift_instance_pools ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = var.cluster_name
  launch_mode    = "PARAVIRTUALIZED"

  image_source_details {
    source_type = "objectStorageUri"
    source_uri  = var.openshift_image_source_uri

    source_image_type = "QCOW2"
  }
}

resource "oci_core_compute_image_capability_schema" "openshift_image_capability_schema" {
  count                                               = local.create_openshift_instance_pools ? 1 : 0
  compartment_id                                      = var.compartment_ocid
  compute_global_image_capability_schema_version_name = local.global_image_capability_schemas[0].current_version_name
  image_id                                            = oci_core_image.openshift_image[0].id
  schema_data                                         = local.image_schema_data
}

##Define network
resource "oci_core_vcn" "openshift_vcn" {
  cidr_blocks = [
    var.vcn_cidr,
  ]
  compartment_id = var.compartment_ocid
  display_name   = var.cluster_name
  dns_label      = var.vcn_dns_label
}

resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "InternetGateway"
  vcn_id         = oci_core_vcn.openshift_vcn.id
}

resource "oci_core_nat_gateway" "nat_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  display_name   = "NatGateway"
}

data "oci_core_services" "oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "service_gateway" {
  #Required
  compartment_id = var.compartment_ocid

  services {
    service_id = data.oci_core_services.oci_services.services[0]["id"]
  }

  vcn_id = oci_core_vcn.openshift_vcn.id

  display_name = "ServiceGateway"
}

resource "oci_core_route_table" "public_routes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  display_name   = "public"

  route_rules {
    destination       = local.anywhere
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}

resource "oci_core_route_table" "private_routes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  display_name   = "private"

  route_rules {
    destination       = local.anywhere
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat_gateway.id
  }
  route_rules {
    destination       = data.oci_core_services.oci_services.services[0]["cidr_block"]
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  display_name   = "private"
  vcn_id         = oci_core_vcn.openshift_vcn.id

  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = local.all_protocols
  }
  egress_security_rules {
    destination = local.anywhere
    protocol    = local.all_protocols
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  display_name   = "public"
  vcn_id         = oci_core_vcn.openshift_vcn.id

  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = local.all_protocols
  }
  ingress_security_rules {
    source   = local.anywhere
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }
  egress_security_rules {
    destination = local.anywhere
    protocol    = local.all_protocols
  }
}

resource "oci_core_subnet" "private" {
  cidr_block     = var.private_cidr
  display_name   = "private"
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  route_table_id = oci_core_route_table.private_routes.id

  security_list_ids = [
    oci_core_security_list.private.id,
  ]

  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "public" {
  cidr_block     = var.public_cidr
  display_name   = "public"
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  route_table_id = oci_core_route_table.public_routes.id

  security_list_ids = [
    oci_core_security_list.public.id,
  ]

  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_network_security_group" "cluster_lb_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  display_name   = "cluster-lb-nsg"
}

resource "oci_core_network_security_group_security_rule" "cluster_lb_nsg_rule_1" {
  network_security_group_id = oci_core_network_security_group.cluster_lb_nsg.id
  direction                 = "EGRESS"
  destination               = local.anywhere
  protocol                  = local.all_protocols
}

resource "oci_core_network_security_group_security_rule" "cluster_lb_nsg_rule_2" {
  network_security_group_id = oci_core_network_security_group.cluster_lb_nsg.id
  protocol                  = "6"
  direction                 = "INGRESS"
  source                    = local.anywhere
  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "cluster_lb_nsg_rule_3" {
  network_security_group_id = oci_core_network_security_group.cluster_lb_nsg.id
  protocol                  = "6"
  direction                 = "INGRESS"
  source                    = local.anywhere
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "cluster_lb_nsg_rule_4" {
  network_security_group_id = oci_core_network_security_group.cluster_lb_nsg.id
  protocol                  = "6"
  direction                 = "INGRESS"
  source                    = local.anywhere
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "cluster_lb_nsg_rule_5" {
  network_security_group_id = oci_core_network_security_group.cluster_lb_nsg.id
  protocol                  = local.all_protocols
  direction                 = "INGRESS"
  source                    = var.vcn_cidr
}

resource "oci_core_network_security_group" "cluster_controlplane_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  display_name   = "cluster-controlplane-nsg"
}

resource "oci_core_network_security_group_security_rule" "cluster_controlplane_nsg_rule_1" {
  network_security_group_id = oci_core_network_security_group.cluster_controlplane_nsg.id
  direction                 = "EGRESS"
  destination               = local.anywhere
  protocol                  = local.all_protocols
}

resource "oci_core_network_security_group_security_rule" "cluster_controlplane_nsg_2" {
  network_security_group_id = oci_core_network_security_group.cluster_controlplane_nsg.id
  protocol                  = local.all_protocols
  direction                 = "INGRESS"
  source                    = var.vcn_cidr
}

resource "oci_core_network_security_group" "cluster_compute_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.openshift_vcn.id
  display_name   = "cluster-compute-nsg"
}

resource "oci_core_network_security_group_security_rule" "cluster_compute_nsg_rule_1" {
  network_security_group_id = oci_core_network_security_group.cluster_compute_nsg.id
  direction                 = "EGRESS"
  destination               = local.anywhere
  protocol                  = local.all_protocols
}

resource "oci_core_network_security_group_security_rule" "cluster_compute_nsg_2" {
  network_security_group_id = oci_core_network_security_group.cluster_compute_nsg.id
  protocol                  = local.all_protocols
  direction                 = "INGRESS"
  source                    = var.vcn_cidr
}

resource "oci_load_balancer_load_balancer" "openshift_api_int_lb" {
  compartment_id             = var.compartment_ocid
  display_name               = "${var.cluster_name}-openshift_api_int_lb"
  shape                      = "flexible"
  subnet_ids                 = [oci_core_subnet.private.id]
  is_private                 = true
  network_security_group_ids = [oci_core_network_security_group.cluster_lb_nsg.id]

  shape_details {
    maximum_bandwidth_in_mbps = var.load_balancer_shape_details_maximum_bandwidth_in_mbps
    minimum_bandwidth_in_mbps = var.load_balancer_shape_details_minimum_bandwidth_in_mbps
  }
}

resource "oci_load_balancer_load_balancer" "openshift_api_apps_lb" {
  compartment_id             = var.compartment_ocid
  display_name               = "${var.cluster_name}-openshift_api_apps_lb"
  shape                      = "flexible"
  subnet_ids                 = var.enable_private_dns ? [oci_core_subnet.private.id] : [oci_core_subnet.public.id]
  is_private                 = var.enable_private_dns ? true : false
  network_security_group_ids = [oci_core_network_security_group.cluster_lb_nsg.id]

  shape_details {
    maximum_bandwidth_in_mbps = var.load_balancer_shape_details_maximum_bandwidth_in_mbps
    minimum_bandwidth_in_mbps = var.load_balancer_shape_details_minimum_bandwidth_in_mbps
  }
}

resource "oci_load_balancer_backend_set" "openshift_cluster_api_backend_external" {
  health_checker {
    protocol          = "HTTP"
    port              = 6080
    return_code       = 200
    url_path          = "/readyz"
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
  name             = "openshift_cluster_api_backend"
  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  policy           = "LEAST_CONNECTIONS"
}

resource "oci_load_balancer_listener" "openshift_cluster_api_listener_external" {
  default_backend_set_name = oci_load_balancer_backend_set.openshift_cluster_api_backend_external.name
  name                     = "openshift_cluster_api_listener"
  load_balancer_id         = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  port                     = 6443
  protocol                 = "TCP"
}

resource "oci_load_balancer_backend_set" "openshift_cluster_ingress_http_backend" {
  health_checker {
    protocol          = "TCP"
    port              = 80
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
  name             = "openshift_cluster_ingress_http"
  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  policy           = "LEAST_CONNECTIONS"
}

resource "oci_load_balancer_listener" "openshift_cluster_ingress_http" {
  default_backend_set_name = oci_load_balancer_backend_set.openshift_cluster_ingress_http_backend.name
  name                     = "openshift_cluster_ingress_http"
  load_balancer_id         = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  port                     = 80
  protocol                 = "TCP"
}

resource "oci_load_balancer_backend_set" "openshift_cluster_ingress_https_backend" {
  health_checker {
    protocol          = "TCP"
    port              = 443
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
  name             = "openshift_cluster_ingress_https"
  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  policy           = "LEAST_CONNECTIONS"
}

resource "oci_load_balancer_listener" "openshift_cluster_ingress_https" {
  default_backend_set_name = oci_load_balancer_backend_set.openshift_cluster_ingress_https_backend.name
  name                     = "openshift_cluster_ingress_https"
  load_balancer_id         = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  port                     = 443
  protocol                 = "TCP"
}

resource "oci_load_balancer_backend_set" "openshift_cluster_api_backend_internal" {
  health_checker {
    protocol          = "HTTP"
    port              = 6080
    return_code       = 200
    url_path          = "/readyz"
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
  name             = "openshift_cluster_api_backend"
  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  policy           = "LEAST_CONNECTIONS"
}

resource "oci_load_balancer_listener" "openshift_cluster_api_listener_internal" {
  default_backend_set_name = oci_load_balancer_backend_set.openshift_cluster_api_backend_internal.name
  name                     = "openshift_cluster_api_listener"
  load_balancer_id         = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  port                     = 6443
  protocol                 = "TCP"
}

resource "oci_load_balancer_backend_set" "openshift_cluster_infra-mcs_backend" {
  health_checker {
    protocol          = "HTTP"
    port              = 22624
    return_code       = 200
    url_path          = "/healthz"
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
  name             = "openshift_cluster_infra-mcs"
  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  policy           = "LEAST_CONNECTIONS"
}

resource "oci_load_balancer_listener" "openshift_cluster_infra-mcs" {
  default_backend_set_name = oci_load_balancer_backend_set.openshift_cluster_infra-mcs_backend.name
  name                     = "openshift_cluster_infra-mcs"
  load_balancer_id         = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  port                     = 22623
  protocol                 = "TCP"
}

resource "oci_load_balancer_backend_set" "openshift_cluster_infra-mcs_backend_2" {
  health_checker {
    protocol          = "HTTP"
    port              = 22624
    return_code       = 200
    url_path          = "/healthz"
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
  name             = "openshift_cluster_infra-mcs_2"
  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  policy           = "LEAST_CONNECTIONS"
}

resource "oci_load_balancer_listener" "openshift_cluster_infra-mcs_2" {
  default_backend_set_name = oci_load_balancer_backend_set.openshift_cluster_infra-mcs_backend_2.name
  name                     = "openshift_cluster_infra-mcs_2"
  load_balancer_id         = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  port                     = 22624
  protocol                 = "TCP"
}


resource "oci_identity_policy" "openshift_control_plane_nodes" {
  compartment_id = var.compartment_ocid
  description    = "OpenShift control_plane nodes instance principal"
  name           = "${var.cluster_name}_control_plane_nodes"
  statements = [
    "Allow dynamic-group ${var.dynamic_group_name} to manage volume-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage instance-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage security-lists in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${var.dynamic_group_name} to use virtual-network-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage load-balancers in compartment id ${var.compartment_ocid}",
  ]
  provider = oci.home
}

resource "oci_dns_zone" "openshift" {
  compartment_id = var.compartment_ocid
  name           = var.zone_dns
  scope          = var.enable_private_dns ? "PRIVATE" : null
  view_id        = var.enable_private_dns ? data.oci_dns_resolver.dns_resolver.default_view_id : null
  zone_type      = "PRIMARY"
  depends_on     = [oci_core_subnet.private]
}

resource "oci_dns_rrset" "openshift_api" {
  domain = "api.${var.cluster_name}.${var.zone_dns}"
  items {
    domain = "api.${var.cluster_name}.${var.zone_dns}"
    rdata  = oci_load_balancer_load_balancer.openshift_api_apps_lb.ip_address_details[0].ip_address
    rtype  = "A"
    ttl    = "3600"
  }
  rtype           = "A"
  zone_name_or_id = oci_dns_zone.openshift.id
}

resource "oci_dns_rrset" "openshift_apps" {
  domain = "*.apps.${var.cluster_name}.${var.zone_dns}"
  items {
    domain = "*.apps.${var.cluster_name}.${var.zone_dns}"
    rdata  = oci_load_balancer_load_balancer.openshift_api_apps_lb.ip_address_details[0].ip_address
    rtype  = "A"
    ttl    = "3600"
  }
  rtype           = "A"
  zone_name_or_id = oci_dns_zone.openshift.id
}

resource "oci_dns_rrset" "openshift_api_int" {
  domain = "api-int.${var.cluster_name}.${var.zone_dns}"
  items {
    domain = "api-int.${var.cluster_name}.${var.zone_dns}"
    rdata  = oci_load_balancer_load_balancer.openshift_api_int_lb.ip_address_details[0].ip_address
    rtype  = "A"
    ttl    = "3600"
  }
  rtype           = "A"
  zone_name_or_id = oci_dns_zone.openshift.id
}

resource "time_sleep" "wait_180_seconds" {
  depends_on      = [oci_core_vcn.openshift_vcn]
  create_duration = "180s"
}

data "oci_core_vcn_dns_resolver_association" "dns_resolver_association" {
  vcn_id     = oci_core_vcn.openshift_vcn.id
  depends_on = [time_sleep.wait_180_seconds]
}

data "oci_dns_resolver" "dns_resolver" {
  resolver_id = data.oci_core_vcn_dns_resolver_association.dns_resolver_association.dns_resolver_id
  scope       = "PRIVATE"
}


## インスタンス関連
locals {
  total_instance_count = var.compute_count + var.control_plane_count
  shapes_with_indices = [
    for i in range(local.total_instance_count) : {
      index = i
      shape = var.shapes[i % length(var.shapes)]
    }
  ]
}

resource "oci_core_instance" "control_plane_node" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => local.shapes_with_indices[idx]
  }

  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.availability_domain.name
  display_name        = "${var.cluster_name}-control-plane-${each.key}"

  shape = each.value.shape
  shape_config {
    memory_in_gbs = var.control_plane_memory
    ocpus         = var.control_plane_ocpu
  }

  create_vnic_details {
    assign_private_dns_record = "true"
    assign_public_ip          = "false"
    nsg_ids = [
      oci_core_network_security_group.cluster_controlplane_nsg.id,
    ]
    subnet_id = oci_core_subnet.private.id
  }

  source_details {
    boot_volume_size_in_gbs = var.control_plane_boot_size
    boot_volume_vpus_per_gb = var.control_plane_boot_volume_vpus_per_gb
    source_id               = oci_core_image.openshift_image[0].id
    source_type             = "image"
  }

}


resource "oci_core_instance" "compute_node" {
  for_each = {
    for idx in range(var.compute_count) : idx => local.shapes_with_indices[idx + var.control_plane_count]
  }

  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.availability_domain.name
  display_name        = "${var.cluster_name}-compute-${each.key}"

  shape = each.value.shape
  shape_config {
    memory_in_gbs = var.compute_memory
    ocpus         = var.compute_ocpu
  }

  create_vnic_details {
    assign_private_dns_record = "true"
    assign_public_ip          = "false"
    nsg_ids = [
      oci_core_network_security_group.cluster_compute_nsg.id,
    ]
    subnet_id = oci_core_subnet.private.id
  }

  source_details {
    boot_volume_size_in_gbs = var.compute_boot_size
    boot_volume_vpus_per_gb = var.compute_boot_volume_vpus_per_gb
    source_id               = oci_core_image.openshift_image[0].id
    source_type             = "image"
  }

}

# バックエンド定義

resource "oci_load_balancer_backend" "control_plane_api_backend_external" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => oci_core_instance.control_plane_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_api_backend_external.name
  ip_address       = each.value.private_ip
  port             = 6443
  weight           = 1
}

resource "oci_load_balancer_backend" "control_plane_ingress_https_backend" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => oci_core_instance.control_plane_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_ingress_https_backend.name
  ip_address       = each.value.private_ip
  port             = 443
  weight           = 1
}

resource "oci_load_balancer_backend" "control_plane_ingress_http_backend" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => oci_core_instance.control_plane_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_ingress_http_backend.name
  ip_address       = each.value.private_ip
  port             = 80
  weight           = 1
}

resource "oci_load_balancer_backend" "control_plane_api_backend_internal" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => oci_core_instance.control_plane_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_api_backend_internal.name
  ip_address       = each.value.private_ip
  port             = 6443
  weight           = 1
}

resource "oci_load_balancer_backend" "control_plane_infra_mcs_backend" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => oci_core_instance.control_plane_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_infra-mcs_backend.name
  ip_address       = each.value.private_ip
  port             = 22623
  weight           = 1
}

resource "oci_load_balancer_backend" "control_plane_infra_mcs_backend_2" {
  for_each = {
    for idx in range(var.control_plane_count) : idx => oci_core_instance.control_plane_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_int_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_infra-mcs_backend_2.name
  ip_address       = each.value.private_ip
  port             = 22624
  weight           = 1
}

resource "oci_load_balancer_backend" "compute_ingress_https_backend" {
  for_each = {
    for idx in range(var.compute_count) : idx => oci_core_instance.compute_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_ingress_https_backend.name
  ip_address       = each.value.private_ip
  port             = 443
  weight           = 1
}

resource "oci_load_balancer_backend" "compute_ingress_http_backend" {
  for_each = {
    for idx in range(var.compute_count) : idx => oci_core_instance.compute_node[idx]
  }

  load_balancer_id = oci_load_balancer_load_balancer.openshift_api_apps_lb.id
  backendset_name  = oci_load_balancer_backend_set.openshift_cluster_ingress_http_backend.name
  ip_address       = each.value.private_ip
  port             = 80
  weight           = 1
}



output "open_shift_api_int_lb_addr" {
  value = oci_load_balancer_load_balancer.openshift_api_int_lb.ip_address_details[0].ip_address
}

output "open_shift_api_apps_lb_addr" {
  value = oci_load_balancer_load_balancer.openshift_api_apps_lb.ip_address_details[0].ip_address
}

output "oci_ccm_config" {
  value = <<OCICCMCONFIG
useInstancePrincipals: true
compartment: ${var.compartment_ocid}
vcn: ${oci_core_vcn.openshift_vcn.id}
loadBalancer:
  subnet1: ${var.enable_private_dns ? oci_core_subnet.private.id : oci_core_subnet.public.id}
  securityListManagementMode: Frontend
  securityLists:
    ${var.enable_private_dns ? oci_core_subnet.private.id : oci_core_subnet.public.id}: ${var.enable_private_dns ? oci_core_security_list.private.id : oci_core_security_list.public.id}
rateLimiter:
  rateLimitQPSRead: 20.0
  rateLimitBucketRead: 5
  rateLimitQPSWrite: 20.0
  rateLimitBucketWrite: 5
  OCICCMCONFIG
}
