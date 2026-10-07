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

## Outputs

| Name | Description |
|------|-------------|
<!-- END_TF_DOCS -->
