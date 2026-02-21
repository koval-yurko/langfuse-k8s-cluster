resource "random_password" "nextauth_secret" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+."
}

resource "random_password" "salt" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+."
}

resource "random_id" "encryption_key" {
  byte_length = 32
}
