# this module contains the bare minimum resources to set up AWS EC2
# instances with Puppet and access to EnvKey secrets.

variable "region" {}
variable "sitedomain" {}
variable "sitename" {}
variable "enable_backups" { default = false }
variable "puppet_repo" { default = "github.com/spinpunch/battlehouse-puppet" }
variable "puppet_branch" { default = "master" }
variable "secrets_bucket" {
  default = ""
  description = "Name of S3 bucket to store secret environment variables (alternative to envkey). Assumed to exist already."
}
variable "cron_mail_sns_topic" {
  description = "ARN of an SNS topic that should receive log messages from cron jobs. This is also used to receive CloudWatch alerts."
}
variable "envkey" {
  description = "Envkey to use for these servers"
}
#variable "envkey_encryption_key_id" { default = "" }
variable "envkey_sub" {
  default = ""
  description = "If more than one envkey is in use (meaning aws-cloud-init is instantiated more than once), then set a unique envkey_sub (suffix) to distinguish between them. Otherwise, the envkey will be named as sitename."
}

locals {
  # use sitename for keyname, if one is not specified
  keyname = "${var.envkey_sub != "" ? "${var.sitename}-${var.envkey_sub}" : "${var.sitename}"}"
  envkey_secrets_s3_uri = "s3://${var.secrets_bucket}/${local.keyname}-envkey.env"
}

# Store the EnvKey secret as an AWS SSM parameter, so that EC2 instances
# can grab it at boot time, without keeping it in the plaintext cloud-config instance data.
resource "aws_ssm_parameter" "envkey" {
  name = "/${local.keyname}/envkey" # note: duplicated below to avoid triggering dependency creation
  type = "SecureString"
  value = "${var.envkey}"
#  key_id = "${var.envkey_encryption_key_id}"
  overwrite = true
#  tags = {
#    Terraform = "true"
#  }
}

# Backup to EnvKey - store the same env vars in a file in S3
resource "aws_s3_bucket_object" "envkey_env" {
  count = "${var.secrets_bucket != "" ? 1 : 0}"
  bucket = "${var.secrets_bucket}"
  key = "${local.keyname}-envkey.env"
  source = "envkey.env"
  etag = "${md5(file(var.envkey_sub != "" ? "${var.envkey_sub}-envkey.env" : "envkey.env"))}"
}

# cloud-init boilerplate for all EC2 instances
data "template_file" "cloud_config" {
  template = "${file("${path.module}/cloud-config.yaml")}"
  vars = {
    terraform_cron_mail_sns_topic = "${var.cron_mail_sns_topic}"
    region = "${var.region}"
    sitename = "${var.sitename}"
    sitedomain = "${var.sitedomain}"
    enable_backups = "${var.enable_backups}"
    puppet_repo = "${var.puppet_repo}"
    puppet_branch = "${var.puppet_branch}"
    envkey_ssm_parameter_name = "/${local.keyname}/envkey" # duplicated above to avoid creating a dependency on the resource
    envkey_secrets_s3_uri = "${var.secrets_bucket != "" ? local.envkey_secrets_s3_uri : ""}"
    logdna_send_py_gz_b64 = "${base64gzip(file("${path.module}/logdna-send.py"))}"
  }
}

data "template_file" "cloud_config_tail" {
  template = "${file("${path.module}/cloud-config-tail.yaml")}"
}

output "cloud_config_head" {
  value = "${data.template_file.cloud_config.rendered}"
}
output "cloud_config_tail" {
  value = "${data.template_file.cloud_config_tail.rendered}"
}

# IAM role boilerplate for all EC2 instance roles
locals {
  ec2_iam_role_base = <<EOF
    { "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": ["${var.cron_mail_sns_topic}"]
    },
    { "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": ["*"]
    },
    { "Effect": "Allow",
      "Action": ["ec2:DescribeTags"],
      "Resource": ["*"]
    },
    { "Effect": "Allow",
      "Action": ["ssm:GetParameter"],
      "Resource": ["${aws_ssm_parameter.envkey.arn}"]
    },
    { "Effect": "Allow",
      "Action": ["cloudfront:ListDistributions"],
      "Resource": ["*"]
    },
    { "Effect": "Allow",
      "Action": ["s3:ListAllMyBuckets","s3:GetBucketLocation"],
      "Resource": ["*"]
    }
EOF

  # this part is only used if secrets_bucket is active
  ec2_iam_role_secrets_s3 = <<EOF
   { "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::${var.secrets_bucket}/${local.keyname}-envkey.env"]
   }
EOF
}

output "ec2_iam_role_fragment" {
  value = "${local.ec2_iam_role_base}${var.secrets_bucket != "" ? ",\n${local.ec2_iam_role_secrets_s3}" : ""}"
}
