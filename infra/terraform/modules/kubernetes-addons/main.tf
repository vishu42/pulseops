locals {
  alb_controller_service_account = "aws-load-balancer-controller"
  alb_controller_namespace       = "kube-system"
  kafka_cluster_name             = "pulseops-kafka"
}

data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.alb_controller_namespace}:${local.alb_controller_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "alb_controller" {
  statement {
    actions = [
      "iam:CreateServiceLinkedRole",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCoipPools",
      "ec2:DescribeInstances",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:GetCoipPoolUsage",
      "ec2:GetSecurityGroupsForVpc",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "elasticloadbalancing:*",
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  policy = data.aws_iam_policy_document.alb_controller.json
  tags   = var.tags
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = local.alb_controller_service_account
    namespace = local.alb_controller_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = local.alb_controller_namespace

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  depends_on = [aws_iam_role_policy_attachment.alb_controller]
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  create_namespace = false
}

resource "kubernetes_namespace" "strimzi" {
  metadata {
    name = "kafka-system"
  }
}

resource "helm_release" "strimzi" {
  name       = "strimzi-kafka-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  namespace  = kubernetes_namespace.strimzi.metadata[0].name

  set {
    name  = "watchAnyNamespace"
    value = "true"
  }
}

resource "kubernetes_namespace" "pulseops" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_storage_class" "kafka" {
  metadata {
    name = "gp3-kafka"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

resource "kubernetes_manifest" "kafka_node_pool" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaNodePool"
    metadata = {
      name      = "kafka"
      namespace = kubernetes_namespace.pulseops.metadata[0].name
      labels = {
        "strimzi.io/cluster" = local.kafka_cluster_name
      }
    }
    spec = {
      replicas = 3
      roles    = ["broker", "controller"]
      storage = {
        type        = "persistent-claim"
        size        = "${var.kafka_storage_gb}Gi"
        class       = kubernetes_storage_class.kafka.metadata[0].name
        deleteClaim = false
      }
      template = {
        pod = {
          tolerations = [{
            key      = "dedicated"
            operator = "Equal"
            value    = "kafka"
            effect   = "NoSchedule"
          }]
          nodeSelector = {
            workload = "kafka"
          }
          topologySpreadConstraints = [{
            maxSkew           = 1
            topologyKey       = "topology.kubernetes.io/zone"
            whenUnsatisfiable = "DoNotSchedule"
            labelSelector = {
              matchLabels = {
                "strimzi.io/cluster" = local.kafka_cluster_name
              }
            }
          }]
        }
      }
    }
  }

  depends_on = [helm_release.strimzi]
}

resource "kubernetes_manifest" "kafka" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = local.kafka_cluster_name
      namespace = kubernetes_namespace.pulseops.metadata[0].name
      annotations = {
        "strimzi.io/node-pools" = "enabled"
        "strimzi.io/kraft"      = "enabled"
      }
    }
    spec = {
      kafka = {
        version         = "3.8.0"
        metadataVersion = "3.8-IV0"
        listeners = [{
          name = "plain"
          port = 9092
          type = "internal"
          tls  = false
        }]
        config = {
          "default.replication.factor"               = 3
          "min.insync.replicas"                      = 2
          "offsets.topic.replication.factor"         = 3
          "transaction.state.log.replication.factor" = 3
          "transaction.state.log.min.isr"            = 2
          "auto.create.topics.enable"                = false
        }
      }
      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_node_pool]
}

resource "kubernetes_manifest" "kafka_topics" {
  for_each = {
    "pulseops.url-check-jobs.v1" = {
      partitions   = 12
      retention_ms = "86400000"
    }
    "pulseops.url-check-results.v1" = {
      partitions   = 12
      retention_ms = "604800000"
    }
    "pulseops.url-check-jobs.dlq.v1" = {
      partitions   = 3
      retention_ms = "1209600000"
    }
    "pulseops.url-check-results.dlq.v1" = {
      partitions   = 3
      retention_ms = "1209600000"
    }
  }

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaTopic"
    metadata = {
      name      = each.key
      namespace = kubernetes_namespace.pulseops.metadata[0].name
      labels = {
        "strimzi.io/cluster" = local.kafka_cluster_name
      }
    }
    spec = {
      partitions = each.value.partitions
      replicas   = 3
      config = {
        "retention.ms"        = each.value.retention_ms
        "min.insync.replicas" = 2
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka]
}

