data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "langfuse-network"
}
