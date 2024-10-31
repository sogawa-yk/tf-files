provider "oci" {
  region       = var.region
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
}
resource "null_resource" "example" {
  # yumコマンドの有無を確認
  provisioner "local-exec" {
    command = "echo 'Hello, World!' > /tmp/hello_world.txt && command -v yum > /tmp/yum_check.txt && cat /tmp/yum_check.txt || echo 'yum command not found'"
  }
}
