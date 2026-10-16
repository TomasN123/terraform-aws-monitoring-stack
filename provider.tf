terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "tomas-terraform-state-2026"
    key    = "monitoring/terraform.tfstate"
    region = "eu-north-1"

  }
}

