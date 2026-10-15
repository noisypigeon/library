# This module moved here from noisypigeon/pigeon.dev's templates/terraform/ by
# LIB-0002, and from noisypigeon/noisypigeon before that (ADR-0154). Consumers
# do not see any of that: they pin
# pigeon.dev/modules/scaleway/project/vX.Y.Z, which is a public interface
# deliberately decoupled from wherever the source lives (ADR-0109/0110), and is
# why three relocations have not broken a single `source =`.
resource "scaleway_account_project" "project" {
  name            = var.name
  description     = var.description
  organization_id = var.organization_id
}

# count, not for_each, because ssh_key is a single optional object rather than a
# collection: the address is therefore always [0] when set. Toggling the input
# between null and a value is a create/destroy of that address, not a move, so
# flipping it rotates the registered key rather than renaming it in place.
resource "scaleway_iam_ssh_key" "key" {
  count      = var.ssh_key != null ? 1 : 0
  name       = var.ssh_key.alias
  public_key = var.ssh_key.public_key
  project_id = scaleway_account_project.project.id
}
