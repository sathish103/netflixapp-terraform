locals {
  region = "ap-south-1"
  name   = "netflix-cluster"
  vpc_cidr = "10.0.0.0/16"
  azs      = ["ap-south-1a", "ap-south-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  intra_subnets   = ["10.0.5.0/24", "10.0.6.0/24"]
  tags = {
    Example = local.name
  }
}



terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.33.0"  # known stable version
    }
  }
}



provider "aws" {
  region = "ap-south-1"
}
