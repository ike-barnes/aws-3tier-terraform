# ------------------------------------------------------------------
# Three subnet tiers in each availability zone:
#   public      - load balancer and NAT gateway only
#   private-app - app servers; outbound internet through NAT
#   private-db  - databases; no internet route at all
# ------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # { "us-east-1a" = 0, "us-east-1b" = 1 }. The number picks the CIDR.
  azs      = { for i, az in slice(data.aws_availability_zones.available.names, 0, var.az_count) : az => i }
  first_az = keys(local.azs)[0]
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

# 10.20.0.0/24, 10.20.1.0/24
resource "aws_subnet" "public" {
  for_each = local.azs

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value)

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

# 10.20.10.0/24, 10.20.11.0/24
resource "aws_subnet" "app" {
  for_each = local.azs

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, 10 + each.value)

  tags = { Name = "${var.name}-app-${each.key}", Tier = "private-app" }
}

# 10.20.20.0/24, 10.20.21.0/24
resource "aws_subnet" "db" {
  for_each = local.azs

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, 20 + each.value)

  tags = { Name = "${var.name}-db-${each.key}", Tier = "private-db" }
}

# One NAT gateway to keep lab costs down. Production uses one per AZ
# so losing an AZ doesn't cut every app server off from the internet.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[local.first_az].id
  tags          = { Name = var.name }

  depends_on = [aws_internet_gateway.this]
}

# ---------------- Route tables ----------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${var.name}-app" }
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app.id
}

# No routes beyond the VPC itself: the database tier can't reach,
# or be reached from, the internet.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-db" }
}

resource "aws_route_table_association" "db" {
  for_each       = aws_subnet.db
  subnet_id      = each.value.id
  route_table_id = aws_route_table.db.id
}
