# pigeon-cluster

Scales a fleet of `pigeon-cli` job instances to the number of pending jobs (ADR-0138). Composes one `scaleway/compute-instance` (with `self_delete_on_exit = true`) plus one dedicated `scaleway/iam-application`/`iam-policy`/`iam-api-key` per entry in `var.jobs` -- each job gets its own IAM scope and its own keyring, isolated from every other job in the same cluster (ADR-0144). A job's own API key is the default credential for any `kind = "bucket"` keyring entry that doesn't specify its own, and `job_commands` strings may reference a keyring entry by alias (e.g. `"${keyring.fastmail.alias}:"`). An instance tears itself down the moment its job finishes, success or failure; remove its entry from `var.jobs` and re-apply to reconcile Terraform state once that's happened. By default every job instance also shares one cluster-wide Private Network and Public Gateway (ADR-0145) -- job buckets can be reached over Scaleway's private Object Storage endpoint instead of the public one, and no job gets a public IP (ADR-0146) -- but a job can opt out of this entirely with `enable_private_network = false`, becoming a plain, directly-reachable `compute-instance` with no dependency on the cluster's shared networking, or keep its Private Network attachment while also requesting its own public IP with `enable_ipv4 = true` (ADR-0149). The cluster's shared Private Network and Public Gateway can also each be disabled independently of the other, via `cluster_config.enable_private_network`/`enable_public_gateway` (ADR-0149) -- e.g. tear down the Private Network once no job needs it anymore while leaving the Gateway (and its stable IP) running. For debug SSH access, set `cluster_config.enable_bastion = true` to provision a dedicated bastion instance on that same Private Network, reachable via the Public Gateway's PAT rule -- see the `bastion_connect_command` output; a direct public IP on an instance attached to this Private Network doesn't actually work while the Gateway is still pushing its default route (the gateway's own route advertisement takes priority), which is why the bastion doesn't get one either, and `enable_bastion` requires both `enable_private_network` and `enable_public_gateway` to stay `true`. `jobs` is a list, each entry naming its own `job_name` -- internally converted to a job-name-keyed map for stable per-job resource addressing.

## Usage

```hcl
module "pigeon_jobs" {
  source = "https://pigeon.dev/modules/scaleway/pigeon-cluster/v1.0.0"

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

  jobs = [
    {
      job_name = "deduplicate-backblaze-snapshots"
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
    },
    {
      job_name = "import-mega-consolidation"
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
    },
  ]
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_config"></a> [cluster\_config](#input\_cluster\_config) | Settings shared by every job instance in this cluster, including a default keyring and permission grant every job inherits unless overridden. | <pre>object({<br/>    name_prefix = string<br/>    project_id  = string<br/>    cockpit = optional(object({<br/>      metrics_push_url = string<br/>      logs_push_url    = string<br/>      token_secret     = string<br/>      scrape_port      = optional(number, 9091)<br/>    }))<br/>    shared_keyring = optional(map(object({<br/>      kind = string<br/><br/>      # kind = "email"<br/>      email                = optional(string)<br/>      provider             = optional(string)<br/>      host                 = optional(string)<br/>      port                 = optional(number)<br/>      max_imap_connections = optional(number)<br/><br/>      # kind = "bucket" -- also generates an rclone.conf remote; access_key_id/secret_key<br/>      # default to the consuming job's own API key when omitted (see `jobs`)<br/>      endpoint             = optional(string)<br/>      bucket               = optional(string)<br/>      access_key_id        = optional(string)<br/>      secret_key           = optional(string)<br/>      encryption_key_alias = optional(string)<br/><br/>      # kind = "encryption-key"<br/>      created_at = optional(string)<br/>    })), {})<br/>    shared_permission_sets = optional(list(string), [])<br/>    # ADR-0146: default false -- no bastion is created. true provisions one<br/>    # debug-SSH instance on the cluster's shared Private Network, reachable<br/>    # only through the shared Public Gateway's PAT rule (see outputs.bastion_connect_command),<br/>    # not via its own public IP -- a direct public IP on an instance attached<br/>    # to this PN doesn't actually work, see cluster.tf's module.bastion comment.<br/>    enable_bastion = optional(bool, false)<br/>    # Scaleway offer type for the cluster's shared Public Gateway (default<br/>    # matches today's hardcoded behavior). Changing this upgrades the<br/>    # existing gateway in place via Scaleway's UpgradeGateway API -- same<br/>    # gateway ID/IP, no job or bastion instance needs to restart or<br/>    # reconnect to benefit. Upgrade-only: Scaleway doesn't support<br/>    # downgrading a gateway back to a smaller tier afterward.<br/>    public_gateway_type = optional(string, "VPC-GW-S")<br/>    # ADR-0149: independent kill switches for the cluster's two shared<br/>    # networking resources. Both default true (today's unconditional<br/>    # behavior). Set enable_private_network = false once no remaining job<br/>    # needs the shared Private Network (e.g. every job has completed or<br/>    # opted out via jobs[*].enable_private_network) to tear it down -- the<br/>    # Public Gateway can keep running untouched (e.g. still fronting the<br/>    # bastion's PAT rule) since the two are independent. Set<br/>    # enable_public_gateway = false to tear down the metered gateway once<br/>    # nothing needs internet/private-Object-Storage egress, leaving the<br/>    # (free) Private Network provisioned for later. enable_bastion requires<br/>    # both to be true (see validation below) -- the bastion is reachable<br/>    # only via the gateway's PAT rule onto the shared PN.<br/>    enable_private_network = optional(bool, true)<br/>    enable_public_gateway  = optional(bool, true)<br/>  })</pre> | n/a | yes |
| <a name="input_jobs"></a> [jobs](#input\_jobs) | Jobs to run right now, each entry naming its own job\_name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra\_permission\_sets plus cluster\_config.shared\_permission\_sets, and its own keyring (merged with cluster\_config.shared\_keyring, job-specific entries winning on alias collision) -- never shared with another job in this same cluster. Every kind = "bucket" keyring entry that omits access\_key\_id/secret\_key defaults to this job's own API key (ADR-0144); job\_commands strings may reference an entry by alias, e.g. "--source '${keyring.fastmail.alias}:'" (use ${keyring["my-alias"].alias} bracket syntax for a hyphenated alias). Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality. block\_volume\_iops defaults to 15000, matching block-volume's and compute-instance's own defaults. By default every job shares the cluster's Private Network/Public Gateway and gets no public IP (ADR-0146) -- use cluster\_config.enable\_bastion for debug SSH access, or set enable\_private\_network = false to opt this job out of the shared networking entirely (ADR-0149), or enable\_ipv4 = true for a job that keeps its Private Network attachment but also wants its own public IP. enable\_transcoding = true (ADR-0150, renamed by ADR-0151) installs a general-purpose ffmpeg build on this job's instance, for job\_commands that run pigeon-cli transform -- any input file type, not just heic. | <pre>list(object({<br/>    job_name          = string<br/>    job_commands      = list(string)<br/>    instance_type     = optional(string, "STARDUST1-S")<br/>    block_volume_size = optional(number)<br/>    block_volume_iops = optional(number, 15000)<br/>    keyring = optional(map(object({<br/>      kind = string<br/><br/>      # kind = "email"<br/>      email                = optional(string)<br/>      provider             = optional(string)<br/>      host                 = optional(string)<br/>      port                 = optional(number)<br/>      max_imap_connections = optional(number)<br/><br/>      # kind = "bucket" -- also generates an rclone.conf remote<br/>      endpoint             = optional(string)<br/>      bucket               = optional(string)<br/>      access_key_id        = optional(string)<br/>      secret_key           = optional(string)<br/>      encryption_key_alias = optional(string)<br/><br/>      # kind = "encryption-key"<br/>      created_at = optional(string)<br/>    })), {})<br/>    extra_permission_sets = optional(list(string), [])<br/>    # ADR-0149: default true preserves today's behavior -- this job attaches<br/>    # to the cluster's shared Private Network. false makes this job a plain,<br/>    # undecorated compute-instance call: no private NIC, no dependency on<br/>    # the cluster's shared PN/Gateway at all. Requires cluster_config's own<br/>    # enable_private_network/enable_public_gateway to still be true for this<br/>    # job -- if the cluster has disabled its shared PN while this stays<br/>    # true, compute-instance's own validation will fail the plan<br/>    # ("private_network_id must be set when enable_private_network is<br/>    # true"), since pigeon-cluster doesn't duplicate that check itself.<br/>    enable_private_network = optional(bool, true)<br/>    # ADR-0149: reinstates the per-job public-IP override ADR-0146 removed.<br/>    # When enable_private_network is true, this job gets enable_ipv4's exact<br/>    # value (default false, matching prior behavior) -- note ADR-0146 found<br/>    # a direct public IP on a PN-attached instance can't be reached by<br/>    # inbound SSH while the cluster's gateway is still pushing a default<br/>    # route (Scaleway's own documented behavior); this remains true here,<br/>    # so set this only once cluster_config.enable_public_gateway is false,<br/>    # or when only outbound use of the IP is needed. When<br/>    # enable_private_network is false, this job always gets a public IP<br/>    # regardless of this field's value -- it has no other network path.<br/>    enable_ipv4 = optional(bool, false)<br/>    # ADR-0150, renamed by ADR-0151: passed straight through to this job's<br/>    # own compute-instance call. false (default) preserves today's behavior<br/>    # -- no ffmpeg installed. true installs a general-purpose ffmpeg build,<br/>    # for jobs whose job_commands run `pigeon-cli transform` (of any input<br/>    # file type, not just heic).<br/>    enable_transcoding = optional(bool, false)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bastion_connect_command"></a> [bastion\_connect\_command](#output\_bastion\_connect\_command) | SSH command to reach the cluster's bastion through the shared Public Gateway's PAT rule (null when cluster\_config.enable\_bastion is false) |
| <a name="output_job_ids"></a> [job\_ids](#output\_job\_ids) | Instance ID per job, keyed by job name (null for any job whose instance has already self-deleted) |
<!-- END_TF_DOCS -->
