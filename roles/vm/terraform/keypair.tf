resource "aws_key_pair" "deployer" {
  key_name   = var.aws["key_pair_name"]
  public_key = var.aws["key_pair_public_key"]
}
