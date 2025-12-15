# IAM Requirements for CloudWatch Agent Installation

## ✅ IAM is Now Automated via Terraform!

**Good news:** All IAM resources (roles, policies, instance profiles) are now created and attached automatically by Terraform. You don't need to do anything manually!

The `iam.tf` file creates:
- IAM Role with required permissions
- IAM Instance Profile
- Automatically attaches the profile to your EC2 instance

## What Terraform Creates Automatically

For the CloudWatch Agent to be installed automatically via Terraform using SSM, Terraform creates an IAM role with the following permissions:

### Required IAM Policies

1. **AmazonSSMManagedInstanceCore** (AWS Managed Policy)
   - Allows SSM to communicate with the instance
   - Required for SSM Association to work

2. **CloudWatchAgentServerPolicy** (AWS Managed Policy)
   - Allows CloudWatch Agent to publish metrics to CloudWatch
   - Required for metrics to be sent

### Minimum IAM Policy (if creating custom policy)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "ec2:DescribeVolumes",
        "ec2:DescribeTags",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:CreateLogStream",
        "logs:CreateLogGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

## ✅ No Manual Steps Required!

Terraform automatically:
1. Creates the IAM role (`iam.tf`)
2. Attaches required AWS managed policies
3. Creates IAM instance profile
4. Associates the profile with your EC2 instance

### Verify IAM Role After Terraform Apply

After running `terraform apply`, you can verify the IAM role was attached:

```bash
aws ec2 describe-instances \
  --instance-ids i-020be26a823f801d5 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
```

Or check in AWS Console:
- EC2 → Instances → Select your instance → Security tab → IAM role

## Verify SSM Agent is Running

SSM Agent is pre-installed on Amazon Linux 2, but verify it's running:

```bash
sudo systemctl status amazon-ssm-agent
```

If not running:
```bash
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
```

## After Terraform Apply

Once you run `terraform apply`, the CloudWatch Agent will be automatically:
1. Installed on the EC2 instance
2. Configured with the settings from SSM Parameter Store
3. Started and running

You can verify installation:
```bash
sudo systemctl status amazon-cloudwatch-agent
```

## Troubleshooting

### Issue: SSM Association fails
- Check IAM role is attached to instance
- Verify SSM Agent is running: `sudo systemctl status amazon-ssm-agent`
- Check SSM Association status in AWS Console → Systems Manager → Fleet Manager

### Issue: CloudWatch Agent not sending metrics
- Verify IAM role has CloudWatch permissions
- Check agent logs: `sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log`
- Verify agent is running: `sudo systemctl status amazon-cloudwatch-agent`

