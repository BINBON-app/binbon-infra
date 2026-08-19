resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(var.tags, {
    Name = var.name
  })
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}
resource "aws_subnet" "public" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.cidr_block, 4, index(var.azs, each.value))
  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.value}", Tier = "public"
  })
}
resource "aws_subnet" "app" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.cidr_block, 4, index(var.azs, each.value) + length(var.azs))
  tags = merge(var.tags, {
    Name = "${var.name}-app-${each.value}", Tier = "app-private"
  })
}
resource "aws_subnet" "data" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.cidr_block, 4, index(var.azs, each.value) + 2 * length(var.azs))
  tags = merge(var.tags, {
    Name = "${var.name}-data-${each.value}", Tier = "data-private"
  })
}
resource "aws_eip" "nat" {
  for_each = toset(var.single_nat_gateway ? [var.azs[0]] : var.azs)
  domain   = "vpc"
  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.value}"
  })
}
resource "aws_nat_gateway" "this" {
  for_each      = aws_eip.nat
  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_internet_gateway.this]
  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.key}"
  })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.name}-public"
  })
}
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  for_each = toset(var.azs)
  vpc_id   = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.value}"
  })
}
resource "aws_route" "private_nat" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? var.azs[0] : each.key].id
}
resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
resource "aws_route_table_association" "data" {
  for_each       = aws_subnet.data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = 30
  tags              = var.tags
}
resource "aws_iam_role" "flow_logs" {
  name = "${var.name}-vpc-flow-logs"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com"
    }, Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
resource "aws_iam_role_policy" "flow_logs" {
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"], Resource = "*"
    }]
  })
}
resource "aws_flow_log" "this" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id
}
