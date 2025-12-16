# Shared IAM Role for all EC2 instances (more efficient than per-instance roles)
resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "ec2-cloudwatch-ssm-role-${var.environment}"

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
    Name        = "ec2-cloudwatch-ssm-role-${var.environment}"
    Environment = var.environment
    Purpose     = "CloudWatch Agent and SSM access for all monitored instances"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Per-instance IAM instance profiles
resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
  for_each = local.ec2_instances_map
  
  name = "${each.value.name}-cloudwatch-profile"
  role = aws_iam_role.ec2_cloudwatch_role.name

  tags = {
    Name        = "${each.value.name}-cloudwatch-profile"
    Environment = var.environment
    Instance    = each.value.name
  }
}

# Attach IAM instance profile to each EC2 instance
resource "null_resource" "attach_iam_instance_profile" {
  for_each = local.ec2_instances_map
  
  triggers = {
    instance_id          = each.value.instance_id
    instance_profile_arn = aws_iam_instance_profile.ec2_cloudwatch_profile[each.key].arn
  }

  provisioner "local-exec" {
    interpreter = ["C:\\Program Files\\Git\\bin\\bash.exe", "-c"]
    command = <<-EOT
      set -e
      
      # Check if instance already has an IAM instance profile association
      ASSOCIATION_ID=$(aws ec2 describe-iam-instance-profile-associations \
        --filters "Name=instance-id,Values=${each.value.instance_id}" \
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
      echo "Associating IAM instance profile: ${aws_iam_instance_profile.ec2_cloudwatch_profile[each.key].arn}"
      aws ec2 associate-iam-instance-profile \
        --instance-id ${each.value.instance_id} \
        --iam-instance-profile Arn=${aws_iam_instance_profile.ec2_cloudwatch_profile[each.key].arn} \
        --region ${var.aws_region}
      
      echo "IAM instance profile successfully attached to ${each.value.name}!"
    EOT
  }

  depends_on = [
    aws_iam_instance_profile.ec2_cloudwatch_profile,
    aws_iam_role.ec2_cloudwatch_role
  ]
}

# Note: v3 resources removed - using unified multi-instance approach above
# All instances now use the shared IAM role with per-instance profiles
