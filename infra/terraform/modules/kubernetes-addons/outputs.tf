output "kafka_bootstrap_service" {
  value = "${local.kafka_cluster_name}-kafka-bootstrap.${var.namespace}.svc.cluster.local:9092"
}

