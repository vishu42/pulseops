#!/usr/bin/env bash
set -euo pipefail

# Creates the AWS-side infrastructure for PulseOps.
#
# Prereqs:
#   source scripts/aws/00-env.sh
#   aws --version
#   jq --version
#
# This script is intentionally plain AWS CLI. Review each section before running.

# Fail early if the shared environment has not been sourced. The message after
# ? is what Bash prints if the variable is missing.
: "${AWS_PROFILE:?source scripts/aws/00-env.sh first}"
: "${AWS_REGION:?source scripts/aws/00-env.sh first}"
: "${NAME_PREFIX:?source scripts/aws/00-env.sh first}"
: "${CLUSTER_NAME:?source scripts/aws/00-env.sh first}"

# Helper for tagging EC2-style resources if we need extra tags later. Most
# create commands already use tag-specifications inline.
tag_resource() {
  local resource_id="$1"
  shift
  aws ec2 create-tags \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --resources "$resource_id" \
    --tags "Key=Project,Value=$PROJECT" "Key=Environment,Value=$ENVIRONMENT" "$@"
}

echo "Creating VPC"
# Create the network boundary for all PulseOps resources. The --query keeps only
# the VPC id so later commands can reference it directly.
export VPC_ID="$(
  aws ec2 create-vpc \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --cidr-block "$VPC_CIDR" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${NAME_PREFIX}-vpc},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Vpc.VpcId' \
    --output text
)"

# EKS, RDS endpoints, and private service discovery need DNS support enabled.
aws ec2 modify-vpc-attribute --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
aws ec2 modify-vpc-attribute --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'

echo "Creating subnets"
# Public subnets hold public-facing load balancers and the NAT Gateway. The
# kubernetes.io/role/elb tag lets the AWS Load Balancer Controller discover
# these subnets for internet-facing ALBs.
export PUBLIC_SUBNET_A="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_A" --cidr-block "$PUBLIC_SUBNET_A_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-a},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"
export PUBLIC_SUBNET_B="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_B" --cidr-block "$PUBLIC_SUBNET_B_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-b},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"
export PUBLIC_SUBNET_C="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_C" --cidr-block "$PUBLIC_SUBNET_C_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-c},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"

# Private subnets hold EKS worker nodes and self-managed Kafka. The
# kubernetes.io/role/internal-elb tag lets Kubernetes create internal load
# balancers here if needed.
export PRIVATE_SUBNET_A="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_A" --cidr-block "$PRIVATE_SUBNET_A_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-private-a},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"
export PRIVATE_SUBNET_B="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_B" --cidr-block "$PRIVATE_SUBNET_B_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-private-b},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"
export PRIVATE_SUBNET_C="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_C" --cidr-block "$PRIVATE_SUBNET_C_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-private-c},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"

# DB subnets isolate RDS from the general worker-node subnets. They still use
# the private route table, but they are only placed into the RDS subnet group.
export DB_SUBNET_A="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_A" --cidr-block "$DB_SUBNET_A_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-db-a},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"
export DB_SUBNET_B="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_B" --cidr-block "$DB_SUBNET_B_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-db-b},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"
export DB_SUBNET_C="$(
  aws ec2 create-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ_C" --cidr-block "$DB_SUBNET_C_CIDR" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-db-c},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Subnet.SubnetId' --output text
)"

# Do not enable map-public-ip-on-launch by default. Public-facing managed
# resources such as ALBs and NAT Gateways can still get public addresses as
# needed, while manually launched EC2 instances stay private unless explicitly
# configured otherwise.

echo "Creating internet gateway and NAT gateway"
# Internet Gateway gives public subnets a path to/from the internet.
export IGW_ID="$(
  aws ec2 create-internet-gateway \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${NAME_PREFIX}-igw},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text
)"
aws ec2 attach-internet-gateway --profile "$AWS_PROFILE" --region "$AWS_REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

# NAT Gateway gives private subnets outbound internet access. This is needed for
# status-checker probes to public URLs and for any dependency downloads that do
# not go through VPC endpoints. This uses one NAT Gateway for lower cost; use
# one per AZ if you need higher availability.
export NAT_EIP_ALLOCATION_ID="$(
  aws ec2 allocate-address \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${NAME_PREFIX}-nat-eip},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'AllocationId' \
    --output text
)"

