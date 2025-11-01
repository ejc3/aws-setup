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

  # Install Buck2
  provisioner "shell" {
    inline = [
      "echo 'Installing Buck2...'",
      "curl -sSL 'https://github.com/facebook/buck2/releases/download/latest/buck2-aarch64-unknown-linux-musl.zst' -o /tmp/buck2.zst",
      "zstd -d /tmp/buck2.zst -o /tmp/buck2",
      "chmod +x /tmp/buck2",
      "sudo mv /tmp/buck2 /usr/local/bin/buck2",
      "rm -f /tmp/buck2.zst",
      "buck2 --version",
    ]
  }

  # Install Terraform
  provisioner "shell" {
    inline = [
      "echo 'Installing Terraform...'",
      "wget -q https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_arm64.zip",
      "unzip -q terraform_1.9.0_linux_arm64.zip",
      "sudo mv terraform /usr/local/bin/",
      "rm terraform_1.9.0_linux_arm64.zip",
      "sudo chmod +x /usr/local/bin/terraform",
      "terraform --version",
    ]
  }

  # Configure Podman for rootless operation
  provisioner "shell" {
    inline = [
      "sudo systemctl enable --now podman.socket",
      "sudo -u ec2-user podman system migrate || true",
    ]
  }

  # Install version server
  provisioner "file" {
    source      = "scripts/version-server.py"
    destination = "/tmp/version-server.py"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/version-server.py /usr/local/bin/version-server.py",
      "sudo chmod +x /usr/local/bin/version-server.py",
    ]
  }

  # Create systemd service for version server
  provisioner "shell" {
    inline = [
      "sudo tee /etc/systemd/system/version-server.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Version Endpoint Server",
      "After=network-online.target",
      "Wants=network-online.target",
      "",
      "[Service]",
      "Type=simple",
      "ExecStart=/usr/bin/python3 /usr/local/bin/version-server.py",
      "Restart=always",
      "RestartSec=10",
      "User=ec2-user",
      "Group=ec2-user",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl enable version-server",
    ]
  }

  # Clone buckman repository and set up application
  provisioner "shell" {
    inline = [
      "echo 'Cloning buckman repository...'",
      "sudo -u ec2-user GIT_TERMINAL_PROMPT=0 git clone https://github.com/ejc3/buckman.git /home/ec2-user/buckman",
      "sudo -u ec2-user chmod -R 755 /home/ec2-user/buckman",
    ]
  }

  # Install Python dependencies for buckman
  provisioner "shell" {
    inline = [
      "echo 'Installing buckman Python dependencies...'",
      "cd /home/ec2-user/buckman",
      "sudo -u ec2-user python3 -m pip install --user -e .",
    ]
  }

  # Generate routes.json for external services
  provisioner "shell" {
    inline = [
      "echo 'Generating routes.json...'",
      "cd /home/ec2-user/buckman",
      "sudo -u ec2-user python3 -c 'import json; from pathlib import Path; external_file = Path(\"external_routes.json\"); data = json.loads(external_file.read_text()) if external_file.exists() else {\"services\": {}}; Path(\"infra/routes.json\").write_text(json.dumps(data, indent=2) + \"\\n\")'",
    ]
  }

  # Create buckman-proxy systemd service
  provisioner "shell" {
    inline = [
      "sudo tee /etc/systemd/system/buckman-proxy.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Buckman Proxy Infrastructure",
      "After=network.target podman.service",
      "Wants=podman.service",
      "",
      "[Service]",
      "Type=simple",
      "User=ec2-user",
      "WorkingDirectory=/home/ec2-user/buckman",
      "Environment=PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/ec2-user/.local/bin",
      "ExecStart=/usr/bin/python3 -m infra.runner --mode prod --no-routes-updater",
      "Restart=always",
      "RestartSec=10",
      "StandardOutput=journal",
      "StandardError=journal",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl enable buckman-proxy",
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
