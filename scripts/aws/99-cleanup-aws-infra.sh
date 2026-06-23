#!/usr/bin/env bash
set -euo pipefail

# Deletes the AWS resources created by the PulseOps AWS scripts.
#
# Prereqs:
#   source scripts/aws/00-env.sh
#   source /tmp/pulseops-aws-ids.env   # if available from creation
#
# This script is destructive and creates data loss. It deletes EKS, Kafka, RDS,
# S3 archive data, ECR repositories, IAM roles/policies, VPC endpoints, NAT,
# routes, subnets, and the VPC.
#
# Run only after reviewing every section:
#
#   CONFIRM_DESTROY=pulseops bash scripts/aws/99-cleanup-aws-infra.sh

# Require an explicit confirmation token so an accidental paste does not destroy
# infrastructure.
if [ "${CONFIRM_DESTROY:-}" != "pulseops" ]; then
  echo "Refusing to delete infrastructure."
  echo "Set CONFIRM_DESTROY=pulseops to confirm destructive cleanup."
  exit 1
fi

# Ensure shared environment exists. These variables come from 00-env.sh.
: "${AWS_PROFILE:?source scripts/aws/00-env.sh first}"
: "${AWS_REGION:?source scripts/aws/00-env.sh first}"
: "${NAME_PREFIX:?source scripts/aws/00-env.sh first}"
: "${CLUSTER_NAME:?source scripts/aws/00-env.sh first}"
: "${DB_IDENTIFIER:?source scripts/aws/00-env.sh first}"
: "${ARCHIVE_BUCKET:?source scripts/aws/00-env.sh first}"

# If /tmp/pulseops-aws-ids.env was not sourced, discover resource ids by tags and
# names. This makes cleanup usable even in a fresh shell.
discover_ids() {
  VPC_ID="${VPC_ID:-$(
    aws ec2 describe-vpcs \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=tag:Name,Values=${NAME_PREFIX}-vpc" \
      --query 'Vpcs[0].VpcId' \
      --output text
  )}"

  if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "No VPC found for ${NAME_PREFIX}; AWS network cleanup will be skipped."
    VPC_ID=""
    return 0
  fi

  ALB_SECURITY_GROUP_ID="${ALB_SECURITY_GROUP_ID:-$(
    aws ec2 describe-security-groups \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${NAME_PREFIX}-alb-sg" \
      --query 'SecurityGroups[0].GroupId' \
      --output text
  )}"

  RDS_SECURITY_GROUP_ID="${RDS_SECURITY_GROUP_ID:-$(
    aws ec2 describe-security-groups \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${NAME_PREFIX}-rds-sg" \
      --query 'SecurityGroups[0].GroupId' \
      --output text
  )}"

  ENDPOINT_SECURITY_GROUP_ID="${ENDPOINT_SECURITY_GROUP_ID:-$(
    aws ec2 describe-security-groups \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${NAME_PREFIX}-vpce-sg" \
      --query 'SecurityGroups[0].GroupId' \
      --output text
  )}"
}

# Helper that runs a command and continues if the resource is already gone. This
# keeps cleanup moving through partially-created stacks.
try() {
  "$@" || true
}

discover_ids

echo "Deleting Kubernetes workloads and Kafka resources if kubeconfig is available"
if command -v kubectl >/dev/null 2>&1; then
  # Refresh kubeconfig if the cluster still exists.
  try aws eks update-kubeconfig --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME"

  # Delete PulseOps namespace. This removes Strimzi Kafka custom resources, app
  # workloads, services, PVCs, and any namespace-scoped Kubernetes resources.
  try kubectl delete namespace pulseops --wait=false

  # Delete Strimzi operator namespace after Kafka resources are gone.
  try kubectl delete namespace kafka-system --wait=false
fi

echo "Deleting EKS managed node groups"
for nodegroup in "${NAME_PREFIX}-app-ng" "${NAME_PREFIX}-kafka-ng"; do
  if aws eks describe-nodegroup --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup" >/dev/null 2>&1; then
    aws eks delete-nodegroup --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup"
    aws eks wait nodegroup-deleted --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup"
  fi
done

