provider "aws" {
  region = var.region
}

resource "aws_instance" "Monitoring" {
  ami                    = var.ami
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.monitoring-sg.id]

  user_data = <<EOF
#! /bin/bash
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
EOF

  tags = {
    Name = "Terraform-EC2"
  }
}

resource "aws_ebs_volume" "volumeEBS" {
  availability_zone = aws_instance.Monitoring.availability_zone
  size              = 20
  type              = "gp2"
  tags = {
    Name = "EBSVolume"
  }
}

resource "aws_volume_attachment" "EBSattachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.volumeEBS.id
  instance_id = aws_instance.Monitoring.id
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "monitoring-sg" {
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
/*  ingress {
    from_port        = 9090 // Prometheus
    to_port          = 9090
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 9100 // Node Exporter
    to_port          = 9100
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
    ingress {
    from_port        = 3000 // Grafana
    to_port          = 3000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
*/
  ingress {
    from_port        = 22 // SSH
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 80 // Nginx
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443 // HTTPS
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

resource "aws_eip" "monitoring-eip" {
  instance = aws_instance.Monitoring.id
  domain   = "vpc"
}

data "aws_route53_zone" "link" {
  name = var.domain_name
}

resource "aws_route53_record" "link_record" {
  zone_id = data.aws_route53_zone.link.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = "300"
  records = [aws_eip.monitoring-eip.public_ip]
}

resource "null_resource" "deploy" {
  depends_on = [aws_instance.Monitoring, aws_eip.monitoring-eip, aws_volume_attachment.EBSattachment]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key)
    host        = aws_eip.monitoring-eip.public_ip
  }

  provisioner "file" {
    source      = "./docker/docker-compose.yml"
    destination = "/home/ec2-user/docker-compose.yml"
  }
  provisioner "file" {
    source      = "./docker/prometheus.yml"
    destination = "/home/ec2-user/prometheus.yml"
  }
  provisioner "file" {
    source      = "./docker/grafana-datasource.yml"
    destination = "/home/ec2-user/grafana-datasource.yml"
  }
  provisioner "file" {
    source      = "./docker/grafana-dashboard.yml"
    destination = "/home/ec2-user/grafana-dashboard.yml"
  }
  provisioner "file" {
    source      = "./docker/node-exporter-dashboard.json"
    destination = "/home/ec2-user/node-exporter-dashboard.json"
  }
  provisioner "file" {
    source      = "./docker/nginx.conf"
    destination = "/home/ec2-user/nginx.conf"
  }
  provisioner "file" {
    source      = "./docker/init-letsencrypt.sh"
    destination = "/home/ec2-user/init-letsencrypt.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -b /dev/xvdf ] && [ ! -b /dev/sdf ]; do sleep 2; done",
      "DEVICE=$([ -b /dev/xvdf ] && echo /dev/xvdf || echo /dev/sdf)",
      "sudo mkfs -t xfs $DEVICE",
      "sudo mkdir -p /data",
      "sudo mount $DEVICE /data",
      "sudo mkdir -p /data/prometheus /data/grafana",
      "sudo chown 65534:65534 /data/prometheus",
      "sudo chown 472:472 /data/grafana",
      "echo 'Waiting for Docker'",
      "while ! sudo docker info > /dev/null 2>&1; do sleep 5; done",
      "echo 'Waiting for Docker Compose'",
      "while ! sudo docker-compose version > /dev/null 2>&1; do sleep 5; done",
      "echo 'Docker is ready!'",
      "chmod +x /home/ec2-user/init-letsencrypt.sh",
      "cd /home/ec2-user && sudo ./init-letsencrypt.sh",
      "sudo docker-compose -f /home/ec2-user/docker-compose.yml up -d"
    ]
  }
}

resource "aws_sns_topic" "emailAlert" {
  name = "email-alert"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.emailAlert.arn
  protocol  = "email"
  endpoint  = var.email
}

resource "aws_cloudwatch_metric_alarm" "CPU-peak" {
  alarm_name                = "terraform-alarm-cpu"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 120
  statistic                 = "Average"
  threshold                 = 80
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  dimensions = {
    InstanceId = aws_instance.Monitoring.id
  }
  alarm_actions = [aws_sns_topic.emailAlert.arn]

}