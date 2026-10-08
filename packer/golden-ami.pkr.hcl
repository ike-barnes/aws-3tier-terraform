# ------------------------------------------------------------------
# Golden AMI: Amazon Linux 2023 (ARM/Graviton), fully patched, with
# the app's packages pre-installed and a CIS-aligned hardening
# baseline applied by Ansible. Servers launched from it boot ready,
# with no package downloads at startup.
# ------------------------------------------------------------------
packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  description = "Build instance. t4g.small avoids the micro capacity shortages seen in us-east-1."
  type        = string
  default     = "t4g.small"
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmm", timestamp())
}

source "amazon-ebs" "al2023" {
  region        = var.region
  instance_type = var.instance_type
  ami_name      = "three-tier-golden-${local.timestamp}"

  # Newest official Amazon Linux 2023 ARM image.
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-kernel-*-arm64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ssh_username                = "ec2-user"
  associate_public_ip_address = true

  # Packer's temporary security group allows SSH only from this
  # computer's public IP, and is deleted when the build finishes.
  temporary_security_group_source_public_ip = true

  # The build instance and every instance launched from the AMI
  # require IMDSv2.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  imds_support = "v2.0"

  # Encrypted root volume in the image.
  encrypt_boot = true

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name         = "three-tier-golden"
    Project      = "aws-3tier-terraform"
    BuiltBy      = "packer"
    BaseAMI      = "{{ .SourceAMIName }}"
    Hardening    = "CIS-aligned baseline (ansible/harden.yml)"
    Architecture = "arm64"
  }

  run_tags = {
    Name = "packer-build-three-tier-golden"
  }
}

build {
  sources = ["source.amazon-ebs.al2023"]

  # Install Ansible in a throwaway virtual environment on the build
  # instance, so it never ends up in the finished image.
  provisioner "shell" {
    inline = [
      "sudo python3 -m venv /opt/ansible",
      "sudo /opt/ansible/bin/pip install --quiet ansible-core",
    ]
  }

  # Run the hardening playbook locally on the build instance.
  provisioner "ansible-local" {
    playbook_file   = "${path.root}/../ansible/harden.yml"
    command         = "sudo /opt/ansible/bin/ansible-playbook"
    extra_arguments = ["-e", "ansible_python_interpreter=/usr/bin/python3"]
  }

  # Remove build tools and caches before the image is captured.
  provisioner "shell" {
    inline = [
      "sudo rm -rf /opt/ansible",
      "sudo dnf clean all",
      "sudo rm -rf /var/cache/dnf",
    ]
  }

  # Writes the new AMI ID to packer/manifest.json.
  post-processor "manifest" {
    output = "${path.root}/manifest.json"
  }
}
