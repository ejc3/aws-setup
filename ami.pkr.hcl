packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-1"
}

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

source "amazon-ebs" "buckman" {
  ami_name      = "buckman-base-{{timestamp}}"
  instance_type = var.instance_type
  region        = var.region

  # Latest Amazon Linux 2023 ARM64
  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-arm64"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ssh_username = "ec2-user"

  tags = {
    Name        = "buckman-base"
    Environment = "production"
    ManagedBy   = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.buckman"]

  # System updates and basic tools
  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y git make python3 python3-pip vim tmux jq unzip tar zstd dnf-plugins-core wget",
    ]
  }

  # Install Podman from Rocky Linux 9 (ARM64)
  provisioner "shell" {
    inline = [
      "echo 'Installing Podman from Rocky Linux 9 repository...'",
      "sudo dnf install -y curl --allowerasing",
      "sudo dnf config-manager --add-repo=https://download.rockylinux.org/pub/rocky/9/AppStream/aarch64/os/",
      "sudo rpm --import https://download.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 || true",
      "sudo dnf install -y podman --nogpgcheck --skip-broken --repofrompath=rocky9,https://download.rockylinux.org/pub/rocky/9/AppStream/aarch64/os/",
      "podman --version",
    ]
  }

  # Install skopeo for registry inspection
  provisioner "shell" {
    inline = [
      "echo 'Installing skopeo...'",
      "sudo dnf install -y skopeo --nogpgcheck --repofrompath=rocky9,https://download.rockylinux.org/pub/rocky/9/AppStream/aarch64/os/",
      "skopeo --version",
    ]
  }


  # Configure Podman for rootless operation
  provisioner "shell" {
    inline = [
      "sudo systemctl enable --now podman.socket",
      "sudo -u ec2-user podman system migrate || true",
    ]
  }

  # Clean up
  provisioner "shell" {
    inline = [
      "sudo dnf clean all",
      "sudo rm -rf /var/cache/dnf/*",
      "sudo rm -rf /tmp/*",
    ]
  }
}