export NAT_GATEWAY_ID="$(
  aws ec2 create-nat-gateway \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --subnet-id "$PUBLIC_SUBNET_A" \
    --allocation-id "$NAT_EIP_ALLOCATION_ID" \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${NAME_PREFIX}-nat-a},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'NatGateway.NatGatewayId' \
    --output text
)"

# Wait until the NAT Gateway is usable before creating routes through it.
aws ec2 wait nat-gateway-available --profile "$AWS_PROFILE" --region "$AWS_REGION" --nat-gateway-ids "$NAT_GATEWAY_ID"

echo "Creating route tables"
# Public route table sends default internet traffic through the Internet Gateway.
export PUBLIC_ROUTE_TABLE_ID="$(
  aws ec2 create-route-table \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-rt},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'RouteTable.RouteTableId' \
    --output text
)"
aws ec2 create-route --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"

# Associate all public subnets with the public route table.
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --subnet-id "$PUBLIC_SUBNET_A"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --subnet-id "$PUBLIC_SUBNET_B"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --subnet-id "$PUBLIC_SUBNET_C"

# Private route table sends default internet-bound traffic through NAT while
# keeping workloads unreachable from the public internet.
export PRIVATE_ROUTE_TABLE_ID="$(
  aws ec2 create-route-table \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME_PREFIX}-private-rt},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'RouteTable.RouteTableId' \
    --output text
)"
aws ec2 create-route --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GATEWAY_ID"

# Associate app, Kafka, and DB subnets with the private route table.
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --subnet-id "$PRIVATE_SUBNET_A"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --subnet-id "$PRIVATE_SUBNET_B"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --subnet-id "$PRIVATE_SUBNET_C"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --subnet-id "$DB_SUBNET_A"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --subnet-id "$DB_SUBNET_B"
aws ec2 associate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --subnet-id "$DB_SUBNET_C"

echo "Creating security groups"
# ALB security group accepts HTTP/HTTPS from the internet. Production should
# redirect HTTP to HTTPS at the ALB/Ingress layer.
export ALB_SECURITY_GROUP_ID="$(
  aws ec2 create-security-group \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --group-name "${NAME_PREFIX}-alb-sg" \
    --description "PulseOps ALB security group" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${NAME_PREFIX}-alb-sg},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'GroupId' \
    --output text
)"
aws ec2 authorize-security-group-ingress --profile "$AWS_PROFILE" --region "$AWS_REGION" --group-id "$ALB_SECURITY_GROUP_ID" --ip-permissions \
  'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' \
  'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]'

# RDS security group accepts Postgres traffic from inside the VPC. This is broad
# but simple for the first cut; later we can restrict it to EKS node/pod security
# groups.
export RDS_SECURITY_GROUP_ID="$(
  aws ec2 create-security-group \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --group-name "${NAME_PREFIX}-rds-sg" \
    --description "PulseOps RDS security group" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${NAME_PREFIX}-rds-sg},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'GroupId' \
    --output text
)"
aws ec2 authorize-security-group-ingress --profile "$AWS_PROFILE" --region "$AWS_REGION" --group-id "$RDS_SECURITY_GROUP_ID" --protocol tcp --port 5432 --cidr "$VPC_CIDR"

# Interface VPC endpoints need a security group that allows HTTPS from private
# workloads inside the VPC.
# Security groups are created inside one VPC, but they are reusable within that
# VPC: the same security group can be attached to many ENIs/resources such as EC2
# instances, load balancers, RDS instances, and interface VPC endpoints.
export ENDPOINT_SECURITY_GROUP_ID="$(
  aws ec2 create-security-group \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --group-name "${NAME_PREFIX}-vpce-sg" \
    --description "PulseOps VPC endpoint security group" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${NAME_PREFIX}-vpce-sg},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'GroupId' \
    --output text
)"
aws ec2 authorize-security-group-ingress --profile "$AWS_PROFILE" --region "$AWS_REGION" --group-id "$ENDPOINT_SECURITY_GROUP_ID" --protocol tcp --port 443 --cidr "$VPC_CIDR"

