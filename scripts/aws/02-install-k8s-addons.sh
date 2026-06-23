#!/usr/bin/env bash
set -euo pipefail

# Installs Kubernetes-side AWS add-ons and self-managed Kafka.
#
# Prereqs:
#   source scripts/aws/00-env.sh
#   source /tmp/pulseops-aws-ids.env
#   aws eks update-kubeconfig --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME"
#   kubectl version --client
#   helm version
#   eksctl version

# Ensure the required variables exist before any cluster mutation happens.
: "${AWS_PROFILE:?source scripts/aws/00-env.sh first}"
: "${AWS_REGION:?source scripts/aws/00-env.sh first}"
: "${CLUSTER_NAME:?source scripts/aws/00-env.sh first}"
: "${VPC_ID:?source /tmp/pulseops-aws-ids.env first}"

# Write/refresh kubeconfig so kubectl and helm point at the new EKS cluster.
aws eks update-kubeconfig --profile "$AWS_PROFILE" --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Associating IAM OIDC provider for IRSA"
# IRSA lets Kubernetes service accounts assume IAM roles without static AWS
# access keys. The ALB controller uses this below.
eksctl utils associate-iam-oidc-provider \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --approve

echo "Installing AWS Load Balancer Controller"
# Download the official IAM policy for the AWS Load Balancer Controller. This
# controller creates ALBs/NLBs from Kubernetes Ingress and Service resources.
curl -fsSL -o /tmp/aws-load-balancer-controller-iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# Create the IAM policy. The || true makes reruns safe if the policy exists.
aws iam create-policy \
  --profile "$AWS_PROFILE" \
  --policy-name "${NAME_PREFIX}-AWSLoadBalancerControllerIAMPolicy" \
  --policy-document file:///tmp/aws-load-balancer-controller-iam-policy.json || true

# Create/replace a Kubernetes service account bound to the IAM policy above.
eksctl create iamserviceaccount \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name "${NAME_PREFIX}-aws-load-balancer-controller" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${NAME_PREFIX}-AWSLoadBalancerControllerIAMPolicy" \
  --approve \
  --override-existing-serviceaccounts

# Install the controller into kube-system using the official EKS Helm chart.
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

echo "Installing metrics-server"
# metrics-server enables basic CPU/memory metrics used by kubectl top and HPAs.
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "Installing Strimzi Kafka Operator"
# Strimzi manages Kafka clusters, users, and topics through Kubernetes CRDs.
kubectl create namespace kafka-system --dry-run=client -o yaml | kubectl apply -f -
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# watchAnyNamespace=true lets the operator manage Kafka resources in the
# pulseops namespace while the operator itself lives in kafka-system.
helm upgrade --install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace kafka-system \
  --set watchAnyNamespace=true

echo "Creating PulseOps namespace"
# Application services and Kafka custom resources live in this namespace.
kubectl create namespace pulseops --dry-run=client -o yaml | kubectl apply -f -

echo "Creating gp3 storage class for Kafka"
# Kafka broker storage uses encrypted EBS gp3 volumes. WaitForFirstConsumer
# delays volume creation until a broker pod is scheduled, which helps place EBS
# volumes in the same AZ as their pods.
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-kafka
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
YAML

echo "Creating self-managed Kafka cluster with Strimzi"
# KafkaNodePool defines three combined broker/controller nodes for KRaft mode.
# The toleration and nodeSelector force Kafka onto the dedicated Kafka node group.
# The topology spread constraint distributes brokers across AZs when possible.
cat <<'YAML' | kubectl apply -n pulseops -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: kafka
  labels:
    strimzi.io/cluster: pulseops-kafka
spec:
  replicas: 3
  roles:
    - broker
    - controller
  storage:
    type: persistent-claim
    size: 100Gi
    class: gp3-kafka
    deleteClaim: false
  template:
    pod:
      tolerations:
        - key: dedicated
          operator: Equal
          value: kafka
          effect: NoSchedule
      nodeSelector:
        workload: kafka
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              strimzi.io/cluster: pulseops-kafka
---
# Kafka custom resource defines listeners, replication settings, and enables the
# topic/user operators. The internal plain listener is only reachable in-cluster;
# add TLS/SASL before exposing any sensitive production data.
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: pulseops-kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.8.0
    metadataVersion: 3.8-IV0
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      default.replication.factor: 3
      min.insync.replicas: 2
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      auto.create.topics.enable: false
  entityOperator:
    topicOperator: {}
    userOperator: {}
YAML

# Wait for Strimzi to finish creating the Kafka StatefulSet and for the cluster
# to report Ready.
kubectl wait kafka/pulseops-kafka -n pulseops --for=condition=Ready --timeout=900s

echo "Creating Kafka topics"
# KafkaTopic resources let Strimzi create and reconcile Kafka topics declaratively.
# Jobs/results use more partitions than DLQs because they carry normal traffic.
cat <<'YAML' | kubectl apply -n pulseops -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: pulseops.url-check-jobs.v1
  labels:
    strimzi.io/cluster: pulseops-kafka
spec:
  partitions: 12
  replicas: 3
  config:
    retention.ms: 86400000
    min.insync.replicas: 2
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: pulseops.url-check-results.v1
  labels:
    strimzi.io/cluster: pulseops-kafka
spec:
  partitions: 12
  replicas: 3
  config:
    retention.ms: 604800000
    min.insync.replicas: 2
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: pulseops.url-check-jobs.dlq.v1
  labels:
    strimzi.io/cluster: pulseops-kafka
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 1209600000
    min.insync.replicas: 2
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: pulseops.url-check-results.dlq.v1
  labels:
    strimzi.io/cluster: pulseops-kafka
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 1209600000
    min.insync.replicas: 2
YAML

# Print the internal bootstrap address for app KAFKA_BROKERS configuration.
echo "Kubernetes add-ons installed. Kafka bootstrap service:"
echo "  pulseops-kafka-kafka-bootstrap.pulseops.svc.cluster.local:9092"
