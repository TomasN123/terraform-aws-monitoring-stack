provider "aws" {
  region  = var.region
}
resource "aws_instance" "Monitoring" {
ami = var.ami
instance_type = var.instance_type
key_name = aws_key_pair.deployer.key_name
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


resource "null_resource" "deploy" {
depends_on = [ aws_instance.Monitoring, aws_eip.monitoring-eip ]


connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file(pathexpand("~/.ssh/aws-monitoring"))
    host = aws_eip.monitoring-eip.public_ip
  }

provisioner "file" {
  source      = "./docker-compose.yml"
  destination = "/home/ec2-user/docker-compose.yml"
}

provisioner "file" {
  source      = "./prometheus.yml"
  destination = "/home/ec2-user/prometheus.yml"
}

provisioner "remote-exec" {
  inline = [
    "echo 'Waiting for Dockee'",
    "while ! sudo docker info > /dev/null 2>&1; do sleep 5; done",
    "echo 'Docker is ready!'",
    "sudo docker-compose -f /home/ec2-user/docker-compose.yml up -d"
   ]
  
  
}  
}


resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file(pathexpand("~/.ssh/aws-monitoring.pub"))
}

resource "aws_security_group" "monitoring-sg" {
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    from_port        = 9090  // Prometheus
    to_port          = 9090
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    from_port        = 22   //SSH
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    from_port        = 9100    //Node Exporter
    to_port          = 9100
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    from_port        = 3000   //Grafana
    to_port          = 3000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_eip" "monitoring-eip" {
  instance = aws_instance.Monitoring.id
  domain   = "vpc"
}

