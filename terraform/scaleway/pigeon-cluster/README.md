# pigeon-cluster

Scales a fleet of `pigeon-cli` job instances to the number of pending jobs (ADR-0138). Composes one `scaleway/compute-instance` (with `self_delete_on_exit = true`) plus one dedicated `scaleway/iam-application` per entry in `var.jobs` -- each job gets its own IAM scope and its own keyring, isolated from every other job in the same cluster. An instance tears itself down the moment its job finishes, success or failure; remove its entry from `var.jobs` and re-apply to reconcile Terraform state once that's happened.

## Usage

```hcl
module "pigeon_jobs" {
  source = "https://pigeon.dev/modules/scaleway/pigeon-cluster/v0.1.0"

  cluster_config = {
    name_prefix = "pigeon-cli"
    project_id  = local.scaleway_project_id
    cockpit = {
      metrics_push_url = local.pigeon_cockpit_metrics_push_url
      logs_push_url    = local.pigeon_cockpit_logs_push_url
      token_secret     = local.pigeon_cockpit_token_secret
    }
  }

  jobs = {
    deduplicate-backblaze-snapshots = {
      job_commands = [
        "cd pigeon-cli",
        "mise run pigeon-release job run deduplicate --source-bucket source: --concurrency 8 --yes",
      ]
      extra_permission_sets = ["ObjectStorageFullAccess"]
      keyring = [
        {
          kind          = "bucket"
          alias         = "source"
          endpoint      = "https://s3.fr-par.scw.cloud"
          bucket        = "backblaze-computer-snapshots"
          access_key_id = local.source_bucket_access_key_id
          secret_key    = local.source_bucket_secret_key
        },
      ]
    }

    import-mega-consolidation = {
      job_commands = [
        "cd pigeon-cli",
        "mise run pigeon-release job run rclone-import --remote mega: --concurrency 4 --yes",
      ]
      extra_permission_sets = []
      keyring               = []
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_config"></a> [cluster\_config](#input\_cluster\_config) | Settings shared by every job instance in this cluster. | <pre>object({<br/>    name_prefix = string<br/>    project_id  = string<br/>    cockpit = optional(object({<br/>      metrics_push_url = string<br/>      logs_push_url    = string<br/>      token_secret     = string<br/>      scrape_port      = optional(number, 9091)<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_jobs"></a> [jobs](#input\_jobs) | Jobs to run right now, keyed by job name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra\_permission\_sets plus whatever self-deletion needs, and its own keyring -- never shared with another job in this same cluster. Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality. | <pre>map(object({<br/>    job_commands      = list(string)<br/>    instance_type     = optional(string, "STARDUST1-S")<br/>    block_volume_size = optional(number)<br/>    keyring = optional(list(object({<br/>      kind  = string<br/>      alias = string<br/><br/>      # kind = "email"<br/>      email                = optional(string)<br/>      provider             = optional(string)<br/>      host                 = optional(string)<br/>      port                 = optional(number)<br/>      max_imap_connections = optional(number)<br/><br/>      # kind = "bucket" -- also generates an rclone.conf remote<br/>      endpoint             = optional(string)<br/>      bucket               = optional(string)<br/>      access_key_id        = optional(string)<br/>      secret_key           = optional(string)<br/>      encryption_key_alias = optional(string)<br/><br/>      # kind = "encryption-key"<br/>      created_at = optional(string)<br/>    })), [])<br/>    extra_permission_sets = optional(list(string), [])<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_job_ids"></a> [job\_ids](#output\_job\_ids) | Instance ID per job, keyed by job name (null for any job whose instance has already self-deleted) |
<!-- END_TF_DOCS -->
