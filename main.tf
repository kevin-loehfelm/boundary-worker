locals {
  boundary_service_config = <<-BOUNDARY_SERVICE_CONFIG
    [Service]
    ProtectSystem=off
    ExecStart=
    ExecStart=/usr/bin/boundary server -config=/etc/boundary.d/boundary-worker.hcl
    BOUNDARY_SERVICE_CONFIG
  cloudinit_write_files = [
    {
      content     = file("${path.root}/files/gpg_pubkeys/hashicorp-archive-keyring.gpg")
      owner       = "root:root"
      path        = "/tmp/hashicorp-archive-keyring.gpg"
      permissions = "0644"
    },
    {
      content     = <<-APT_NO_PROMPT_CONFIG
          Dpkg::Options {
            "--force-confdef";
            "--force-confold";
          }
          APT_NO_PROMPT_CONFIG
      owner       = "root:root"
      path        = "/etc/apt/apt.conf.d/no-update-prompt"
      permissions = "0644"
    },
    {
      content     = local.boundary_service_config
      owner       = "root:root"
      path        = "/etc/systemd/system/boundary.service.d/10-execstart.conf"
      permissions = "0644"
    }
  ]
  cloudinit_runcmd = [
    ["systemctl", "disable", "--now", "unattended-upgrades.service", "apt-daily-upgrade.service", "apt-daily-upgrade.timer"],
    ["apt", "install", "-y", "software-properties-common"],
    ["apt-add-repository", "universe"],
    ["sh", "-c", "gpg --dearmor < /tmp/hashicorp-archive-keyring.gpg > /usr/share/keyrings/hashicorp-archive-keyring.gpg"],
    ["sh", "-c", "echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" > /etc/apt/sources.list.d/hashicorp.list"],
    ["apt", "update"],
    ["sh", "-c", "UCF_FORCE_CONFFOLD=true apt upgrade -y"],
    ["mkdir", "/etc/boundary-worker-data"],
    ["apt", "install", "-y", "bind9-dnsutils", "jq", "curl", "unzip", "docker-compose"],
    ["apt", "install", "-y", "boundary-enterprise"],
    ["chown", "boundary:boundary", "/etc/boundary-worker-data"],
    ["systemctl", "enable", "--now", "boundary"],
    ["systemctl", "enable", "--now", "apt-daily-upgrade.service", "apt-daily-upgrade.timer", "docker"]
  ]
}

# Retrieve latest Ubuntu AMI ID for given region
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

## Ingress
data "aws_subnet" "ingress" {
  count = length(var.aws_ingress_subnet_ids)
  id    = var.aws_ingress_subnet_ids[count.index]
}

resource "aws_security_group" "ingress" {
  count  = var.ingress_worker_count
  name   = "${var.prefix}-ingress-worker-${count.index}-sg"
  vpc_id = data.aws_subnet.ingress[count.index].vpc_id

  ingress {
    description = "ingress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "ingress" {
  count           = var.ingress_worker_count
  subnet_id       = var.aws_ingress_subnet_ids[count.index]
  security_groups = [aws_security_group.ingress[count.index].id]
}

resource "aws_eip" "ingress" {
  count             = var.ingress_worker_count
  domain            = "vpc"
  network_interface = aws_network_interface.ingress[count.index].id
}

data "cloudinit_config" "ingress" {
  count         = var.ingress_worker_count
  gzip          = false
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = yamlencode(
      {
        write_files = concat(local.cloudinit_write_files, [
          {
            content = templatefile("${path.module}/ingress-worker.tpl", {
              cluster_id                       = split(".", split("//", var.boundary_cluster_url)[1])[0]
              public_addr                      = aws_eip.ingress[count.index].public_dns
              boundary_worker_activation_token = boundary_worker.ingress[count.index].controller_generated_activation_token
              worker_tags = {
                type = ["ingress", "upstream"]
                name = ["${var.prefix}-ingress-worker-${count.index}"]
              }
            })
            owner       = "root:root"
            path        = "/etc/boundary.d/boundary-worker.hcl"
            permissions = "0644"
          }
        ])
        runcmd = local.cloudinit_runcmd
      }
    )
  }
}

resource "aws_instance" "ingress" {
  count = var.ingress_worker_count
  lifecycle {
    ignore_changes = [user_data_base64]
  }
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = var.aws_worker_instance_type
  key_name                    = "hashicorp-mac-2"
  user_data_replace_on_change = false
  user_data_base64            = data.cloudinit_config.ingress[count.index].rendered

  network_interface {
    network_interface_id = aws_network_interface.ingress[count.index].id
    device_index         = 0
  }

  tags = {
    Name = "${var.prefix}-ingress-worker-${count.index}"
  }
}

resource "boundary_worker" "ingress" {
  count    = var.ingress_worker_count
  scope_id = "global"
  name     = "${var.prefix}-ingress-worker-${count.index}"
}

## Egress
data "aws_subnet" "egress" {
  count = length(var.aws_egress1_subnet_ids)
  id    = var.aws_egress1_subnet_ids[count.index]
}

resource "aws_security_group" "egress" {
  count  = var.egress_worker_count
  name   = "${var.prefix}-egress-worker-${count.index}-sg"
  vpc_id = data.aws_subnet.egress[count.index].vpc_id

  ingress {
    description = "ingress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "egress" {
  count           = var.egress_worker_count
  subnet_id       = var.aws_egress1_subnet_ids[count.index]
  security_groups = [aws_security_group.egress[count.index].id]
}

data "cloudinit_config" "egress" {
  count         = var.egress_worker_count
  gzip          = false
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = yamlencode(
      {
        write_files = concat(local.cloudinit_write_files, [
          {
            content = templatefile("${path.module}/egress-worker.tpl", {
              public_addr                      = aws_network_interface.egress[count.index].private_dns_name
              boundary_worker_activation_token = boundary_worker.egress[count.index].controller_generated_activation_token
              upstream_addrs                   = formatlist("%s:9202", aws_eip.ingress.*.public_dns)
              worker_tags = {
                type = ["egress", "downstream"]
                name = ["${var.prefix}-egress-worker-${count.index}"]
              }
            })
            owner       = "root:root"
            path        = "/etc/boundary.d/boundary-worker.hcl"
            permissions = "0644"
          }
        ])
        runcmd = local.cloudinit_runcmd
      }
    )
  }
}

resource "aws_instance" "egress" {
  count = var.egress_worker_count
  lifecycle {
    ignore_changes = [user_data_base64]
  }
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = var.aws_worker_instance_type
  key_name                    = "hashicorp-mac-2"
  user_data_replace_on_change = false
  user_data_base64            = data.cloudinit_config.egress[count.index].rendered

  network_interface {
    network_interface_id = aws_network_interface.egress[count.index].id
    device_index         = 0
  }

  tags = {
    Name = "${var.prefix}-egress-worker-${count.index}"
  }
}

resource "boundary_worker" "egress" {
  count    = var.egress_worker_count
  scope_id = "global"
  name     = "${var.prefix}-egress-worker-${count.index}"
}