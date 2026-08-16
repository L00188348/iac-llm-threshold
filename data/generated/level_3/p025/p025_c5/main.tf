variable "instance_configs" {
  type = map(object({
    type = string
  }))

  default = {
    dev = {
      type = "t3.micro"
    }
    staging = {
      type = "t3.small"
    }
    prod = {
      type = "t3.medium"
    }
  }
}

resource "aws_instance" "this" {
  for_each      = var.instance_configs
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = each.value.type
}

output "instance_ids" {
  value = {
    for k, inst in aws_instance.this : k => inst.id
  }
}