echo "Creating cost-saving VPC endpoints"
# S3 Gateway Endpoint keeps S3 traffic off the NAT Gateway and has no hourly
# charge. It is attached to the private route table.
aws ec2 create-vpc-endpoint \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --service-name "com.amazonaws.${AWS_REGION}.s3" \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$PRIVATE_ROUTE_TABLE_ID" \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${NAME_PREFIX}-s3-gateway},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]"

# Interface endpoints reduce NAT usage for common control-plane calls from EKS
# nodes and pods: ECR pulls, CloudWatch Logs, Secrets Manager, and STS.
for service in ecr.api ecr.dkr logs secretsmanager sts; do
  aws ec2 create-vpc-endpoint \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --vpc-id "$VPC_ID" \
    --service-name "com.amazonaws.${AWS_REGION}.${service}" \
    --vpc-endpoint-type Interface \
    --subnet-ids "$PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_B" "$PRIVATE_SUBNET_C" \
    --security-group-ids "$ENDPOINT_SECURITY_GROUP_ID" \
    --private-dns-enabled \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${NAME_PREFIX}-${service}-endpoint},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]"
done

echo "Creating IAM roles"
# Trust policy for the EKS control plane role. It lets the EKS service assume
# this role to manage cluster resources.
cat > /tmp/pulseops-eks-cluster-trust.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

# Trust policy for EKS worker nodes. EC2 instances in the node groups assume this
# role to join the cluster, pull images, attach EBS volumes, and use the VPC CNI.
cat > /tmp/pulseops-eks-node-trust.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

# Create the EKS cluster IAM role and attach the standard managed policy.
export EKS_CLUSTER_ROLE_ARN="$(
  aws iam create-role \
    --profile "$AWS_PROFILE" \
    --role-name "${NAME_PREFIX}-eks-cluster-role" \
    --assume-role-policy-document file:///tmp/pulseops-eks-cluster-trust.json \
    --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}" \
    --query 'Role.Arn' \
    --output text
)"
aws iam attach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-cluster-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Create the worker-node IAM role. The attached policies allow nodes to join EKS,
# run the VPC CNI, pull from ECR, and support EBS volumes for Kafka PVCs.
export EKS_NODE_ROLE_ARN="$(
  aws iam create-role \
    --profile "$AWS_PROFILE" \
    --role-name "${NAME_PREFIX}-eks-node-role" \
    --assume-role-policy-document file:///tmp/pulseops-eks-node-trust.json \
    --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}" \
    --query 'Role.Arn' \
    --output text
)"
aws iam attach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Look up the EBS CSI managed policy ARN instead of hardcoding the path. This is
# more robust across AWS partitions and avoids NoSuchEntity if the path differs.
export EBS_CSI_POLICY_ARN="$(
  aws iam list-policies \
    --profile "$AWS_PROFILE" \
    --scope AWS \
    --query "Policies[?PolicyName=='AmazonEBSCSIDriverPolicy'].Arn | [0]" \
    --output text
)"

if [ "$EBS_CSI_POLICY_ARN" = "None" ] || [ -z "$EBS_CSI_POLICY_ARN" ]; then
  echo "AWS managed policy AmazonEBSCSIDriverPolicy was not found; creating a PulseOps-managed fallback policy."
  cat > /tmp/pulseops-ebs-csi-policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteSnapshot",
        "ec2:DeleteTags",
        "ec2:DeleteVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:DetachVolume",
        "ec2:ModifyVolume"
      ],
      "Resource": "*"
    }
  ]
}
JSON
  export EBS_CSI_POLICY_ARN="$(
    aws iam create-policy \
      --profile "$AWS_PROFILE" \
      --policy-name "${NAME_PREFIX}-AmazonEBSCSIDriverPolicy" \
      --policy-document file:///tmp/pulseops-ebs-csi-policy.json \
      --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}" \
      --query 'Policy.Arn' \
      --output text
  )"
fi

aws iam attach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn "$EBS_CSI_POLICY_ARN"

echo "Creating EKS cluster"
# Create a private-subnet EKS cluster. endpointPublicAccess=true keeps kubectl
# access simple for now; endpointPrivateAccess=true allows in-VPC access too.
aws eks create-cluster \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --version "1.35" \
  --role-arn "arn:aws:iam::012345678910:role/eks-service-role-AWSServiceRoleForAmazonEKS-J7ONKE3BQ4PI" \
  --resources-vpc-config "subnetIds=${PRIVATE_SUBNET_A},${PRIVATE_SUBNET_B},${PRIVATE_SUBNET_C}" \
  --tags "Project=${PROJECT},Environment=${ENVIRONMENT}"

