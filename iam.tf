# IAM Role and Instance Profile for EC2 Instance
# This allows CloudWatch Agent and SSM to work automatically

# IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "${var.instance_name}-cloudwatch-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.instance_name}-cloudwatch-ssm-role"
    Environment = var.environment
    Purpose     = "CloudWatch Agent and SSM access"
  }
}

# Attach AWS Managed Policy for SSM
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach AWS Managed Policy for CloudWatch Agent
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
  name = "${var.instance_name}-cloudwatch-profile"
  role = aws_iam_role.ec2_cloudwatch_role.name

  tags = {
    Name        = "${var.instance_name}-cloudwatch-profile"
    Environment = var.environment
  }
}

# Associate IAM Instance Profile with existing EC2 Instance
resource "aws_ec2_instance_iam_instance_profile_association" "ec2_cloudwatch_association" {
  instance_id    = var.instance_id
  iam_instance_profile_id = aws_iam_instance_profile.ec2_cloudwatch_profile.id
}

