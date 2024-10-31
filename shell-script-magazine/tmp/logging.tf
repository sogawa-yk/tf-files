## This configuration was generated by terraform-provider-oci

resource oci_logging_log_group export_oci_devops_hadson_all {
  compartment_id = var.compartment_ocid
  #description = <<Optional value not found in discovery>>
  display_name = "oci_devops_hadson_all"
  freeform_tags = {
  }
}

resource oci_logging_log export_oci_devops_handson_all {
  configuration {
    compartment_id = var.compartment_ocid
    source {
      category = "all"
      parameters = {
      }
      resource    = oci_devops_project.export_oci-devops-handson.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
  display_name = "oci_devops_handson_all"
  freeform_tags = {
  }
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.export_oci_devops_hadson_all.id
  log_type           = "SERVICE"
  retention_duration = "30"
}
