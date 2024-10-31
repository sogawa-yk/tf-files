provider "oci" {
  region       = var.region
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
}
resource "null_resource" "example" {
  # yumを使ってmysqlクライアントをインストールし、ログを表示
  provisioner "local-exec" {
    command = <<EOT
      if command -v yum > /dev/null 2>&1; then
        echo 'yum is available, proceeding with mysql installation'
        sudo yum install -y mysql > /tmp/mysql_install.log 2>&1
        echo 'Installation log:'
        cat /tmp/mysql_install.log
      else
        echo 'yum is not available, skipping mysql installation'
      fi
    EOT
  }
}
