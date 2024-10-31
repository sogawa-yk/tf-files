provider "oci" {
  region       = var.region
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
}

resource "null_resource" "example" {
  # OS情報の出力
  provisioner "local-exec" {
    command = "echo 'Hello, World!' > /tmp/hello_world.txt && uname -a > /tmp/os_info.txt && cat /tmp/os_info.txt"
  }
}
