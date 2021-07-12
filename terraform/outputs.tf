output "epm-efs-mt-1-dns-name" {
  value = aws_efs_mount_target.epm-efs-mt-1.mount_target_dns_name
}

output "epm-efs-mt-2-dns-name" {
  value = aws_efs_mount_target.epm-efs-mt-2.mount_target_dns_name
}

output "webloadbalancer-url" {
    value = aws_lb.app-lb.dns_name
    description = "Please copy and past this link in the browser to access the webserver"
}