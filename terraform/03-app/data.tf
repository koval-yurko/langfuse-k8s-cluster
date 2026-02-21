data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "langfuse-network"
}

data "tfe_outputs" "deps" {
  organization = var.tfc_organization
  workspace    = "langfuse-deps"
}
