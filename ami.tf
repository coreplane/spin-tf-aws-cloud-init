# Automatically query for the latest Amazon Linux AMI ID in the default region

# Note: Our AWS instances have ignore_changes set for "ami",
# because changing them all over at once in an update would be disruptive.
# When updating kernels, taint instances manually one by one to do a slow roll-out.
  
data "aws_ami" "amazon_linux" {
  # past values:
  # us-east-1 = "ami-a4827dc9" # Amazon Linux AMI 2016.03.2 HVM (SSD) EBS-Backed 64-bit
  # us-east-1 = "ami-97785bed" # Amazon Linux AMI 2017.09.1 HVM (SSD) EBS-Backed 64-bit
  most_recent = true
  filter {
    name = "name"
    values = ["amzn-ami-*-x86_64-gp2"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name = "owner-alias"
    values = ["amazon"]
  }
}

output "current_amazon_linux_ami_id" {
  value = "${data.aws_ami.amazon_linux.id}"
}