echo "Deleting EKS cluster"
if aws eks describe-cluster --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  # Delete add-ons first so the cluster can be removed cleanly.
  for addon in aws-ebs-csi-driver coredns kube-proxy vpc-cni; do
    try aws eks delete-addon --profile "$AWS_PROFILE" --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name "$addon"
  done

  aws eks delete-cluster --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME"
  aws eks wait cluster-deleted --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME"
fi

echo "Deleting RDS PostgreSQL"
if aws rds describe-db-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER" >/dev/null 2>&1; then
  # Turn off deletion protection so the DB can be removed.
  aws rds modify-db-instance \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --no-deletion-protection \
    --apply-immediately

  aws rds wait db-instance-available --profile "$AWS_PROFILE" --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER"

  # Skip final snapshot for a complete cleanup. Change this manually if you want
  # a final recovery snapshot before deleting the DB.
  aws rds delete-db-instance \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --skip-final-snapshot \
    --delete-automated-backups

  aws rds wait db-instance-deleted --profile "$AWS_PROFILE" --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER"
fi

echo "Deleting RDS subnet group and secret"
try aws rds delete-db-subnet-group --profile "$AWS_PROFILE" --region "$AWS_REGION" --db-subnet-group-name "$DB_SUBNET_GROUP"
try aws secretsmanager delete-secret --profile "$AWS_PROFILE" --region "$AWS_REGION" --secret-id "$RDS_SECRET_NAME" --force-delete-without-recovery

echo "Deleting ECR repositories"
for repo in "$API_REPO" "$SCHEDULER_REPO" "$CHECKER_REPO" "$WRITER_REPO"; do
  try aws ecr delete-repository --profile "$AWS_PROFILE" --region "$AWS_REGION" --repository-name "$repo" --force
done

echo "Deleting S3 archive bucket contents and bucket"
if aws s3api head-bucket --profile "$AWS_PROFILE" --region "$AWS_REGION" --bucket "$ARCHIVE_BUCKET" >/dev/null 2>&1; then
  # Remove current objects. If you later enable bucket versioning, add deletion
  # for object versions and delete markers too.
  try aws s3 rm "s3://${ARCHIVE_BUCKET}" --profile "$AWS_PROFILE" --region "$AWS_REGION" --recursive
  try aws s3 rb "s3://${ARCHIVE_BUCKET}" --profile "$AWS_PROFILE" --region "$AWS_REGION"
fi