aws eks create-cluster \
  --name "$CLUSTER_NAME" \
  --region $AWS_REGION \
  --role-arn  arn:aws:iam::211481646329:role/pulseops-prod-eks-cluster-role \
  --resources-vpc-config "subnetIds=${PRIVATE_SUBNET_A},${PRIVATE_SUBNET_B},${PRIVATE_SUBNET_C}"

# securityGroupIds=${ALB_SECURITY_GROUP_ID},endpointPublicAccess=true,endpointPrivateAccess=true"

# Block until the EKS control plane is ready for node groups and add-ons.
aws eks wait cluster-active --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Creating EKS node groups"
# App node group runs stateless application workloads. It uses Spot capacity for
# cost savings because api/checker/writer/scheduler pods can be rescheduled.
aws eks create-nodegroup \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "${NAME_PREFIX}-app-ng" \
  --node-role "$EKS_NODE_ROLE_ARN" \
  --subnets "$PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_B" "$PRIVATE_SUBNET_C" \
  --instance-types "$APP_NODE_INSTANCE_TYPES" \
  --capacity-type SPOT \
  --scaling-config minSize=2,maxSize=6,desiredSize=2 \
  --labels workload=app \
  --tags "Project=${PROJECT},Environment=${ENVIRONMENT}"

# Kafka node group runs only Kafka broker/controller pods. It uses on-demand
# capacity, fixed size 3, a workload label, and a taint so ordinary app pods do
# not land on Kafka nodes.
aws eks create-nodegroup \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "${NAME_PREFIX}-kafka-ng" \
  --node-role "$EKS_NODE_ROLE_ARN" \
  --subnets "$PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_B" "$PRIVATE_SUBNET_C" \
  --instance-types "$KAFKA_NODE_INSTANCE_TYPES" \
  --capacity-type ON_DEMAND \
  --scaling-config minSize=3,maxSize=3,desiredSize=3 \
  --labels workload=kafka \
  --taints key=dedicated,value=kafka,effect=NO_SCHEDULE \
  --tags "Project=${PROJECT},Environment=${ENVIRONMENT}"

# Wait until both node groups are ready before installing add-ons or Kafka.
aws eks wait nodegroup-active --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "${NAME_PREFIX}-app-ng"
aws eks wait nodegroup-active --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "${NAME_PREFIX}-kafka-ng"

echo "Installing EKS managed add-ons"
# vpc-cni provides pod networking, kube-proxy handles Service routing, coredns
# provides cluster DNS, and aws-ebs-csi-driver provisions Kafka EBS volumes.
aws eks create-addon --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name vpc-cni --resolve-conflicts OVERWRITE
aws eks create-addon --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name kube-proxy --resolve-conflicts OVERWRITE
aws eks create-addon --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name coredns --resolve-conflicts OVERWRITE
aws eks create-addon --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name aws-ebs-csi-driver --resolve-conflicts OVERWRITE

echo "Creating ECR repositories"
# One image repository per service keeps permissions, lifecycle rules, and image
# history easier to reason about. The create command is allowed to fail if the
# repo already exists so reruns are less annoying.
for repo in "$API_REPO" "$SCHEDULER_REPO" "$CHECKER_REPO" "$WRITER_REPO"; do
  aws ecr create-repository \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --repository-name "$repo" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}" || true
done

echo "Creating S3 archive bucket"
# Bucket for cold probe history after it leaves hot Postgres storage.
aws s3 mb "s3://${ARCHIVE_BUCKET}" --profile "$AWS_PROFILE" --region "$AWS_REGION"

# Block all public access because archive data should never be publicly exposed.
aws s3api put-public-access-block \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$ARCHIVE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable simple SSE-S3 encryption. Use SSE-KMS later if audit requirements need
# customer-managed keys.
aws s3api put-bucket-encryption \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$ARCHIVE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Lifecycle rule lowers long-term archive cost by moving objects to cheaper S3
# storage classes as they age.
cat > /tmp/pulseops-s3-lifecycle.json <<'JSON'
{
  "Rules": [
    {
      "ID": "archive-history-cost-optimization",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 180, "StorageClass": "GLACIER_IR" }
      ]
    }
  ]
}
JSON

