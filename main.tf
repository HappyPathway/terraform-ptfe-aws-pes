#------------------------------------------------------------------------------
# production external-services ptfe resources
#------------------------------------------------------------------------------

locals {
  namespace = "${var.namespace}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "random_pet" "replicated-pwd" {
  length = 2
}

data "template_file" "user_data" {
  template = "${file("${path.module}/user-data.tpl")}"

  vars {
    hostname       = "${var.namespace}.hashidemos.io"
    replicated_pwd = "${random_pet.replicated-pwd.id}"
  }
}

resource "aws_instance" "pes" {
  count                  = 2
  ami                    = "${data.aws_ami.ubuntu.id}"
  instance_type          = "${var.aws_instance_type}"
  subnet_id              = "${element(var.subnet_ids, count.index)}"
  vpc_security_group_ids = ["${var.vpc_security_group_ids}"]
  key_name               = "${var.ssh_key_name}"
  user_data              = "${data.template_file.user_data.rendered}"
  iam_instance_profile   = "${aws_iam_instance_profile.ptfe.name}"

  root_block_device {
    volume_size = 80
    volume_type = "gp2"
  }

  tags {
    Name  = "${local.namespace}-instance-${count.index+1}"
    owner = "${var.owner}"
    TTL   = "${var.ttl}"
  }
}

resource "aws_eip" "pes" {
  instance = "${aws_instance.pes.0.id}"
  vpc      = true
}

data "aws_route53_zone" "selected" {
  name         = "${var.route53_zone}"
  private_zone = "${var.private_route53_zone}"
}

resource "aws_route53_record" "pes" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "${local.namespace}.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_eip.pes.public_ip}"]
}

resource "aws_s3_bucket" "pes" {
  bucket = "${local.namespace}-ptfe-blobstorage"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags {
    Name = "${local.namespace}-ptfe-blobstorage"
  }
}

resource "aws_db_instance" "pes" {
  allocated_storage         = 10
  engine                    = "postgres"
  engine_version            = "9.4"
  instance_class            = "db.t2.medium"
  identifier                = "${local.namespace}-ptfe-db"
  name                      = "ptfe"
  storage_type              = "gp2"
  username                  = "ptfe"
  password                  = "${var.database_pwd}"
  db_subnet_group_name      = "${var.db_subnet_group_name}"
  vpc_security_group_ids    = ["${var.vpc_security_group_ids}"]
  final_snapshot_identifier = "${local.namespace}-ptfe-db-instance-final-snapshot"
}

#------------------------------------------------------------------------------
# iam for ec2 to s3
#------------------------------------------------------------------------------

resource "aws_iam_role" "ptfe" {
  name = "${local.namespace}-iam_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ptfe" {
  name = "${local.namespace}-iam_instance_profile"
  role = "${aws_iam_role.ptfe.name}"
}

data "aws_iam_policy_document" "ptfe" {
  statement {
    sid    = "AllowS3"
    effect = "Allow"

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.pes.id}",
      "arn:aws:s3:::${aws_s3_bucket.pes.id}/*",
    ]

    actions = [
      "s3:*",
    ]
  }
}

resource "aws_iam_role_policy" "ptfe" {
  name   = "${local.namespace}-iam_role_policy"
  role   = "${aws_iam_role.ptfe.name}"
  policy = "${data.aws_iam_policy_document.ptfe.json}"
}
