# pigeon-cluster

Scales a fleet of `pigeon-cli` job instances to the number of pending jobs (ADR-0138). Composes one `scaleway/compute-instance` (with `self_delete_on_exit = true`) plus one dedicated `scaleway/iam-application`/`iam-policy`/`iam-api-key` per entry in `var.jobs` -- each job gets its own IAM scope and its own keyring, isolated from every other job in the same cluster (ADR-0144). A job's own API key is the default credential for any `kind = "bucket"` keyring entry that doesn't specify its own, and `job_commands` strings may reference a keyring entry by alias (e.g. `"${keyring.fastmail.alias}:"`). An instance tears itself down the moment its job finishes, success or failure; remove its entry from `var.jobs` and re-apply to reconcile Terraform state once that's happened.

## Usage

```hcl
module "pigeon_jobs" {
  source = "https://pigeon.dev/modules/scaleway/pigeon-cluster/v0.2.0"

  cluster_config = {
    name_prefix = "pigeon-cli"
    project_id  = local.scaleway_project_id
    cockpit = {
      metrics_push_url = local.pigeon_cockpit_metrics_push_url
      logs_push_url    = local.pigeon_cockpit_logs_push_url
      token_secret     = local.pigeon_cockpit_token_secret
    }
    # Every job below gets this bucket for free, with no per-job declaration.
    shared_keyring = {
      reports = {
        kind     = "bucket"
        endpoint = "https://s3.fr-par.scw.cloud"
        bucket   = "pigeon-cli-vmqjtz-reports"
        # access_key_id/secret_key omitted -- each job defaults to its own API key
      }
    }
    shared_permission_sets = ["ObjectStorageFullAccess"]
  }

  jobs = {
    deduplicate-backblaze-snapshots = {
      job_commands = [
        "cd pigeon-cli",
        "mise run pigeon-release job run deduplicate --source-bucket '${keyring.source.alias}:' --report-bucket '${keyring.reports.alias}:' --concurrency 8 --yes",
      ]
      keyring = {
        source = {
          kind     = "bucket"
          endpoint = "https://s3.fr-par.scw.cloud"
          bucket   = "backblaze-computer-snapshots"
          # this job reaches "source" under a pre-existing, shared auth stack
          # instead of defaulting to its own freshly-minted job key
          access_key_id = local.source_bucket_access_key_id
          secret_key    = local.source_bucket_secret_key
        }
      }
    }

    import-mega-consolidation = {
      job_commands = [
        "cd pigeon-cli",
        "mise run pigeon-release job run rclone-import --remote '${keyring.mega.alias}:' --report-bucket '${keyring.reports.alias}:' --concurrency 4 --yes",
      ]
      keyring = {
        mega = {
          kind     = "bucket"
          endpoint = "https://s3.fr-par.scw.cloud"
          bucket   = "deduplicate-p7d0kd-backblaze-mega-consolidation"
          # access_key_id/secret_key omitted -- defaults to this job's own API key
        }
      }
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_config"></a> [cluster\_config](#input\_cluster\_config) | Settings shared by every job instance in this cluster, including a default keyring and permission grant every job inherits unless overridden. | <pre>object({<br/>    name_prefix = string<br/>    project_id  = string<br/>    cockpit = optional(object({<br/>      metrics_push_url = string<br/>      logs_push_url    = string<br/>      token_secret     = string<br/>      scrape_port      = optional(number, 9091)<br/>    }))<br/>    shared_keyring = optional(map(object({<br/>      kind = string<br/><br/>      # kind = "email"<br/>      email                = optional(string)<br/>      provider             = optional(string)<br/>      host                 = optional(string)<br/>      port                 = optional(number)<br/>      max_imap_connections = optional(number)<br/><br/>      # kind = "bucket" -- also generates an rclone.conf remote; access_key_id/secret_key<br/>      # default to the consuming job's own API key when omitted (see `jobs`)<br/>      endpoint             = optional(string)<br/>      bucket               = optional(string)<br/>      access_key_id        = optional(string)<br/>      secret_key           = optional(string)<br/>      encryption_key_alias = optional(string)<br/><br/>      # kind = "encryption-key"<br/>      created_at = optional(string)<br/>    })), {})<br/>    shared_permission_sets = optional(list(string), [])<br/>  })</pre> | n/a | yes |
| <a name="input_jobs"></a> [jobs](#input\_jobs) | Jobs to run right now, keyed by job name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra\_permission\_sets plus cluster\_config.shared\_permission\_sets, and its own keyring (merged with cluster\_config.shared\_keyring, job-specific entries winning on alias collision) -- never shared with another job in this same cluster. Every kind = "bucket" keyring entry that omits access\_key\_id/secret\_key defaults to this job's own API key (ADR-0144); job\_commands strings may reference an entry by alias, e.g. "--source '${keyring.fastmail.alias}:'" (use ${keyring["my-alias"].alias} bracket syntax for a hyphenated alias). Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality. | <pre>map(object({<br/>    job_commands      = list(string)<br/>    instance_type     = optional(string, "STARDUST1-S")<br/>    block_volume_size = optional(number)<br/>    keyring = optional(map(object({<br/>      kind = string<br/><br/>      # kind = "email"<br/>      email                = optional(string)<br/>      provider             = optional(string)<br/>      host                 = optional(string)<br/>      port                 = optional(number)<br/>      max_imap_connections = optional(number)<br/><br/>      # kind = "bucket" -- also generates an rclone.conf remote<br/>      endpoint             = optional(string)<br/>      bucket               = optional(string)<br/>      access_key_id        = optional(string)<br/>      secret_key           = optional(string)<br/>      encryption_key_alias = optional(string)<br/><br/>      # kind = "encryption-key"<br/>      created_at = optional(string)<br/>    })), {})<br/>    extra_permission_sets = optional(list(string), [])<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_job_ids"></a> [job\_ids](#output\_job\_ids) | Instance ID per job, keyed by job name (null for any job whose instance has already self-deleted) |
<!-- END_TF_DOCS -->
