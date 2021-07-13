output "epm-efs-mt-1-dns-name" {
  value = aws_efs_mount_target.epm-efs-mt-1.mount_target_dns_name
}

output "epm-efs-mt-2-dns-name" {
  value = aws_efs_mount_target.epm-efs-mt-2.mount_target_dns_name
}

output "epm-srv-web-1-dns-name" {
  value = aws_instance.epm-srv-web-1.public_dns
}

output "epm-srv-web-2-dns-name" {
  value = aws_instance.epm-srv-web-2.public_dns
}

output "db-instance-endpoint" {
  value = module.db.db_instance_endpoint
}

output "webloadbalancer-url" {
  description = "Please copy and past this link in the browser to access the webserver"
  value = aws_lb.epm-app-lb.dns_name
}