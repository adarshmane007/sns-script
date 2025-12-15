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

# Associate IAM Instance Profile with existing EC2 Instance using AWS CLI
# Note: This uses null_resource because aws_ec2_instance_iam_instance_profile_association
# may not be available in all AWS provider versions
# Requires AWS CLI to be installed where Terraform runs
resource "null_resource" "attach_iam_instance_profile" {
  triggers = {
    instance_id     = var.instance_id
    instance_profile_arn = aws_iam_instance_profile.ec2_cloudwatch_profile.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if instance already has an IAM instance profile association
      ASSOCIATION_ID=$(aws ec2 describe-iam-instance-profile-associations \
        --filters "Name=instance-id,Values=${var.instance_id}" \
        --region ${var.aws_region} \
        --query 'IamInstanceProfileAssociations[0].AssociationId' \
        --output text 2>/dev/null || echo "None")
      
      # If instance already has a profile, disassociate it first
      if [ "$ASSOCIATION_ID" != "None" ] && [ ! -z "$ASSOCIATION_ID" ]; then
        echo "Disassociating existing IAM instance profile (Association ID: $ASSOCIATION_ID)..."
        aws ec2 disassociate-iam-instance-profile \
          --association-id "$ASSOCIATION_ID" \
          --region ${var.aws_region} || true
        echo "Waiting for disassociation to complete..."
        sleep 3
      fi
      
      # Wait a moment for IAM instance profile to be fully available
      echo "Waiting for IAM instance profile to be available..."
      sleep 2
      
      # Associate the new IAM instance profile using ARN
      echo "Associating IAM instance profile: ${aws_iam_instance_profile.ec2_cloudwatch_profile.arn}"
      aws ec2 associate-iam-instance-profile \
        --instance-id ${var.instance_id} \
        --iam-instance-profile Arn=${aws_iam_instance_profile.ec2_cloudwatch_profile.arn} \
        --region ${var.aws_region}
      
      echo "IAM instance profile successfully attached!"
    EOT
  }

  depends_on = [
    aws_iam_instance_profile.ec2_cloudwatch_profile,
    aws_iam_role.ec2_cloudwatch_role
  ]
}

