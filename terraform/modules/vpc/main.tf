variable "ami_id" {
  type        = string
  description = "Optional explicit AMI ID for NAT instance. If provided, skips ec2:DescribeImages query."
  default     = ""
}

data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : try(data.aws_ami.amazon_linux_2023[0].id, "")
}

# 1. VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# 2. Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# 3. Public Subnets (across 2 AZs for ALB & NAT)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# 4. Private Application Subnets (across 2 AZs for EC2 ASG)
resource "aws_subnet" "private_app" {
  count             = length(var.private_app_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-subnet-${count.index + 1}"
    Type = "Private-App"
  })
}

# 5. Private Database Subnets (across 2 AZs for RDS MySQL)
resource "aws_subnet" "private_db" {
  count             = length(var.private_db_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db-subnet-${count.index + 1}"
    Type = "Private-DB"
  })
}

# 6. Route Table - Public (Routes to Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -------------------------------------------------------------
# NAT Solution (Free-Tier NAT Instance OR AWS Managed NAT Gateway)
# -------------------------------------------------------------

# Security Group for Free-Tier NAT Instance
resource "aws_security_group" "nat_instance" {
  count       = var.enable_nat_instance && !var.enable_nat_gateway ? 1 : 0
  name        = "${var.name_prefix}-nat-instance-sg"
  description = "Security group for Free Tier NAT instance"
  vpc_id      = aws_vpc.this.id

  # Allow all outbound-forwarded traffic from the VPC
  ingress {
    description = "Allow all inbound traffic from VPC for NAT routing"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-instance-sg"
  })
}

# Free-Tier NAT Instance (costs $0.00 in Free Tier)
resource "aws_instance" "nat" {
  count                  = var.enable_nat_instance && !var.enable_nat_gateway ? 1 : 0
  ami                    = local.ami_id
  instance_type          = var.nat_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nat_instance[0].id]
  source_dest_check      = false # Required for NAT routing

  user_data = <<-EOF
              #!/bin/bash
              set -xe

              # Enable IP forwarding
              sysctl -w net.ipv4.ip_forward=1
              echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf

              # Determine default interface
              DEFAULT_IFACE=$(ip -4 route list 0/0 | awk '{print $5; exit}')

              # Configure iptables NAT and FORWARD rules
              iptables -F FORWARD
              iptables -P FORWARD ACCEPT
              iptables -t nat -F POSTROUTING
              iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE

              # Create persistent systemd unit for reboots
              cat <<'UNIT' > /etc/systemd/system/nat-setup.service
              [Unit]
              Description=NAT Routing Setup
              After=network.target

              [Service]
              Type=oneshot
              ExecStart=/bin/bash -c "sysctl -w net.ipv4.ip_forward=1 && DEFAULT_IFACE=\$(ip -4 route list 0/0 | awk '{print \$5; exit}') && iptables -P FORWARD ACCEPT && iptables -t nat -A POSTROUTING -o \$DEFAULT_IFACE -j MASQUERADE"
              RemainAfterExit=true

              [Install]
              WantedBy=multi-user.target
              UNIT

              systemctl daemon-reload
              systemctl enable --now nat-setup.service
              EOF

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-free-tier-nat-instance"
  })
}

# Optional AWS Managed NAT Gateway (Paid resource, disabled by default)
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-gw"
  })

  depends_on = [aws_internet_gateway.this]
}

# 7. Route Table - Private App (Routes to NAT Instance or NAT Gateway)
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-rt"
  })
}

resource "aws_route" "private_app_nat_instance" {
  count                  = var.enable_nat_instance && !var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route" "private_app_nat_gw" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private_app" {
  count          = length(aws_subnet.private_app)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# 8. Route Table - Private Database (Strict Isolation, No Internet Route)
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db-rt"
  })
}

resource "aws_route_table_association" "private_db" {
  count          = length(aws_subnet.private_db)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}
