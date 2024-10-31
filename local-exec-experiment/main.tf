provider "oci" {
  region       = var.region
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
}

resource "null_resource" "example" {
  provisioner "local-exec" {
    command = "echo 'Hello, World!' > /tmp/hello_world.txt"
  }
}