if [ -n "${VPC_ID:-}" ]; then
  echo "Deleting VPC endpoints"
  VPC_ENDPOINT_IDS="$(
    aws ec2 describe-vpc-endpoints \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'VpcEndpoints[].VpcEndpointId' \
      --output text
  )"
  if [ -n "$VPC_ENDPOINT_IDS" ]; then
    try aws ec2 delete-vpc-endpoints --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-endpoint-ids $VPC_ENDPOINT_IDS
  fi

  echo "Deleting NAT Gateways and releasing Elastic IPs"
  NAT_GATEWAY_IDS="$(
    aws ec2 describe-nat-gateways \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=pending,available,failed" \
      --query 'NatGateways[].NatGatewayId' \
      --output text
  )"
  for nat_id in $NAT_GATEWAY_IDS; do
    try aws ec2 delete-nat-gateway --profile "$AWS_PROFILE" --region "$AWS_REGION" --nat-gateway-id "$nat_id"
  done
  for nat_id in $NAT_GATEWAY_IDS; do
    try aws ec2 wait nat-gateway-deleted --profile "$AWS_PROFILE" --region "$AWS_REGION" --nat-gateway-ids "$nat_id"
  done

  EIP_ALLOCATION_IDS="$(
    aws ec2 describe-addresses \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=tag:Name,Values=${NAME_PREFIX}-nat-eip" \
      --query 'Addresses[].AllocationId' \
      --output text
  )"
  for allocation_id in $EIP_ALLOCATION_IDS; do
    try aws ec2 release-address --profile "$AWS_PROFILE" --region "$AWS_REGION" --allocation-id "$allocation_id"
  done

  echo "Deleting route tables"
  ROUTE_TABLE_IDS="$(
    aws ec2 describe-route-tables \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'RouteTables[?Associations[?Main!=`true`]].RouteTableId' \
      --output text
  )"
  for route_table_id in $ROUTE_TABLE_IDS; do
    ASSOCIATION_IDS="$(
      aws ec2 describe-route-tables \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --route-table-ids "$route_table_id" \
        --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' \
        --output text
    )"
    for association_id in $ASSOCIATION_IDS; do
      try aws ec2 disassociate-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --association-id "$association_id"
    done
    try aws ec2 delete-route-table --profile "$AWS_PROFILE" --region "$AWS_REGION" --route-table-id "$route_table_id"
  done

  echo "Detaching and deleting Internet Gateways"
  IGW_IDS="$(
    aws ec2 describe-internet-gateways \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
      --query 'InternetGateways[].InternetGatewayId' \
      --output text
  )"
  for igw_id in $IGW_IDS; do
    try aws ec2 detach-internet-gateway --profile "$AWS_PROFILE" --region "$AWS_REGION" --internet-gateway-id "$igw_id" --vpc-id "$VPC_ID"
    try aws ec2 delete-internet-gateway --profile "$AWS_PROFILE" --region "$AWS_REGION" --internet-gateway-id "$igw_id"
  done

  echo "Deleting security groups"
  for sg_id in "$ALB_SECURITY_GROUP_ID" "$RDS_SECURITY_GROUP_ID" "$ENDPOINT_SECURITY_GROUP_ID"; do
    if [ "$sg_id" != "None" ] && [ -n "$sg_id" ]; then
      try aws ec2 delete-security-group --profile "$AWS_PROFILE" --region "$AWS_REGION" --group-id "$sg_id"
    fi
  done

  echo "Deleting subnets"
  SUBNET_IDS="$(
    aws ec2 describe-subnets \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'Subnets[].SubnetId' \
      --output text
  )"
  for subnet_id in $SUBNET_IDS; do
    try aws ec2 delete-subnet --profile "$AWS_PROFILE" --region "$AWS_REGION" --subnet-id "$subnet_id"
  done

  echo "Deleting VPC"
  try aws ec2 delete-vpc --profile "$AWS_PROFILE" --region "$AWS_REGION" --vpc-id "$VPC_ID"
fi

echo "Deleting IAM roles and policies"
try aws iam detach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-cluster-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
try aws iam delete-role --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-cluster-role"

try aws iam detach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
try aws iam detach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
try aws iam detach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

CUSTOM_EBS_POLICY_ARN="$(
  aws iam list-policies \
    --profile "$AWS_PROFILE" \
    --scope Local \
    --query "Policies[?PolicyName=='${NAME_PREFIX}-AmazonEBSCSIDriverPolicy'].Arn | [0]" \
    --output text
)"
if [ "$CUSTOM_EBS_POLICY_ARN" != "None" ] && [ -n "$CUSTOM_EBS_POLICY_ARN" ]; then
  try aws iam detach-role-policy --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role" --policy-arn "$CUSTOM_EBS_POLICY_ARN"
  try aws iam delete-policy --profile "$AWS_PROFILE" --policy-arn "$CUSTOM_EBS_POLICY_ARN"
fi
try aws iam delete-role --profile "$AWS_PROFILE" --role-name "${NAME_PREFIX}-eks-node-role"

ALB_CONTROLLER_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${NAME_PREFIX}-AWSLoadBalancerControllerIAMPolicy"
ALB_CONTROLLER_ROLE_NAME="${NAME_PREFIX}-aws-load-balancer-controller"
try aws iam detach-role-policy --profile "$AWS_PROFILE" --role-name "$ALB_CONTROLLER_ROLE_NAME" --policy-arn "$ALB_CONTROLLER_POLICY_ARN"
try aws iam delete-role --profile "$AWS_PROFILE" --role-name "$ALB_CONTROLLER_ROLE_NAME"
try aws iam delete-policy --profile "$AWS_PROFILE" --policy-arn "$ALB_CONTROLLER_POLICY_ARN"

echo "Cleanup finished. Check AWS console for any retained resources such as EBS volumes, snapshots, load balancers, or log groups."

