terraform {
  required_version = ">= 0.15.3"

  backend "s3" {
    bucket = "button-eks-terraform"
    key    = "state"
    region = "ca-central-1"
  }
}
