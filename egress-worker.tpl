disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}
        
worker {
  public_addr = "${public_addr}"
  initial_upstreams = ${jsonencode(upstream_addrs)}
  auth_storage_path = "/etc/boundary-worker-data"
  controller_generated_activation_token = "${boundary_worker_activation_token}"

  tags {
    %{ for key, value in worker_tags }
    ${key} = ${jsonencode(value)}
    %{ endfor ~}
  }
}