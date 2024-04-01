disable_mlock = true

hcp_boundary_cluster_id = "${cluster_id}"

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}
        
worker {
  public_addr = "${public_addr}"
  auth_storage_path = "/etc/boundary-worker-data"
  controller_generated_activation_token = "${boundary_worker_activation_token}"

  tags {
    %{ for key, value in worker_tags }
    ${key} = ${jsonencode(value)}
    %{ endfor ~}
  }
}