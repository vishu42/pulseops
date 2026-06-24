# AWS CLI Infrastructure Scripts

> Prefer the Terraform/OpenTofu modules in `infra/terraform` for new infrastructure work. These scripts are kept as manual runbooks/reference material.

These scripts are command runbooks for creating PulseOps AWS infrastructure with AWS CLI, EKS, and self-managed Kafka.

They are intentionally split by layer so commands can be reviewed and executed step by step.

## Scripts

1. `00-env.sh`
   - Defines names, CIDRs, regions, instance sizes, repository names, and RDS settings.
   - Source this before the other scripts.

2. `01-create-aws-infra.sh`
   - Creates VPC, subnets, NAT, route tables, VPC endpoints, IAM roles, EKS, node groups, ECR, S3 archive bucket, Secrets Manager secret, and RDS PostgreSQL.

3. `02-install-k8s-addons.sh`
   - Configures kubeconfig.
   - Installs AWS Load Balancer Controller.
   - Installs metrics-server.
   - Installs Strimzi.
   - Creates self-managed Kafka and PulseOps Kafka topics.

4. `03-build-and-push-images.sh`
   - Builds the Go service images.
   - Pushes them to ECR.

5. `99-cleanup-aws-infra.sh`
   - Deletes the AWS resources created by these scripts.
   - Requires `CONFIRM_DESTROY=pulseops`.
   - Destructive: deletes RDS, S3 archive data, EKS, Kafka, ECR repos, VPC networking, and IAM resources.

## Expected Flow

```sh
source scripts/aws/00-env.sh
bash scripts/aws/01-create-aws-infra.sh
source /tmp/pulseops-aws-ids.env
bash scripts/aws/02-install-k8s-addons.sh
bash scripts/aws/03-build-and-push-images.sh
```

Cleanup flow:

```sh
source scripts/aws/00-env.sh
source /tmp/pulseops-aws-ids.env
CONFIRM_DESTROY=pulseops bash scripts/aws/99-cleanup-aws-infra.sh
```

## Required CLIs

- `aws`
- `jq`
- `kubectl`
- `helm`
- `eksctl`
- `docker`
- `openssl`

## Notes

- These scripts create paid AWS resources.
- `01-create-aws-infra.sh` creates a single NAT Gateway for cost control. For higher availability, use one NAT Gateway per AZ and separate private route tables.
- Kafka is self-managed on EKS through Strimzi.
- Kafka broker pods use a dedicated on-demand EKS node group with EBS `gp3` volumes.
- App nodes default to Spot capacity for cost savings.
- RDS is created as Multi-AZ with deletion protection.
