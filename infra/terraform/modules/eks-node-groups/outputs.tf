output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}
