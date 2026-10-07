# ADR-0138: one IAM application + one self-deleting compute-instance per job,
# so each job's blast radius is its own grants/keyring, never shared with a
# sibling job in the same cluster. Pinned to released tags per ADR-0121.
module "job_application" {
  for_each = var.jobs
  source   = "https://pigeon.dev/modules/scaleway/iam-application/v0.1.0"
  name     = "${var.cluster_config.name_prefix}-${each.key}"
}

module "job" {
  for_each    = var.jobs
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v5.4.0"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = each.key

  self_delete_on_exit = true
  keyring             = each.value.keyring

  instance_config = {
    type    = each.value.instance_type
    cockpit = var.cluster_config.cockpit
    block_volume = each.value.block_volume_size == null ? null : {
      size       = each.value.block_volume_size
      project_id = var.cluster_config.project_id
    }
    post_provision_commands = each.value.job_commands
  }

  iam_config = {
    application_id          = module.job_application[each.key].id
    project_ids             = [var.cluster_config.project_id]
    project_permission_sets = each.value.extra_permission_sets
  }
}
