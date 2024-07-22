region = "ap-seoul-1"

zone_dns = "yusogawa.com" # RedHatのコンソールで設定したBase domain

control_plane_count = 3


control_plane_ocpu = 2

control_plane_memory = 32

control_plane_boot_size = 512 # 1024

control_plane_boot_volume_vpus_per_gb = 90

compute_count = 3

compute_ocpu = 1

compute_memory = 16

compute_boot_size = 100

compute_boot_volume_vpus_per_gb = 30

load_balancer_shape_details_maximum_bandwidth_in_mbps = 500

load_balancer_shape_details_minimum_bandwidth_in_mbps = 10

tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaa3mb7wrcy2ls3u3jsy2soq5ck3lc3q4mczitpdaymbuazc5tkguca"

compartment_ocid = "ocid1.compartment.oc1..aaaaaaaanxm4oucgt5pkgd7sw2vouvckvvxan7ca2lirowaao7krnzlkdkhq"

cluster_name = "demo"

vcn_cidr = "10.0.0.0/16"

vcn_dns_label = "openshiftvcn"

private_cidr = "10.0.16.0/20"

public_cidr = "10.0.0.0/20"

openshift_image_source_uri = "https://objectstorage.ap-seoul-1.oraclecloud.com/p/evVdDbVV0VRkAx1psRAus9BiodLXK1wN0IM-J_dX9oXqz2pA4T8EfEWjZDJqrA0G/n/orasejapan/b/forOpenShift/o/39847e55-da43-4c16-9e70-2c67d163cbac-discovery.iso"

enable_private_dns = false

dynamic_group_name = "member-yuki.sogawa_dynamic_group"

shapes = ["VM.Standard3.Flex", "VM.Standard.E3.Flex", "VM.Standard.E4.Flex"]

