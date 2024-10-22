## This configuration was generated by terraform-provider-oci

resource oci_devops_project export_oci-devops-handson {
  compartment_id = var.compartment_ocid
  description = ""
  freeform_tags = {
  }
  name = "oci-devops-handson"
  notification_config {
    topic_id = oci_ons_notification_topic.export_oci-devops-handson_1.id
  }
}

resource oci_devops_project_repository_setting export_oci-devops-handson_project_repository_setting {
  approval_rules {
  }
  merge_settings {
    allowed_merge_strategies = [
      "MERGE_COMMIT",
    ]
    default_merge_strategy = "MERGE_COMMIT"
  }
  project_id = oci_devops_project.export_oci-devops-handson.id
}