# Attach the lifecycle policy to the archive bucket.
aws s3api put-bucket-lifecycle-configuration \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$ARCHIVE_BUCKET" \
  --lifecycle-configuration file:///tmp/pulseops-s3-lifecycle.json

echo "Creating RDS subnet group and database"
# RDS subnet group tells RDS which private DB subnets it can place instances in.
aws rds create-db-subnet-group \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --db-subnet-group-description "PulseOps RDS subnet group" \
  --subnet-ids "$DB_SUBNET_A" "$DB_SUBNET_B" "$DB_SUBNET_C" \
  --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}"

# Generate a password unless DB_PASSWORD was exported before running. The
# generated value is stored in Secrets Manager below.
export DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 32 | tr -d '=+/[:space:]' | cut -c1-32)}"

# Store DB credentials for later use by Kubernetes secret sync / app config.
aws secretsmanager create-secret \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$RDS_SECRET_NAME" \
  --description "PulseOps RDS credentials" \
  --secret-string "{\"username\":\"${DB_USERNAME}\",\"password\":\"${DB_PASSWORD}\",\"dbname\":\"${DB_NAME}\"}" \
  --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}"

# Create the production PostgreSQL database. Multi-AZ and deletion protection
# are enabled intentionally; use smaller/single-AZ settings for disposable dev.
aws rds create-db-instance \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --engine postgres \
  --engine-version 16.4 \
  --db-instance-class "$DB_INSTANCE_CLASS" \
  --allocated-storage "$DB_ALLOCATED_STORAGE_GB" \
  --max-allocated-storage "$DB_MAX_STORAGE_GB" \
  --storage-type gp3 \
  --db-name "$DB_NAME" \
  --master-username "$DB_USERNAME" \
  --master-user-password "$DB_PASSWORD" \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --vpc-security-group-ids "$RDS_SECURITY_GROUP_ID" \
  --backup-retention-period 7 \
  --multi-az \
  --no-publicly-accessible \
  --storage-encrypted \
  --deletion-protection \
  --tags "Key=Project,Value=${PROJECT}" "Key=Environment,Value=${ENVIRONMENT}"

# Wait until RDS is ready before reading its endpoint.
aws rds wait db-instance-available --profile "$AWS_PROFILE" --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER"

# Capture the DNS endpoint apps will use in DATABASE_URL.
export DB_ENDPOINT="$(
  aws rds describe-db-instances \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text
)"

echo "Persisting discovered IDs to /tmp/pulseops-aws-ids.env"
# Later scripts need generated AWS ids, so write them to a source-able temp file.
# Keep this file private because it includes infrastructure identifiers, though
# not the database password.
cat > /tmp/pulseops-aws-ids.env <<EOF
export VPC_ID="${VPC_ID}"
export PUBLIC_SUBNET_A="${PUBLIC_SUBNET_A}"
export PUBLIC_SUBNET_B="${PUBLIC_SUBNET_B}"
export PUBLIC_SUBNET_C="${PUBLIC_SUBNET_C}"
export PRIVATE_SUBNET_A="${PRIVATE_SUBNET_A}"
export PRIVATE_SUBNET_B="${PRIVATE_SUBNET_B}"
export PRIVATE_SUBNET_C="${PRIVATE_SUBNET_C}"
export DB_SUBNET_A="${DB_SUBNET_A}"
export DB_SUBNET_B="${DB_SUBNET_B}"
export DB_SUBNET_C="${DB_SUBNET_C}"
export ALB_SECURITY_GROUP_ID="${ALB_SECURITY_GROUP_ID}"
export RDS_SECURITY_GROUP_ID="${RDS_SECURITY_GROUP_ID}"
export EKS_CLUSTER_ROLE_ARN="${EKS_CLUSTER_ROLE_ARN}"
export EKS_NODE_ROLE_ARN="${EKS_NODE_ROLE_ARN}"
export DB_ENDPOINT="${DB_ENDPOINT}"
EOF

# Final hints for the next manual steps.
echo "AWS infra created. Next:"
echo "  source /tmp/pulseops-aws-ids.env"
echo "  bash scripts/aws/02-install-k8s-addons.sh"
