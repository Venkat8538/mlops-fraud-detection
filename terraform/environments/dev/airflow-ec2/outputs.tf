output "airflow_public_ip" {
  description = "Airflow EC2 public IP — add to GitHub Secret AIRFLOW_EC2_HOST"
  value       = aws_eip.airflow.public_ip
}

output "airflow_ui_url" {
  description = "Airflow web UI URL"
  value       = "http://${aws_eip.airflow.public_ip}:8080"
}

output "ssh_command" {
  description = "SSH into Airflow EC2"
  value       = "ssh -i ~/.ssh/id_ed25519 ec2-user@${aws_eip.airflow.public_ip}"
}
