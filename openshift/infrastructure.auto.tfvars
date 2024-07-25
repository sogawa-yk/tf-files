region = "ap-seoul-1"

zone_dns = "ochacafe-openshift.net"

control_plane_count = 3

control_plane_shape = "VM.Standard.E4.Flex"

compute_count = 3

compute_shape = "VM.Standard.E4.Flex"

load_balancer_shape_details_maximum_bandwidth_in_mbps = 500

load_balancer_shape_details_minimum_bandwidth_in_mbps = 10

tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaa3mb7wrcy2ls3u3jsy2soq5ck3lc3q4mczitpdaymbuazc5tkguca"

cluster_name = "ocidemo"

vcn_cidr = "10.0.0.0/16"

vcn_dns_label = "openshiftvcn"

private_cidr = "10.0.16.0/20"

public_cidr = "10.0.0.0/20"

openshift_image_source_uri = "https://objectstorage.ca-toronto-1.oraclecloud.com/p/zO9PVhL-7MDpKYe-rlclbjamAr7KCMhbb7u4Ky0Fn31B_hLzXLIcChZ6PlIZbiyU/n/orasejapan/b/setup/o/231b0234-af6e-4c42-a137-fc75e8619bb6-discovery.iso"

enable_private_dns = false

dynamic_group_name = "project-ocha-rhos_dynamic_group"
