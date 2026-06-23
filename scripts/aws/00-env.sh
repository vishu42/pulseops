#!/usr/bin/env bash

# Source this file before running the other AWS scripts. It exports shared
# names, regions, CIDRs, instance sizes, and derived AWS account metadata.
#
#   source scripts/aws/00-env.sh
#
# Review every value before creating infrastructure.

# AWS CLI profile to use. Override with AWS_PROFILE=my-profile before sourcing.
export AWS_PROFILE="${AWS_PROFILE:-default}"

# AWS region where every regional resource will be created.
export AWS_REGION="${AWS_REGION:-us-east-1}"

# Logical project/environment labels. These feed resource names and tags.
export PROJECT="${PROJECT:-pulseops}"
export ENVIRONMENT="${ENVIRONMENT:-prod}"

# Prefix used for most AWS resource names, for example pulseops-prod-eks.
export NAME_PREFIX="${NAME_PREFIX:-${PROJECT}-${ENVIRONMENT}}"

# VPC CIDR and subnet CIDRs. The layout reserves public, private app/Kafka,
# and DB-only subnet ranges across three Availability Zones.
export VPC_CIDR="${VPC_CIDR:-10.42.0.0/16}"
export PUBLIC_SUBNET_A_CIDR="${PUBLIC_SUBNET_A_CIDR:-10.42.0.0/20}"
export PUBLIC_SUBNET_B_CIDR="${PUBLIC_SUBNET_B_CIDR:-10.42.16.0/20}"
export PUBLIC_SUBNET_C_CIDR="${PUBLIC_SUBNET_C_CIDR:-10.42.32.0/20}"
export PRIVATE_SUBNET_A_CIDR="${PRIVATE_SUBNET_A_CIDR:-10.42.48.0/20}"
export PRIVATE_SUBNET_B_CIDR="${PRIVATE_SUBNET_B_CIDR:-10.42.64.0/20}"
export PRIVATE_SUBNET_C_CIDR="${PRIVATE_SUBNET_C_CIDR:-10.42.80.0/20}"
export DB_SUBNET_A_CIDR="${DB_SUBNET_A_CIDR:-10.42.96.0/24}"
export DB_SUBNET_B_CIDR="${DB_SUBNET_B_CIDR:-10.42.97.0/24}"
export DB_SUBNET_C_CIDR="${DB_SUBNET_C_CIDR:-10.42.98.0/24}"

# EKS version and node instance families. App nodes default to smaller Spot
# capacity, while Kafka nodes default to on-demand capacity in the infra script.
export EKS_VERSION="${EKS_VERSION:-1.30}"
export APP_NODE_INSTANCE_TYPES="${APP_NODE_INSTANCE_TYPES:-t3.large}"
export KAFKA_NODE_INSTANCE_TYPES="${KAFKA_NODE_INSTANCE_TYPES:-m7i.large}"

# RDS PostgreSQL defaults. Multi-AZ is enabled in the infra script, so this
# instance class should be sized with production cost in mind.
export DB_NAME="${DB_NAME:-pulseops}"
export DB_USERNAME="${DB_USERNAME:-pulseops}"
export DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-db.t4g.medium}"
export DB_ALLOCATED_STORAGE_GB="${DB_ALLOCATED_STORAGE_GB:-50}"
export DB_MAX_STORAGE_GB="${DB_MAX_STORAGE_GB:-200}"

# S3 bucket for archived probe history. Bucket names are globally unique, so
# override ARCHIVE_BUCKET if this generated name is already taken.
export ARCHIVE_BUCKET="${ARCHIVE_BUCKET:-${NAME_PREFIX}-history-${AWS_REGION}}"

# ECR repository names for each Go service image.
export API_REPO="${API_REPO:-${NAME_PREFIX}/api-server}"
export SCHEDULER_REPO="${SCHEDULER_REPO:-${NAME_PREFIX}/scheduler}"
export CHECKER_REPO="${CHECKER_REPO:-${NAME_PREFIX}/status-checker}"
export WRITER_REPO="${WRITER_REPO:-${NAME_PREFIX}/status-writer}"

# Stable names for EKS, RDS, and the RDS credential secret.
export CLUSTER_NAME="${CLUSTER_NAME:-${NAME_PREFIX}-eks}"
export DB_IDENTIFIER="${DB_IDENTIFIER:-${NAME_PREFIX}-postgres}"
export DB_SUBNET_GROUP="${DB_SUBNET_GROUP:-${NAME_PREFIX}-db-subnets}"
export RDS_SECRET_NAME="${RDS_SECRET_NAME:-/${NAME_PREFIX}/rds}"

# Resolve the AWS account id from the active profile. Other scripts use it for
# ECR URLs and IAM policy ARNs.
export ACCOUNT_ID="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"

# Pick the first three AZs in the selected region so the VPC, EKS node groups,
# Kafka brokers, and RDS subnet group can span three failure domains.
export AZ_A="$(aws ec2 describe-availability-zones --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'AvailabilityZones[0].ZoneName' --output text)"
export AZ_B="$(aws ec2 describe-availability-zones --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'AvailabilityZones[1].ZoneName' --output text)"
export AZ_C="$(aws ec2 describe-availability-zones --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'AvailabilityZones[2].ZoneName' --output text)"

# Print the key resolved values so you can verify you are pointed at the right
# AWS account and region before creating paid resources.
echo "Loaded PulseOps AWS environment:"
echo "  AWS_PROFILE=$AWS_PROFILE"
echo "  AWS_REGION=$AWS_REGION"
echo "  ACCOUNT_ID=$ACCOUNT_ID"
echo "  NAME_PREFIX=$NAME_PREFIX"
echo "  CLUSTER_NAME=$CLUSTER_NAME"
