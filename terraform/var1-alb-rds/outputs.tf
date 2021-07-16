/*output "epm-efs-mt-1-dns-name" {
  value = aws_efs_mount_target.epm-efs-mt-1.mount_target_dns_name
}

output "epm-efs-mt-2-dns-name" {
  value = aws_efs_mount_target.epm-efs-mt-2.mount_target_dns_name
}

output "db-instance-endpoint" {
  value = module.db.db_instance_endpoint
}*/

output "epm-srv-web-1-dns-name" {
  value = aws_instance.epm-srv-web-1.public_dns
}

output "epm-srv-web-2-dns-name" {
  value = aws_instance.epm-srv-web-2.public_dns
}

output "Please_copy_and_past_this_link_into_your_browser_to_access_wordpress" {
  value = aws_lb.epm-app-lb.dns_name
}