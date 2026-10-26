# the library's spoke root.hcl template (LIB-0001 §6, LIB-0003).
#
# GENERATED in a spoke -- do not edit there. .github/scripts/resolve-root-hcl.sh
# copies this file to the spoke's repo root at the version the spoke's
# spoke.hcl pins (root_hcl_version); the spoke commits the copy, and its CI runs
# the same script with --check to fail on any drift. To change it, change it in
# library and bump root_hcl_version. Every leaf under <spoke>/terraform/
# includes it with find_in_parent_folders("root.hcl"). Materialized rather than
# included from the library clone because Terragrunt does not support nested
# includes (DEV-0059), and because a leaf's path_relative_to_include() -- its
# state key -- is relative to this file's own directory, which has to be the
# spoke's root (LIB-0001 invariant 4). Committed rather than gitignored because
# Terragrunt's [main...HEAD] filter plans inside git worktrees, where only
# tracked files exist.
#
# Everything a spoke varies comes from spoke.hcl; everything else is one copy
# here.
#
# Since v2.0.0 (LIB-0005) that includes which providers a leaf gets: spoke.hcl's
# required `providers` map enables and configures each one, optionally scoped
# to leaf path prefixes. There are no per-leaf *_config.hcl files.
#
# Since v2.1.0 (LIB-0007) spoke.hcl may also set `state_backend` to keep state
# in Cloudflare R2 instead of Scaleway Object Storage.
#
# Since v2.2.0 (LIB-0008) a zone leaf -- terraform/cloudflare/<zone>/<module>/
# <instance>/ -- gets its zone as local.cloudflare_zone.
#
# Since v3.0.0 (LIB-0010) every secret has one fixed name, required according
# to what spoke.hcl enables and checked against secrets-schema.json, which
# resolve-root-hcl.sh copies beside this file. spoke.hcl no longer names the
# state bucket's key, and any ENV_<NAME> key becomes local.<name> in every
# leaf. The zone ID left with it: dns-record v1 looks the zone up by apex
# (LIB-0011).
#
# Since v4.0.0 (LIB-0012) those secrets live in one sops file per concern under
# terraform/secrets/ -- terraform.enc, cloudflare.enc, scaleway.enc,
# backblaze.enc and env.enc -- each holding exactly its own keys. A leaf
# decrypts only the files it needs. spoke.hcl's state_backup says whether the
# state is backed up, and an env.enc key <NAME> becomes local.<name>, without
# v3's ENV_ prefix.
#
# Since v4.1.0 (LIB-0014) a provider's entry may set breakglass = { leaves =
# [...] }. Only those leaves decrypt terraform/secrets/<provider>_breakglass.enc,
# a hand-made key Terraform never manages, and read the provider's credentials
# -- and the state backend's, when state_backend is that provider -- from it
# instead. Which keys it stands in for is the schema's `replaces` and
# `replaces_state`.
#
# Since v4.2.0 (LIB-0022) both state backends lock: Terraform's S3-native
# lockfile, a conditional write of <state key>.tflock beside the state.
#
# Since v4.3.0 (LIB-0023) a leaf may also be a workload leaf,
# workloads/<workload>/<provider>/<module>/<instance>/, a stub that
# resolve-workloads.sh generates from workloads/<workload>/values.yaml. For
# one, this file reads its entry in values.yaml, applies the workload's name
# defaults, resolves the module's newest release matching the entry's
# `version` at every plan, and writes the module call into
# workload_generated.tf. Its state sits in the same bucket as every other
# leaf's, keyed by its path.
#
# Since v4.4.0 (LIB-0024) a workload with a project also gets its own
# deployer, scaleway/terraform-deployer-iam/main, and each kind says whose
# credentials it runs with. A `workload` kind's provider signs in with the
# deployer's key, which its stub passes as two sensitive variables, in place
# of the spoke's.
#
# Since v4.5.0 (LIB-0025) a workload may also have a sops-encrypted
# secrets.yaml: secret inputs under the same kind paths, and an `env` map that
# a values.yaml input reaches as { secretRef: NAME }. Secrets reach the module
# as sensitive variables, through this file's inputs, and are never written
# into a generated file.
#
# Since v5.0.0 (LIB-0028) every workload has a project, a deployer and a
# versioned state bucket, scaleway/bucket/state, with or without an entry in
# values.yaml. The three keep their state in the spoke's bucket. Every other
# workload leaf keeps its state in the workload's bucket, at
# workload_state_key, through a remote_state its stub declares and signs in
# to with the workload deployer's key; this file only supplies the key and
# the backend's other settings.
#
# Since v5.1.0 (LIB-0029) a workload may also declare Backblaze buckets and
# API keys. They sign in with the spoke's Backblaze key, keep their state in
# the workload's bucket, and an API key reaches only the buckets its `buckets`
# list names. A workload leaf gets exactly the provider its path names, when
# spoke.hcl's providers map has it; `leaves` scopes hand-written leaves only.
#
# Since v5.2.0 (LIB-0030) a workload may also declare Cloudflare buckets, DNS
# records, rulesets and apex redirects. A root zones.yaml gives each zone one
# owner, a workload or `terraform`; a workload may act only on zones it owns,
# and a hand-written zone leaf only on zones no workload owns.
#
# Since v5.3.0 (LIB-0033) a workload that owns a zone, or declares an R2
# bucket, gets its own Cloudflare token, cloudflare/api-token/deployer, scoped
# to exactly those zones. Its Cloudflare leaves sign in with it, not with the
# spoke's token. Since v5.4.0 that token is minted with the spoke's Cloudflare
# breakglass token, where it has one: Cloudflare won't let a minted token mint.
#
# Since v5.5.0 (LIB-0034) a site workload's features.githubPages implies two
# cloudflare.dnsRecord entries, the Pages CNAMEs at @ and www. An explicit
# entry under either key is merged over its default, field by field.
#
# Since v5.6.0 (LIB-0036) a zone is a unit of its own: zones/<zone>/zone.yaml,
# whose leaves are zones/<zone>/<provider>/<module>/<instance>/. It gets a
# workload's project, deployer, state bucket and Cloudflare token, named with
# `zone-`, and holds the zone's own records, rulesets and redirects. It names
# at most one workload, which may then write records in it too. zones.yaml
# still works beside it, for the migration; a zone in both is refused.
#
# Since v6.0.0 (LIB-0036) a zone.yaml is the only way to register a zone. A
# root zones.yaml is refused, and so is a workload's ruleset or apexRedirect,
# which are a zone's alone, and a hand-written terraform/cloudflare/<zone>/
# leaf. A workload's token no longer gets the redirect group.
#
# Since v6.1.0 (LIB-0037) a workload may live in its zone,
# workloads/<zone>/<workload>/workload.yaml, or with no zone in
# workloads/private/<workload>/.
#
# Since v7.0.0 (LIB-0038) a unit's deployer is three leaves,
# scaleway/iam-application, scaleway/iam-policy and scaleway/iam-api-key, each
# at the instance `deployer`, in place of scaleway/terraform-deployer-iam/main.
# A zone's cloudflare.apexRedirect is a shorthand that expands into
# cloudflare.dnsRecord and cloudflare.ruleset entries; it is no longer a kind.
# The old layout of LIB-0037 §6 is refused: a workloads/<w>/values.yaml, a
# leaf at its depth, a workload's secrets.yaml, zone.yaml's `workload`,
# `features` and a workload's cloudflare.zone.
#
# Since v7.1.0 (LIB-0039) a unit file's content may sit under one key, `zone`
# or `workload`, with its records at `dnsRecords` directly under it, in place
# of cloudflare.dnsRecord. A wrapped zone.yaml may name `services`, each of
# which implies its provider's records. An unwrapped file is read as before.

locals {
  # The spoke's instance values. Missing spoke.hcl is a hard error, which is
  # what we want: guessing a state bucket is how a plan lands in the wrong one.
  spoke = read_terragrunt_config("${get_parent_terragrunt_dir()}/spoke.hcl")

  # The providers this spoke uses, and how (LIB-0005). Required: a spoke.hcl
  # without it is a hard error.
  #
  #   providers = {
  #     cloudflare = {}
  #     scaleway   = { region = "fr-par", zone = "fr-par-1" }
  #     backblaze  = { leaves = ["terraform/backblaze/"] }
  #     grafana    = { leaves = ["terraform/grafana/"] }
  #   }
  #
  # A provider absent from the map is off for every leaf. `leaves`, if given,
  # is a list of path prefixes (relative to this file, ending in "/") and the
  # provider is on only for leaves under one of them; omitted, it is on for
  # every leaf.
  providers         = local.spoke.locals.providers
  known_providers   = ["cloudflare", "scaleway", "backblaze", "grafana"]
  unknown_providers = setsubtract(keys(local.providers), local.known_providers)
  provider_prefixes = flatten([for name, cfg in local.providers : concat(try(cfg.leaves, []), try(cfg.breakglass.leaves, []))])

  leaf = "${path_relative_to_include()}/"
  # A workload leaf gets exactly the provider its path names (LIB-0029 §4):
  # `leaves` can't name workloads/*/<provider>/, and shouldn't turn a
  # provider on for every workload.
  provider_on = {
    for name in local.known_providers : name => contains(keys(local.providers), name) && (
      local.is_workload_leaf ? name == local.leaf_provider : (
        length(try(local.providers[name].leaves, [])) == 0 ||
        anytrue([for prefix in try(local.providers[name].leaves, []) : startswith(local.leaf, prefix)])
      )
    )
  }

  cloudflare_enabled = local.provider_on.cloudflare
  scaleway_enabled   = local.provider_on.scaleway
  backblaze_enabled  = local.provider_on.backblaze
  grafana_enabled    = local.provider_on.grafana

  # Breakglass (LIB-0014): a provider's entry may set
  #
  #   scaleway = { breakglass = { leaves = ["terraform/scaleway/iam-api-key/terraform-deployer/"] } }
  #
  # and a leaf under one of those prefixes, with the provider on, then reads
  # that provider's credentials from <provider>_breakglass.enc. There is no
  # "every leaf" default: a breakglass key every leaf reads is just a second
  # provider key, so leaves is required.
  breakglass_providers = [for name in local.known_providers : name if can(local.providers[name].breakglass)]
  # A workload's own Cloudflare token leaf (LIB-0033 §4) is breakglass too,
  # wherever the spoke has Cloudflare breakglass: Cloudflare won't let a minted
  # token mint, so only the bootstrap token can. Tested on the path alone, so
  # it can't depend on the secrets it decides on.
  is_cf_token_leaf = (
    local.is_workload_leaf &&
    local.leaf_provider == "cloudflare" &&
    local.workload_module == "cloudflare/api-token" &&
    local.workload_instance == "deployer"
  )
  breakglass_on = {
    for name in local.known_providers : name => local.provider_on[name] && contains(local.breakglass_providers, name) && (
      anytrue([for prefix in try(local.providers[name].breakglass.leaves, []) : startswith(local.leaf, prefix)]) ||
      (name == "cloudflare" && local.is_cf_token_leaf)
    )
  }

  # Misconfigurations fail the run rather than silently dropping a provider.
  # Terragrunt has no assert, so each guard reads a file whose name is the
  # message when its condition fails.
  guard_legacy_flags      = anytrue([for k in ["backblaze", "grafana"] : contains(keys(local.spoke.locals), k)]) ? file("spoke.hcl sets backblaze/grafana: root.hcl v2 reads providers only (LIB-0005); move them into the providers map and delete any *_config.hcl") : true
  guard_unknown           = length(local.unknown_providers) > 0 ? file("spoke.hcl providers has unknown keys ${join(", ", local.unknown_providers)}; known: ${join(", ", local.known_providers)}") : true
  guard_prefixes          = alltrue([for p in local.provider_prefixes : endswith(p, "/")]) ? true : file("spoke.hcl providers: every leaves prefix must end in a slash, or it matches sibling paths too")
  guard_backend           = contains(local.known_state_backend, local.state_backend) ? true : file("spoke.hcl state_backend is ${local.state_backend}; known: ${join(", ", local.known_state_backend)}")
  guard_grafana           = local.grafana_enabled && !local.scaleway_enabled ? file("providers.grafana is on for ${path_relative_to_include()} but providers.scaleway is not; its data source needs the Scaleway provider") : true
  guard_bucket_key        = contains(keys(local.spoke.locals), "state_bucket_secret") ? file("spoke.hcl sets state_bucket_secret: root.hcl v3 reads the state bucket from TERRAFORM_STATE_BUCKET_NAME (LIB-0010) in terraform/secrets/terraform.enc; delete state_bucket_secret") : true
  guard_r2_account        = local.state_backend == "cloudflare" && !contains(keys(local.providers), "cloudflare") ? file("spoke.hcl state_backend is cloudflare but providers has no cloudflare; the R2 endpoint is built from CLOUDFLARE_PROVIDER_ACCOUNT_ID in terraform/secrets/cloudflare.enc (LIB-0010, LIB-0012)") : true
  guard_breakglass_leaves = alltrue([for name in local.breakglass_providers : length(try(local.providers[name].breakglass.leaves, [])) > 0]) ? true : file("spoke.hcl providers sets breakglass without leaves for ${join(", ", [for name in local.breakglass_providers : name if length(try(local.providers[name].breakglass.leaves, [])) == 0])}; breakglass must list the leaves allowed to use it (LIB-0014)")
  guard_breakglass_file   = alltrue([for name in local.breakglass_providers : contains(keys(local.secret_files), "${name}_breakglass")]) ? true : file("spoke.hcl providers sets breakglass for ${join(", ", [for name in local.breakglass_providers : name if !contains(keys(local.secret_files), "${name}_breakglass")])}, which has no <provider>_breakglass file in secrets-schema.json (LIB-0014)")
  guard_r2_backup         = local.state_backend == "cloudflare" && local.state_backup != true ? file("spoke.hcl state_backend is cloudflare but state_backup is not true; R2 can't version objects, so its state must be backed up to B2 (LIB-0007, LIB-0012)") : true

  # extra_required_providers: { <name> = { source = "...", version = "..." } },
  # appended to the one required_providers block (LIB-0003 v1.1.0). A
  # provider's configuration, if it needs any, lives in the leaf that uses it.
  extra_required_providers = lookup(local.spoke.locals, "extra_required_providers", {})

  # Where that bucket lives (LIB-0007): "scaleway" (the default) or
  # "cloudflare", an EU-jurisdiction R2 bucket (LIB-0006). One backend per
  # spoke -- Terraform allows exactly one per leaf.
  state_backend       = lookup(local.spoke.locals, "state_backend", "scaleway")
  known_state_backend = ["scaleway", "cloudflare"]

  # Whether state-backup.yml copies the state to B2 (LIB-0012 §2). It also
  # makes the backup keys part of terraform/secrets/terraform.enc.
  state_backup = lookup(local.spoke.locals, "state_backup", false)

  # Secrets (LIB-0012): one sops dotenv file per concern under the spoke's
  # terraform/secrets/, each decrypted in-memory via sops/age (ADR-0123,
  # ADR-0131). No plaintext copy ever touches disk, and nothing ever falls
  # back to another repo's secrets.
  #
  # secrets-schema.json, copied beside this file by resolve-root-hcl.sh, says
  # what each file holds and when it is required: `required_when` lists
  # conditions -- "always", "backend.<state_backend>", "provider.<name>" -- of
  # which any one is enough, and `keys_when` adds keys under a condition
  # ("state_backup"). A file with no `required_when` (env) is optional.
  #
  # A leaf decrypts only the files its own conditions require, with
  # provider.<name> holding only where that provider is on for this leaf
  # (leaves scoping, LIB-0005), plus any optional file that exists. So a
  # Grafana leaf never decrypts backblaze.enc, and a file for a provider this
  # spoke doesn't enable is never read at all.
  secrets_schema = jsondecode(file("${get_parent_terragrunt_dir()}/secrets-schema.json"))
  secrets_dir    = "${get_parent_terragrunt_dir()}/terraform/secrets"
  secret_files   = local.secrets_schema.files

  leaf_conditions = concat(
    ["always", "backend.${local.state_backend}"],
    [for name in local.known_providers : "provider.${name}" if local.provider_on[name]],
    [for name in local.known_providers : "breakglass.${name}" if local.breakglass_on[name]],
    local.state_backup ? ["state_backup"] : [],
  )
  secret_file_path     = { for name, f in local.secret_files : name => "${local.secrets_dir}/${name}.enc" }
  secret_file_optional = { for name, f in local.secret_files : name => length(try(f.required_when, [])) == 0 }
  secret_file_needed = [
    for name, f in local.secret_files : name
    if anytrue([for c in try(f.required_when, []) : contains(local.leaf_conditions, c)])
  ]
  secret_files_read = concat(local.secret_file_needed, [
    for name, optional in local.secret_file_optional : name if optional && fileexists(local.secret_file_path[name])
  ])

  # The existence test is the for's filter, not a conditional: HCL evaluates
  # both arms of ?:, so run_cmd would still run sops on a missing file.
  secrets_decrypted = {
    for name in local.secret_files_read : name => run_cmd(
      "--terragrunt-quiet", "sops", "--decrypt",
      "--input-type", "dotenv", "--output-type", "dotenv",
      local.secret_file_path[name]
    ) if fileexists(local.secret_file_path[name])
  }

  secrets_by_file = {
    for name, text in local.secrets_decrypted : name => { for pair in [
      for line in split("\n", text) :
      regex("^([^=]+)=(.*)$", trimspace(line))
      if trimspace(line) != "" && !startswith(trimspace(line), "#")
      && !startswith(trimspace(line), "sops_")
      && can(regex("^([^=]+)=(.*)$", trimspace(line)))
    ] : trimspace(pair[0]) => trimspace(pair[1]) }
  }

  # Each file's own keys under this leaf's conditions: exactly what it must
  # hold. env, open-ended, has none.
  secret_file_keys = {
    for name, f in local.secret_files : name => distinct(concat(
      try(f.keys, []),
      flatten([for c, ks in try(f.keys_when, {}) : ks if contains(local.leaf_conditions, c)]),
    ))
  }
  # Every key some non-env file may hold, whatever the conditions: an env key
  # with one of these names is a value in the wrong file.
  schema_keys = distinct(flatten([
    for name, f in local.secret_files : concat(try(f.keys, []), flatten(values(try(f.keys_when, {}))))
  ]))

  # The guards name the file and the key, never a value. A key's value is
  # read from the environment first (get_env), so an environment variable
  # still overrides the file, and only the effective value must be non-empty.
  missing_secret_files = [
    for name in local.secret_file_needed : "terraform/secrets/${name}.enc" if !fileexists(local.secret_file_path[name])
  ]
  missing_secrets = flatten([
    for name in keys(local.secrets_by_file) : [
      for k in local.secret_file_keys[name] : "${name}.enc ${k}" if !contains(keys(local.secrets_by_file[name]), k)
    ]
  ])
  empty_secrets = flatten([
    for name in keys(local.secrets_by_file) : [
      for k, v in local.secrets_by_file[name] : "${name}.enc ${k}" if get_env(k, v) == ""
    ]
  ])
  unexpected_secrets = flatten([
    for name in keys(local.secrets_by_file) : [
      for k in sort(keys(local.secrets_by_file[name])) : "${name}.enc ${k}"
      if local.secret_file_optional[name] ? (
        !can(regex(try(local.secret_files[name].pattern, ""), k)) || contains(local.schema_keys, k)
      ) : !contains(local.secret_file_keys[name], k)
    ]
  ])
  reserved_env_secrets = flatten([
    for name in keys(local.secrets_by_file) : [
      for k in sort(keys(local.secrets_by_file[name])) : "${name}.enc ${k} (local.${lower(k)})"
      if contains(try(local.secret_files[name].reserved, []), lower(k))
    ] if local.secret_file_optional[name]
  ])
  guard_missing_secret_files = length(local.missing_secret_files) > 0 ? file("${path_relative_to_include()} needs ${join(", ", local.missing_secret_files)}, required by spoke.hcl's state_backend and providers (LIB-0012; see secrets-schema.json)") : true
  guard_missing_secrets      = length(local.missing_secrets) > 0 ? file("terraform/secrets/ lacks ${join(", ", local.missing_secrets)}, each required in that file (LIB-0012; see secrets-schema.json)") : true
  guard_empty_secrets        = length(local.empty_secrets) > 0 ? file("terraform/secrets/ and the environment leave empty ${join(", ", local.empty_secrets)} (LIB-0012)") : true
  guard_unexpected_secrets   = length(local.unexpected_secrets) > 0 ? file("terraform/secrets/ holds keys outside their file's own: ${join(", ", local.unexpected_secrets)}; move, rename or delete them (LIB-0012; see secrets-schema.json)") : true
  guard_reserved_env         = length(local.reserved_env_secrets) > 0 ? file("terraform/secrets/ env keys shadow a generated local: ${join(", ", local.reserved_env_secrets)}; rename them (LIB-0012)") : true

  # Every value has one name (LIB-0010 §1), read from the environment first
  # and then the file that owns it. The state reads only TERRAFORM_STATE_*,
  # and each provider only its own <PROVIDER>_PROVIDER_*; the one overlap is
  # the R2 endpoint, which needs the Cloudflare account ID (guard_r2_account),
  # and is why a cloudflare backend decrypts cloudflare.enc in every leaf.
  secrets_terraform  = lookup(local.secrets_by_file, "terraform", {})
  secrets_cloudflare = lookup(local.secrets_by_file, "cloudflare", {})
  secrets_scaleway   = lookup(local.secrets_by_file, "scaleway", {})
  secrets_backblaze  = lookup(local.secrets_by_file, "backblaze", {})
  secrets_env        = lookup(local.secrets_by_file, "env", {})

  # Breakglass (LIB-0014): for each breakglass file this leaf decrypts, the
  # canonical key it stands in for => its own key, from the schema's
  # `replaces`, plus `replaces_state` while state_backend is its provider.
  # Every credential below looks itself up here first; a key nothing replaces
  # finds no entry and falls through to its own file. The environment, under
  # the canonical name, still overrides both.
  breakglass_files = [
    for name in local.secret_file_needed : name
    if length(try(local.secret_files[name].replaces, {})) + length(try(local.secret_files[name].replaces_state, {})) > 0
  ]
  breakglass_replace = merge({}, flatten([for name in local.breakglass_files : [
    try(local.secret_files[name].replaces, {}),
    anytrue([
      for c in local.secret_files[name].required_when :
      startswith(c, "breakglass.") && contains(local.leaf_conditions, "backend.${trimprefix(c, "breakglass.")}")
    ]) ? try(local.secret_files[name].replaces_state, {}) : {},
  ]])...)
  breakglass_values = merge({}, [for name in local.breakglass_files : lookup(local.secrets_by_file, name, {})]...)

  terraform_state_bucket_name   = get_env("TERRAFORM_STATE_BUCKET_NAME", lookup(local.secrets_terraform, "TERRAFORM_STATE_BUCKET_NAME", ""))
  terraform_state_access_key_id = get_env("TERRAFORM_STATE_ACCESS_KEY_ID", lookup(local.breakglass_values, lookup(local.breakglass_replace, "TERRAFORM_STATE_ACCESS_KEY_ID", ""), lookup(local.secrets_terraform, "TERRAFORM_STATE_ACCESS_KEY_ID", "")))
  terraform_state_access_key    = get_env("TERRAFORM_STATE_ACCESS_KEY", lookup(local.breakglass_values, lookup(local.breakglass_replace, "TERRAFORM_STATE_ACCESS_KEY", ""), lookup(local.secrets_terraform, "TERRAFORM_STATE_ACCESS_KEY", "")))

  cloudflare_account_id = get_env("CLOUDFLARE_PROVIDER_ACCOUNT_ID", lookup(local.secrets_cloudflare, "CLOUDFLARE_PROVIDER_ACCOUNT_ID", ""))
  cloudflare_api_token  = get_env("CLOUDFLARE_PROVIDER_TOKEN", lookup(local.breakglass_values, lookup(local.breakglass_replace, "CLOUDFLARE_PROVIDER_TOKEN", ""), lookup(local.secrets_cloudflare, "CLOUDFLARE_PROVIDER_TOKEN", "")))

  scaleway_access_key      = get_env("SCALEWAY_PROVIDER_ACCESS_KEY_ID", lookup(local.breakglass_values, lookup(local.breakglass_replace, "SCALEWAY_PROVIDER_ACCESS_KEY_ID", ""), lookup(local.secrets_scaleway, "SCALEWAY_PROVIDER_ACCESS_KEY_ID", "")))
  scaleway_secret_key      = get_env("SCALEWAY_PROVIDER_ACCESS_KEY", lookup(local.breakglass_values, lookup(local.breakglass_replace, "SCALEWAY_PROVIDER_ACCESS_KEY", ""), lookup(local.secrets_scaleway, "SCALEWAY_PROVIDER_ACCESS_KEY", "")))
  scaleway_organization_id = get_env("SCALEWAY_PROVIDER_ORGANIZATION_ID", lookup(local.secrets_scaleway, "SCALEWAY_PROVIDER_ORGANIZATION_ID", ""))
  scaleway_project_id      = get_env("SCALEWAY_PROVIDER_PROJECT_ID", lookup(local.secrets_scaleway, "SCALEWAY_PROVIDER_PROJECT_ID", ""))

  backblaze_application_key_id = get_env("BACKBLAZE_PROVIDER_ACCESS_KEY_ID", lookup(local.breakglass_values, lookup(local.breakglass_replace, "BACKBLAZE_PROVIDER_ACCESS_KEY_ID", ""), lookup(local.secrets_backblaze, "BACKBLAZE_PROVIDER_ACCESS_KEY_ID", "")))
  backblaze_application_key    = get_env("BACKBLAZE_PROVIDER_ACCESS_KEY", lookup(local.breakglass_values, lookup(local.breakglass_replace, "BACKBLAZE_PROVIDER_ACCESS_KEY", ""), lookup(local.secrets_backblaze, "BACKBLAZE_PROVIDER_ACCESS_KEY", "")))

  # Enforce the terraform/<leaf> convention (ADR-0092, ADR-0096): anything this
  # root is included from outside <spoke>/terraform/ is excluded -- except a
  # unit leaf, which is exactly <root>/<unit>/<provider>/<module>/<instance>:
  # a workload's under workloads/ (LIB-0023), or a zone's under zones/
  # (LIB-0036). Since LIB-0037 a workload lives in its zone, one segment
  # deeper: workloads/<zone>/<workload>/..., or with no zone
  # workloads/private/<workload>/..., which unit_offset steps past. Every
  # workload_* local below is a unit's, a zone's included. Since v7.0.0 a leaf
  # at the old depth, workloads/<workload>/<provider>/<module>/<instance>, is
  # refused (LIB-0037 §6).
  path_segments      = split("/", path_relative_to_include())
  unit_root          = local.path_segments[0]
  is_nested_workload = length(local.path_segments) == 6 && local.unit_root == "workloads" && (length(regexall("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", try(local.path_segments[1], ""))) > 0 || try(local.path_segments[1], "") == "private")
  is_old_workload    = length(local.path_segments) == 5 && local.unit_root == "workloads"
  is_workload_leaf   = (length(local.path_segments) == 5 && local.unit_root == "zones") || local.is_nested_workload
  is_zone_unit       = local.is_workload_leaf && local.unit_root == "zones"
  is_valid_leaf      = local.path_segments[0] == "terraform" || local.is_workload_leaf
  unit_offset        = local.is_nested_workload ? 1 : 0
  # The zone a nested workload lives in, or `private`.
  workload_parent     = local.is_nested_workload ? local.path_segments[1] : ""
  is_private_workload = local.workload_parent == "private"
  leaf_provider       = try(local.path_segments[2 + local.unit_offset], "")

  # A zone leaf (LIB-0008) is terraform/cloudflare/<zone>/<module>/<instance>/,
  # where <zone> is the zone's apex domain. A domain always has a dot and a
  # module name never does, which is what tells the two apart. try() because
  # HCL's && doesn't short-circuit, so a short path must not index out of range.
  is_zone_leaf = (
    length(local.path_segments) >= 5 &&
    try(local.path_segments[1], "") == "cloudflare" &&
    length(regexall("\\.", try(local.path_segments[2], ""))) > 0
  )
  cloudflare_zone = local.is_zone_leaf ? local.path_segments[2] : ""

  # Each zones/<zone>/zone.yaml (LIB-0036 §1) gives its hosts, the apex `@`
  # and each subdomain label, to the workloads under workloads/<zone>/ that
  # serve them (LIB-0037 §3). Unit leaves are selected by terragrunt-run.yml
  # rather than the git filter, so these need no mark_as_read. A root
  # zones.yaml is only looked for, to be refused.
  zones = {
    for f in(local.is_workload_leaf ? fileset(get_parent_terragrunt_dir(), "zones/*/zone.yaml") : []) :
    split("/", f)[1] => {
      hosts = try({ for h, w in try(yamldecode(file("${get_parent_terragrunt_dir()}/${f}")).zone.hosts, yamldecode(file("${get_parent_terragrunt_dir()}/${f}")).hosts) : h => tostring(w) }, {})
    }
  }
  # An old-layout workload (LIB-0037 §6), looked for only to be refused.
  old_workload_files = local.is_workload_leaf ? fileset(get_parent_terragrunt_dir(), "workloads/*/values.yaml") : []

  # Workload leaves (LIB-0023). HCL evaluates both arms of a conditional, so
  # every expression below runs for every leaf and is written to be harmless
  # for a hand-written one. Only the guards and workload_tf act, and only on a
  # workload leaf.
  workload          = try(local.path_segments[1 + local.unit_offset], "")
  workload_module   = "${try(local.path_segments[2 + local.unit_offset], "")}/${try(local.path_segments[3 + local.unit_offset], "")}"
  workload_instance = try(local.path_segments[4 + local.unit_offset], "")
  unit_dir          = local.is_nested_workload ? "workloads/${local.workload_parent}/${local.workload}" : "zones/${local.workload}"
  workload_file     = local.is_nested_workload ? "${local.unit_dir}/workload.yaml" : "zones/${local.workload}/zone.yaml"
  workload_doc      = try(yamldecode(file(mark_as_read("${get_parent_terragrunt_dir()}/${local.workload_file}"))), null)
  # A unit file's content may sit under one key, `zone` or `workload`, with
  # its records at dnsRecords (LIB-0039 §§1-2). Everything below reads it
  # unwrapped, with dnsRecords at cloudflare.dnsRecord, the kind table's path.
  # resolve-workloads.sh's unwrap is its twin.
  workload_wrapper = local.is_nested_workload ? "workload" : "zone"
  workload_wrapped = can(local.workload_doc[local.workload_wrapper])
  workload_in      = try(local.workload_doc[local.workload_wrapper], local.workload_doc)
  workload_raw = try(merge(
    { for k, v in local.workload_in : k => v if k != "dnsRecords" },
    { for k, v in { cloudflare = merge({}, try(local.workload_in.cloudflare, null), { dnsRecord = try(local.workload_in.dnsRecords, null) }) } : k => v if can(local.workload_in.dnsRecords) },
  ), null)
  workload_dns_path = local.workload_wrapped ? "dnsRecords" : "cloudflare.dnsRecord"
  # A zone's file, read as a workload's (LIB-0036 §§1-2): its name defaults to
  # its directory, its prefix to that name with every character a resource
  # name can't hold turned into a dash, and every zone kind acts on the
  # directory's zone. Each overlay is a one-key for, since a conditional's arms
  # must be the same shape.
  zone_name = try(tostring(local.workload_raw.name), local.workload)
  # A nested workload's workload.yaml, read as a values.yaml (LIB-0037
  # §§1-2): `prefix` and `suffix` from deployments.scaleway.project, else
  # its zone's; its zone from the directory; and a project entry only when
  # it has its own project. resolve-workloads.sh's expand_workload is its twin.
  workload_zone_doc     = local.is_nested_workload && !local.is_private_workload ? try(yamldecode(file("${get_parent_terragrunt_dir()}/zones/${local.workload_parent}/zone.yaml")), null) : null
  workload_zone_raw     = try(local.workload_zone_doc.zone, local.workload_zone_doc)
  workload_zone_prefix  = try(tostring(local.workload_zone_raw.prefix), replace(try(tostring(local.workload_zone_raw.name), local.workload_parent), "/[^a-z0-9-]/", "-"))
  workload_project      = merge({}, try(local.workload_raw.deployments.scaleway.project, null))
  workload_own_project  = local.is_nested_workload && (local.is_private_workload || length(setintersection(keys(local.workload_project), ["name", "prefix", "suffix"])) > 0)
  workload_zone_project = local.is_nested_workload && !local.workload_own_project
  workload_name         = local.is_nested_workload ? try(tostring(local.workload_raw.name), local.workload) : local.workload
  workload_values = local.workload_raw == null ? null : merge(
    { for k, v in merge({}, try(local.workload_raw, null)) : k => v if !(local.is_nested_workload && contains(["name", "deployments"], k)) },
    { for k, v in { prefix = replace(local.zone_name, "/[^a-z0-9-]/", "-") } : k => v if local.is_zone_unit && !can(tostring(local.workload_raw.prefix)) },
    { for k, v in { cloudflare = merge({}, try(local.workload_raw.cloudflare, null), { zone = local.workload }) } : k => v if local.is_zone_unit },
    { for k, v in {
      prefix = try(tostring(local.workload_project.prefix), local.is_private_workload ? "" : local.workload_zone_prefix)
      suffix = try(tostring(local.workload_project.suffix), local.is_private_workload ? "" : try(tostring(local.workload_zone_raw.suffix), ""))
    } : k => v if local.is_nested_workload },
    { for k, v in { scaleway = merge({}, try(local.workload_raw.scaleway, null), { project = { for pk, pv in local.workload_project : pk => pv if !contains(["prefix", "suffix"], pk) } }) } : k => v if local.workload_own_project },
    { for k, v in { cloudflare = merge({}, try(local.workload_raw.cloudflare, null), { zone = local.workload_parent }) } : k => v if local.is_nested_workload && !local.is_private_workload },
  )
  # The host its zone gives a nested workload (LIB-0037 §3), or "".
  workload_host = try([for h, w in local.zones[local.workload_parent].hosts : h if w == local.workload][0], "")
  # What a unit's implicit resources carry in their names: a zone's `zone`
  # (LIB-0036 §2), a nested workload's name (LIB-0037 §2).
  workload_name_tag = local.is_nested_workload ? "-${local.workload_name}" : ""
  unit_tag          = local.is_zone_unit ? "-zone" : local.workload_name_tag
  # The workload's secrets.yaml (LIB-0025), decrypted the way terraform/secrets/
  # is: a for whose filter, not a conditional, keeps sops from running for a
  # hand-written leaf or a workload without one. A file that won't decrypt
  # fails the run.
  workload_secrets_file = local.is_nested_workload ? "${local.unit_dir}/secrets.workload.yaml" : "${local.unit_root}/${local.workload}/secrets.yaml"
  workload_secrets_doc = merge({}, [
    for f in ["${get_parent_terragrunt_dir()}/${local.workload_secrets_file}"] :
    jsondecode(run_cmd("--terragrunt-quiet", "sops", "--decrypt", "--output-type", "json", mark_as_read(f)))
    if local.is_workload_leaf && !local.is_zone_unit && fileexists(f)
  ]...)
  # Wrapped as its workload.yaml is (LIB-0039 §1).
  workload_secrets_in = try(merge({}, local.workload_secrets_doc.workload), local.workload_secrets_doc)
  workload_secrets = merge(
    { for k, v in local.workload_secrets_in : k => v if k != "dnsRecords" },
    { for k, v in { cloudflare = merge({}, try(local.workload_secrets_in.cloudflare, null), { dnsRecord = try(local.workload_secrets_in.dnsRecords, null) }) } : k => v if can(local.workload_secrets_in.dnsRecords) },
  )
  workload_secrets_scaleway = try(local.workload_secrets.scaleway, null)
  workload_env              = { for k, v in try(local.workload_secrets.env, {}) : k => tostring(v) }

  workload_prefix = try(tostring(local.workload_values.prefix), "")
  workload_suffix = try(tostring(local.workload_values.suffix), "")

  # The kinds (LIB-0023 §2): each module a workload can call, whether this
  # leaf's unit file declares its instance, the entry itself, the inputs a
  # dependency fills and their types (§4's wiring, which the stub sets), the
  # defaults, whose credentials it signs in with (LIB-0024 §2), and which
  # units may declare it (`units`, LIB-0036 §1). resolve-workloads.sh's KINDS and generate-module-redirects.sh's
  # schema list are this table's twins: change one and change all three.
  # resolve-workloads.sh's expand_zone and expand_workload are
  # workload_cf_dns's and workload_cf_rulesets' twins.
  # A YAML key with nothing under it is null, so every lookup goes through
  # try(); a conditional can't stand in, since HCL wants both of its arms to
  # be the same shape of object.
  workload_scaleway = try(local.workload_values.scaleway, null)
  workload_iam      = try(local.workload_scaleway.iam, null)
  # The deployer's three leaves (LIB-0038 §1), each overridden by its own key.
  workload_deployer         = merge({}, try(local.workload_scaleway.deployer, null))
  workload_deployer_secrets = merge({}, try(local.workload_secrets_scaleway.deployer, null))
  workload_deployer_keys    = ["application", "policy", "apiKey"]
  workload_buckets          = try(local.workload_scaleway.bucket, null)
  # Backblaze kinds (LIB-0029).
  workload_backblaze    = try(local.workload_values.backblaze, null)
  workload_b2_buckets   = try(local.workload_backblaze.bucket, null)
  workload_b2_keys      = try(local.workload_backblaze.apiKey, null)
  workload_b2_key_entry = try(local.workload_b2_keys[local.workload_instance], null)
  # Cloudflare kinds (LIB-0030). cloudflare.zone, which root.hcl sets from
  # the unit's directory, fills `zone` for the two zone kinds.
  workload_cloudflare = try(local.workload_values.cloudflare, null)
  workload_cf_zone    = try(tostring(local.workload_cloudflare.zone), "")
  # The Pages records deployments.githubPages implies (LIB-0034 §2, LIB-0037
  # §4), under any explicit entry of the same key. A for with an `if` stands
  # in for a conditional, whose arms HCL wants the same shape. They follow
  # the workload's host: an apex host's are LIB-0034's two, a subdomain's one, all
  # pointing at `url`, by default <username>.github.io.
  workload_pages_on      = local.is_nested_workload && contains(try(keys(local.workload_raw.deployments), []), "githubPages")
  workload_pages_entry   = merge({}, try(local.workload_raw.deployments.githubPages, null))
  workload_pages_user_in = try(tostring(local.workload_pages_entry.username), "")
  # The spoke repo's owner, username's default: CI's GITHUB_REPOSITORY_OWNER,
  # else the owner in origin's URL. git runs only when needed, behind a for's
  # filter, since HCL evaluates both arms of a conditional.
  spoke_origin = join("", [
    for c in ["origin"] : run_cmd("--terragrunt-quiet", "sh", "-c", "git -C \"$1\" remote get-url origin 2>/dev/null || true", "sh", get_parent_terragrunt_dir())
    if local.workload_pages_on && local.workload_pages_user_in == "" && get_env("GITHUB_REPOSITORY_OWNER", "") == ""
  ])
  spoke_owner         = get_env("GITHUB_REPOSITORY_OWNER", try(regex("github\\.com[:/]([^/]+)/", local.spoke_origin)[0], ""))
  workload_pages_user = local.workload_pages_user_in != "" ? local.workload_pages_user_in : local.spoke_owner
  workload_pages_host = local.workload_pages_on && local.workload_host != "" ? try(tostring(local.workload_pages_entry.url), "${local.workload_pages_user}.github.io") : ""
  workload_pages_dns = merge(
    {
      for k, v in {
        "github-pages-root-cname" = { name = "@", type = "CNAME", content = local.workload_pages_host, ttl = 1, proxied = false, comment = "github pages root cname (apex, cloudflare-flattened)" }
        "github-pages-www-cname"  = { name = "www", type = "CNAME", content = local.workload_pages_host, ttl = 1, proxied = false, comment = "github pages www cname" }
      } : k => v if local.workload_pages_host != "" && local.workload_host == "@"
    },
    {
      for k, v in {
        "github-pages-cname" = { name = local.workload_host, type = "CNAME", content = local.workload_pages_host, ttl = 1, proxied = false, comment = "github pages cname" }
      } : k => v if local.workload_pages_host != "" && local.workload_host != "@"
    },
  )
  # A zone's apexRedirect (LIB-0038 §3) is a shorthand: each entry <key>
  # implies dnsRecord <key>-apex and, with include_www, <key>-www, the proxied
  # placeholders, and ruleset <key>, the redirect. Every string is the one
  # cloudflare/apex-redirect generated, so its state moves with no change.
  # An explicit entry of the same key is merged over its default, field by
  # field, as the Pages records are. resolve-workloads.sh's expand_zone is its
  # twin.
  workload_cf_redirects     = { for k, v in merge({}, try(local.workload_cloudflare.apexRedirect, null)) : k => merge({}, v) if local.is_zone_unit }
  workload_cf_redirect_keys = ["target_url", "status_code", "include_www", "preserve_query_string"]
  workload_cf_redirect_host = { for k, e in local.workload_cf_redirects : k => try(trimsuffix(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://(.*)$", tostring(e.target_url))[0], "/"), "") }
  workload_cf_redirect_www  = { for k, e in local.workload_cf_redirects : k => try(tobool(e.include_www), true) }
  workload_cf_redirect_dns = merge(
    { for k, e in local.workload_cf_redirects : "${k}-apex" => { name = "@", type = "A", content = "192.0.2.1", proxied = true, ttl = 1, comment = "placeholder so Cloudflare intercepts apex traffic for the ${local.workload_cf_redirect_host[k]} redirect" } },
    { for k, e in local.workload_cf_redirects : "${k}-www" => { name = "www", type = "CNAME", content = local.workload, proxied = true, ttl = 1, comment = "placeholder so Cloudflare intercepts www traffic for the ${local.workload_cf_redirect_host[k]} redirect" } if local.workload_cf_redirect_www[k] },
  )
  workload_cf_redirect_rulesets = {
    for k, e in local.workload_cf_redirects : k => {
      name  = "${local.workload} to ${local.workload_cf_redirect_host[k]} redirect"
      kind  = "zone"
      phase = "http_request_dynamic_redirect"
      rules = [{
        expression  = join(" or ", [for h in(local.workload_cf_redirect_www[k] ? [local.workload, "www.${local.workload}"] : [local.workload]) : "(http.host eq \"${h}\")"])
        description = "redirect ${local.workload_cf_redirect_www[k] ? "${local.workload} and www" : local.workload} to the ${local.workload_cf_redirect_host[k]} homepage"
        action      = "redirect"
        action_parameters = {
          from_value = {
            status_code = try(e.status_code, 301)
            target_url = {
              value = try(tostring(e.target_url), "")
            }
            preserve_query_string = try(e.preserve_query_string, false)
          }
        }
      }]
    }
  }
  zone_services_all = try({ for n, v in local.workload_raw.services : n => v if local.is_zone_unit }, {})
  # A zone's services (LIB-0039 §3): each enabled one implies its provider's
  # records, under any explicit entry of the same key, as the Pages records
  # are. resolve-workloads.sh's service_dns is its twin.
  workload_services = { for n, v in local.zone_services_all : n => v if try(v.enabled, false) == true }
  workload_service_dmarc = { for n, v in local.workload_services : n => (
    !can(v.dmarc) || try(v.dmarc == true, false) ? "v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s" :
    try(v.dmarc == false, false) ? "" : try(startswith(v.dmarc, "v=DMARC1") ? tostring(v.dmarc) : null, null)
  ) }
  workload_cf_service_dns = merge(
    {
      for k, v in {
        "proton-mx-primary"              = { name = "@", type = "MX", content = "mx1.alias.proton.me", priority = 10, ttl = 1, comment = "proton primary mx" }
        "proton-mx-secondary"            = { name = "@", type = "MX", content = "mx2.alias.proton.me", priority = 20, ttl = 1, comment = "proton secondary mx" }
        "proton-dkim-primary"            = { name = "dkim._domainkey", type = "CNAME", content = "dkim._domainkey.alias.proton.me", ttl = 1, proxied = false, comment = "proton primary dkim" }
        "proton-dkim-secondary"          = { name = "dkim02._domainkey", type = "CNAME", content = "dkim02._domainkey.alias.proton.me", ttl = 1, proxied = false, comment = "proton secondary dkim" }
        "proton-dkim-tertiary"           = { name = "dkim03._domainkey", type = "CNAME", content = "dkim03._domainkey.alias.proton.me", ttl = 1, proxied = false, comment = "proton tertiary dkim" }
        "proton-spf"                     = { name = "@", type = "TXT", content = "v=spf1 include:alias.proton.me ~all", ttl = 1, comment = "proton spf" }
        "proton-pm-verification"         = { name = "@", type = "TXT", content = "pm-verification=${try(tostring(local.workload_services.proton.verification.pm), "")}", ttl = 1, comment = "proton pm verification" }
        "proton-protonmail-verification" = { name = "@", type = "TXT", content = "protonmail-verification=${try(tostring(local.workload_services.proton.verification.protonmail), "")}", ttl = 1, comment = "proton protonmail verification" }
      } : k => v if contains(keys(local.workload_services), "proton")
    },
    {
      for k, v in {
        "proton-dmarc" = { name = "_dmarc", type = "TXT", content = try(local.workload_service_dmarc.proton, ""), ttl = 1, comment = "proton dmarc" }
      } : k => v if try(local.workload_service_dmarc.proton, "") != ""
    },
    {
      for k, v in {
        "fastmail-mx-primary"   = { name = "@", type = "MX", content = "in1-smtp.messagingengine.com", priority = 10, ttl = 1, comment = "fastmail primary mx" }
        "fastmail-mx-secondary" = { name = "@", type = "MX", content = "in2-smtp.messagingengine.com", priority = 20, ttl = 1, comment = "fastmail secondary mx" }
        "fastmail-dkim-fm1"     = { name = "fm1._domainkey", type = "CNAME", content = "fm1.${local.workload}.dkim.fmhosted.com", ttl = 1, proxied = false, comment = "fastmail primary dkim" }
        "fastmail-dkim-fm2"     = { name = "fm2._domainkey", type = "CNAME", content = "fm2.${local.workload}.dkim.fmhosted.com", ttl = 1, proxied = false, comment = "fastmail secondary dkim" }
        "fastmail-dkim-fm3"     = { name = "fm3._domainkey", type = "CNAME", content = "fm3.${local.workload}.dkim.fmhosted.com", ttl = 1, proxied = false, comment = "fastmail tertiary dkim" }
        "fastmail-spf"          = { name = "@", type = "TXT", content = "\"v=spf1 include:spf.messagingengine.com ?all\"", ttl = 1, comment = "fastmail spf" }
      } : k => v if contains(keys(local.workload_services), "fastmail")
    },
    {
      for k, v in {
        "fastmail-dmarc" = { name = "_dmarc", type = "TXT", content = try(local.workload_service_dmarc.fastmail, ""), ttl = 1, comment = "fastmail dmarc" }
      } : k => v if try(local.workload_service_dmarc.fastmail, "") != ""
    },
    {
      for k, v in {
        "googlesearch-site-verification" = { name = "@", type = "TXT", content = "\"google-site-verification=${try(tostring(local.workload_services.googleSearch.verification), "")}\"", ttl = 1, comment = "google search site verification" }
      } : k => v if contains(keys(local.workload_services), "googleSearch")
    },
    {
      for k, v in {
        "bluesky-did" = { name = "_atproto", type = "TXT", content = "did=${try(tostring(local.workload_services.bluesky.did), "")}", ttl = 1, comment = "bluesky domain handle" }
      } : k => v if contains(keys(local.workload_services), "bluesky")
    },
  )
  workload_cf_implied = merge(local.workload_pages_dns, local.workload_cf_redirect_dns, local.workload_cf_service_dns)
  workload_cf_dns = merge(local.workload_cf_implied, {
    for k, v in merge({}, try(local.workload_cloudflare.dnsRecord, null)) :
    k => merge(lookup(local.workload_cf_implied, k, {}), merge({}, v))
  })
  workload_cf_rulesets = merge(local.workload_cf_redirect_rulesets, {
    for k, v in merge({}, try(local.workload_cloudflare.ruleset, null)) :
    k => merge(lookup(local.workload_cf_redirect_rulesets, k, {}), merge({}, v))
  })
  workload_cf_maps = {
    "cloudflare/bucket"     = try(local.workload_cloudflare.bucket, null)
    "cloudflare/dns-record" = local.workload_cf_dns
    "cloudflare/ruleset"    = local.workload_cf_rulesets
  }
  workload_cf_yaml = {
    "cloudflare/bucket"     = "bucket"
    "cloudflare/dns-record" = "dnsRecord"
    "cloudflare/ruleset"    = "ruleset"
  }
  workload_cf_entry     = try(local.workload_cf_maps[local.workload_module][local.workload_instance], null)
  workload_cf_declared  = contains(try(keys(local.workload_cf_maps[local.workload_module]), []), local.workload_instance)
  workload_cf_secrets   = try(local.workload_secrets.cloudflare[local.workload_cf_yaml[local.workload_module]][local.workload_instance], null)
  workload_cf_zone_kind = contains(["cloudflare/dns-record", "cloudflare/ruleset"], local.workload_module)
  # An entry's path in its file, for messages: a wrapped file's records are
  # at dnsRecords (LIB-0039 §2).
  workload_cf_path     = local.workload_module == "cloudflare/dns-record" ? local.workload_dns_path : "cloudflare.${try(local.workload_cf_yaml[local.workload_module], "")}"
  workload_cf_zone_set = { for k, v in { zone = local.workload_cf_zone } : k => v if v != "" }
  # The zone a zone kind acts on: its own, or the workload's default.
  workload_zone = try(tostring(local.workload_cf_entry.zone), local.workload_cf_zone)
  # The workload's own Cloudflare token (LIB-0033 §4): it exists when a
  # zone.yaml names the workload or it declares an R2 bucket, and reaches only
  # those. A zone's token always has one, its own zone (LIB-0036 §2), and only
  # a zone's gets the redirect group, since it alone holds entrypoints
  # (LIB-0036 §3).
  # A nested workload's token reaches its zone only when it has a host there
  # (LIB-0037 §3).
  workload_cf_owned    = local.is_zone_unit ? [local.workload] : [for z in [local.workload_parent] : z if local.workload_host != ""]
  workload_cf_buckets  = length(try(keys(local.workload_cloudflare.bucket), [])) > 0
  workload_cf_deployer = local.is_zone_unit || length(local.workload_cf_owned) > 0 || local.workload_cf_buckets
  workload_cf_policies = concat(
    [for z in [local.workload_cf_owned] : { permission_groups = concat(["Zone Read", "DNS Write"], local.is_zone_unit ? ["Dynamic URL Redirects Write"] : []), zones = z } if length(z) > 0],
    [for b in [local.workload_cf_buckets] : { permission_groups = ["Workers R2 Storage Write"], account = true } if b],
  )
  # Each kind also says where its state lives (LIB-0028 §4): `spoke` in the
  # spoke's bucket, through this file's remote_state; `workload` in the
  # workload's bucket, through the remote_state its stub declares. The project,
  # deployer and state bucket are implicit (LIB-0028 §1): every workload has
  # them, and an entry only overrides their inputs.
  workload_kinds = {
    "scaleway/project" = {
      declared    = local.workload_instance == "main"
      entry       = try(local.workload_scaleway.project, null)
      secrets     = try(local.workload_secrets_scaleway.project, null)
      wiring      = {}
      defaults    = { name = local.is_zone_unit ? local.zone_name : "${local.workload_prefix}-${local.workload_suffix}" }
      sensitive   = false
      credentials = "spoke"
      state       = "spoke"
      units       = ["workload", "zone"]
    }
    "scaleway/iam-application" = {
      declared    = local.workload_instance == "main" && contains(try(keys(local.workload_iam), []), "application")
      entry       = try(local.workload_iam.application, null)
      secrets     = try(local.workload_secrets_scaleway.iam.application, null)
      wiring      = {}
      defaults    = { name = "${local.workload_prefix}-${local.workload_suffix}${local.workload_name_tag}" }
      sensitive   = false
      credentials = "spoke"
      state       = "workload"
      units       = ["workload"]
    }
    # The unit's deployer (LIB-0024 §1, LIB-0038 §1): an application, its
    # policy on the unit's project, and the key every workload-credentials
    # provider and workload-state backend signs in with. Its policy keeps the
    # name terraform-deployer-iam gave it, since iam-policy appends -policy.
    "scaleway/iam-application#deployer" = {
      declared    = local.workload_instance == "deployer"
      entry       = try(local.workload_deployer.application, null)
      secrets     = try(local.workload_deployer_secrets.application, null)
      wiring      = {}
      defaults    = { name = "${local.workload_prefix}-${local.workload_suffix}${local.unit_tag}-deployer" }
      sensitive   = false
      credentials = "spoke"
      state       = "spoke"
      units       = ["workload", "zone"]
    }
    "scaleway/iam-policy#deployer" = {
      declared = local.workload_instance == "deployer"
      entry    = try(local.workload_deployer.policy, null)
      secrets  = try(local.workload_deployer_secrets.policy, null)
      wiring   = { project_ids = "list(string)", application_id = "string" }
      defaults = {
        name                    = "${local.workload_prefix}-${local.workload_suffix}${local.unit_tag}-deployer"
        project_permission_sets = ["ObjectStorageFullAccess"]
      }
      sensitive   = false
      credentials = "spoke"
      state       = "spoke"
      units       = ["workload", "zone"]
    }
    "scaleway/iam-api-key#deployer" = {
      declared    = local.workload_instance == "deployer"
      entry       = try(local.workload_deployer.apiKey, null)
      secrets     = try(local.workload_deployer_secrets.apiKey, null)
      wiring      = { default_project_id = "string", application_id = "string" }
      defaults    = { rotation_days = 30 }
      sensitive   = true
      credentials = "spoke"
      state       = "spoke"
      units       = ["workload", "zone"]
    }
    # The workload's state bucket (LIB-0028 §2): scaleway/bucket's instance
    # `state`. Its `prefix` is this file's, for workload_state_key, not the
    # module's.
    "scaleway/bucket#state" = {
      declared = local.workload_instance == "state"
      entry    = try({ for k, v in local.workload_scaleway.state : k => v if k != "prefix" }, null)
      secrets  = try(local.workload_secrets_scaleway.state, null)
      wiring   = { project_id = "string" }
      defaults = {
        name_prefix       = local.workload_prefix
        name_suffix       = "${trimprefix(local.unit_tag, "-")}${local.unit_tag == "" ? "" : "-"}terraform-state"
        enable_versioning = true
        storage_class     = "standard"
        force_destroy     = false
      }
      sensitive   = false
      credentials = "workload"
      state       = "spoke"
      units       = ["workload", "zone"]
    }
    "scaleway/bucket" = {
      declared    = local.workload_instance != "state" && contains(try(keys(local.workload_buckets), []), local.workload_instance)
      entry       = try(local.workload_buckets[local.workload_instance], null)
      secrets     = try(local.workload_secrets_scaleway.bucket[local.workload_instance], null)
      wiring      = { project_id = "string" }
      defaults    = { name_prefix = "${local.workload_prefix}${local.workload_name_tag}-${local.workload_instance}", name_suffix = local.workload_suffix }
      sensitive   = false
      credentials = "workload"
      state       = "workload"
      units       = ["workload"]
    }
    "scaleway/iam-api-key" = {
      declared    = local.workload_instance == "main" && contains(try(keys(local.workload_iam), []), "apiKey")
      entry       = try(local.workload_iam.apiKey, null)
      secrets     = try(local.workload_secrets_scaleway.iam.apiKey, null)
      wiring      = { default_project_id = "string", application_id = "string" }
      defaults    = {}
      sensitive   = true
      credentials = "spoke"
      state       = "workload"
      units       = ["workload"]
    }
    # Backblaze (LIB-0029): the spoke's account-wide key, the workload's state.
    "backblaze/bucket" = {
      declared    = contains(try(keys(local.workload_b2_buckets), []), local.workload_instance)
      entry       = try(local.workload_b2_buckets[local.workload_instance], null)
      secrets     = try(local.workload_secrets.backblaze.bucket[local.workload_instance], null)
      wiring      = {}
      defaults    = { name_prefix = "${local.workload_prefix}${local.workload_name_tag}-${local.workload_instance}", name_suffix = local.workload_suffix }
      sensitive   = false
      credentials = "spoke"
      state       = "workload"
      units       = ["workload"]
    }
    # `buckets` names the stub's dependencies, which wire bucket_ids; it isn't
    # an input of the module's.
    "backblaze/api-key" = {
      declared    = contains(try(keys(local.workload_b2_keys), []), local.workload_instance)
      entry       = try({ for k, v in local.workload_b2_key_entry : k => v if k != "buckets" }, null)
      secrets     = try(local.workload_secrets.backblaze.apiKey[local.workload_instance], null)
      wiring      = { bucket_ids = "list(string)" }
      defaults    = { key_name = "${local.workload_prefix}${local.workload_name_tag}-${local.workload_instance}-${local.workload_suffix}" }
      sensitive   = true
      credentials = "spoke"
      state       = "workload"
      units       = ["workload"]
    }
    # The workload's Cloudflare token (LIB-0033 §4), minted with the spoke's
    # breakglass token where it has one (breakglass_on), since a minted token
    # can't mint; with the spoke's own token otherwise.
    # An entry under cloudflare.deployer overrides any default.
    "cloudflare/api-token#deployer" = {
      declared     = local.workload_instance == "deployer" && local.workload_cf_deployer
      entry        = try(local.workload_cloudflare.deployer, null)
      secrets      = try(local.workload_secrets.cloudflare.deployer, null)
      wiring       = {}
      defaults     = { name = "${local.workload_prefix}-${local.workload_suffix}${local.unit_tag}-cloudflare-deployer", rotation_days = 30, policies = local.workload_cf_policies }
      spoke_inputs = { account_id = local.cloudflare_account_id }
      sensitive    = true
      credentials  = "spoke"
      state        = "workload"
      units        = ["workload", "zone"]
    }
    # Cloudflare (LIB-0030), signed in with the workload's token (LIB-0033 §4).
    # spoke_inputs reach the module as sensitive variables, never literals.
    "cloudflare/bucket" = {
      declared     = local.workload_cf_declared
      entry        = local.workload_cf_entry
      secrets      = local.workload_cf_secrets
      wiring       = {}
      defaults     = { name_prefix = "${local.workload_prefix}${local.workload_name_tag}-${local.workload_instance}", name_suffix = local.workload_suffix }
      spoke_inputs = { account_id = local.cloudflare_account_id }
      sensitive    = false
      credentials  = "workload"
      state        = "workload"
      units        = ["workload"]
    }
    "cloudflare/dns-record" = {
      declared    = local.workload_cf_declared
      entry       = local.workload_cf_entry
      secrets     = local.workload_cf_secrets
      wiring      = {}
      defaults    = merge(local.workload_cf_zone_set, { name = local.workload_instance, comment = local.unit_dir })
      sensitive   = false
      credentials = "workload"
      state       = "workload"
      units       = ["workload", "zone"]
    }
    "cloudflare/ruleset" = {
      declared    = local.workload_cf_declared
      entry       = local.workload_cf_entry
      secrets     = local.workload_cf_secrets
      wiring      = {}
      defaults    = merge(local.workload_cf_zone_set, { name = "${local.workload_prefix}-${local.workload_instance}-${local.workload_suffix}" })
      sensitive   = false
      credentials = "workload"
      state       = "workload"
      units       = ["zone"]
    }
  }
  workload_kind_key = (
    local.workload_module == "scaleway/bucket" && local.workload_instance == "state" ? "scaleway/bucket#state" :
    local.workload_instance == "deployer" && contains(["scaleway/iam-application", "scaleway/iam-policy", "scaleway/iam-api-key", "cloudflare/api-token"], local.workload_module) ? "${local.workload_module}#deployer" :
    local.workload_module
  )
  # The kinds LIB-0038 retired, refused by name rather than as unknown.
  workload_retired = contains(["scaleway/terraform-deployer-iam", "cloudflare/apex-redirect"], local.workload_module)
  workload_kind    = try(local.workload_kinds[local.workload_kind_key], null)
  workload_entry   = merge({}, try(local.workload_kind.entry, null))

  # Secret inputs (LIB-0025 §3): this leaf's slice of secrets.yaml, and every
  # values.yaml input written as { secretRef: NAME }, resolved from `env`.
  # They become sensitive variables, never literals.
  workload_secret_entry = merge({}, try(local.workload_kind.secrets, null))
  workload_refs         = { for k, v in local.workload_entry : k => v.secretRef if can(v.secretRef) }
  workload_sensitive = merge(
    { for k, v in local.workload_secret_entry : k => try(tostring(v), null) },
    { for k, name in local.workload_refs : k => lookup(local.workload_env, name, null) },
    try(local.workload_kind.spoke_inputs, {}),
  )

  # The module's plaintext inputs: the defaults, then the entry, which wins.
  # A wiring input the entry doesn't set is left to the stub's dependency, and
  # a secret input to workload_sensitive.
  workload_inputs = {
    for k, v in merge(
      try(local.workload_kind.defaults, {}),
      { for k, v in local.workload_entry : k => v if k != "version" && !can(v.secretRef) },
    ) : k => v if !contains(keys(local.workload_sensitive), k)
  }
  workload_wiring = { for k, type in try(local.workload_kind.wiring, {}) : k => type if !contains(keys(local.workload_inputs), k) && !contains(keys(local.workload_sensitive), k) }

  # A `workload` kind signs its provider in with the workload deployer's key
  # (LIB-0024 §2), which the stub passes from its deployer dependency.
  workload_credentials = local.is_workload_leaf && try(local.workload_kind.credentials, "spoke") == "workload"
  # Whose: a Scaleway leaf's comes from the workload deployer's key, a
  # Cloudflare leaf's from the workload's Cloudflare token (LIB-0033 §4).
  workload_credentials_scaleway   = local.workload_credentials && local.leaf_provider == "scaleway"
  workload_credentials_cloudflare = local.workload_credentials && local.leaf_provider == "cloudflare"

  # Where a `workload`-state leaf's state sits in its workload's bucket
  # (LIB-0028 §3): under scaleway.state.prefix, by default workloads/<workload>/,
  # which makes the key exactly what path_relative_to_include() gives. Read by
  # the stub's remote_state, which this file can't declare for it: only the stub
  # has the dependencies the bucket name and the deployer's key come from.
  workload_state        = try(local.workload_kind.state, "spoke")
  workload_state_prefix = try(tostring(local.workload_scaleway.state.prefix), "${local.unit_dir}/")
  workload_state_key    = "${local.workload_state_prefix}${local.workload_module}/${local.workload_instance}/terraform.tfstate"
  # A stub from a resolve-workloads.sh older than LIB-0028 has no remote_state,
  # and would keep a workload-state leaf's state in the spoke's bucket.
  workload_stub_backend = local.is_workload_leaf && local.workload_state == "workload" ? length(regexall("(?m)^remote_state \\{", file("${get_terragrunt_dir()}/terragrunt.hcl"))) > 0 : true

  # The version (LIB-0023 §3): X.Y.Z exactly, X.Y or X as the newest release
  # within it, or the newest release when unset, by git's own version sort.
  # A hand-written leaf runs `true` instead of git, so it lists nothing.
  workload_pin = try(tostring(local.workload_entry.version), "")
  workload_tag_pattern = (
    local.workload_pin == "" ? "v*" :
    length(split(".", local.workload_pin)) == 3 ? "v${local.workload_pin}" :
    "v${local.workload_pin}.*"
  )
  workload_tags = run_cmd(
    "--terragrunt-quiet", local.is_workload_leaf ? "git" : "true",
    "ls-remote", "--sort=-v:refname", "--tags",
    get_env("LIB_TAG_REMOTE", "https://github.com/noisypigeon/library"),
    "refs/tags/terraform/${local.workload_module}/${local.workload_tag_pattern}",
  )
  workload_version = try(regex("/v([0-9]+\\.[0-9]+\\.[0-9]+)(\\^\\{\\})?$", split("\n", trimspace(local.workload_tags))[0])[0], "")

  guard_workload_values = local.is_workload_leaf && local.workload_values == null ? file("${local.workload_file} is missing or not valid YAML, but ${path_relative_to_include()} is its stub (LIB-0023)") : true
  # The old layout (LIB-0037 §6): a leaf at its depth, and any values.yaml.
  guard_workload_old_leaf = local.is_old_workload ? file("${path_relative_to_include()} is a workload leaf in the old layout, workloads/<workload>/, refused since root.hcl v7.0.0: a workload lives in workloads/<zone>/<workload>/ or workloads/private/<workload>/ (LIB-0037 §6)") : true
  guard_workload_old_file = length(local.old_workload_files) > 0 ? file("${join(", ", local.old_workload_files)}: a workloads/<workload>/values.yaml is refused since root.hcl v7.0.0; move it to workloads/<zone>/<workload>/workload.yaml (LIB-0037 §6)") : true
  guard_workload_retired  = local.is_workload_leaf && local.workload_retired ? file("${path_relative_to_include()}: ${local.workload_module} is no longer a kind; its resources are the ${local.workload_module == "cloudflare/apex-redirect" ? "cloudflare/dns-record and cloudflare/ruleset leaves an apexRedirect implies" : "scaleway/iam-application, iam-policy and iam-api-key leaves at the instance deployer"}. Regenerate the stubs with workflows v7, and move its state by LIB-0038 §5") : true
  guard_workload_kind     = local.is_workload_leaf && !local.workload_retired && local.workload_kind == null ? file("${path_relative_to_include()}: ${local.workload_module} is not a workload kind (LIB-0023 §2)") : true
  guard_workload_unit     = local.is_workload_leaf && local.workload_kind != null && !contains(try(local.workload_kind.units, []), local.is_zone_unit ? "zone" : "workload") ? file("${path_relative_to_include()}: ${local.workload_module} is not a kind a ${local.is_zone_unit ? "zone" : "workload"} takes (LIB-0036 §§1, 3)") : true
  guard_workload_declared = local.is_workload_leaf && !try(local.workload_kind.declared, true) ? file("${path_relative_to_include()} has no entry in ${local.workload_file}; run resolve-workloads.sh, which generates stubs from values.yaml (LIB-0023)") : true
  guard_workload_names    = local.is_workload_leaf && (local.workload_prefix == "" || local.workload_suffix == "") ? file("${local.workload_file} needs a non-empty prefix and suffix (LIB-0023 §4)") : true
  guard_workload_inputs   = local.is_workload_leaf && !alltrue([for k in keys(local.workload_inputs) : can(regex("^[a-z_][a-z0-9_]*$", k))]) ? file("${path_relative_to_include()}: ${local.workload_file} has an input name that isn't a Terraform identifier") : true
  guard_workload_pin      = local.is_workload_leaf && !can(regex("^([0-9]+(\\.[0-9]+){0,2})?$", local.workload_pin)) ? file("${path_relative_to_include()}: version \"${local.workload_pin}\" must be X, X.Y or X.Y.Z (LIB-0023 §3)") : true
  guard_workload_both     = local.is_workload_leaf && length(setintersection(keys(local.workload_secret_entry), [for k in keys(local.workload_entry) : k if k != "version"])) > 0 ? file("${path_relative_to_include()}: ${join(", ", setintersection(keys(local.workload_secret_entry), keys(local.workload_entry)))} set in both ${local.workload_file} and ${local.workload_secrets_file}; keep each input in one (LIB-0025)") : true
  guard_workload_refs     = local.is_workload_leaf && !alltrue([for k, name in local.workload_refs : contains(keys(local.workload_env), name)]) ? file("${path_relative_to_include()}: a secretRef in ${local.workload_file} names something ${local.workload_secrets_file}'s env doesn't have (LIB-0025)") : true
  guard_workload_scalars  = local.is_workload_leaf && !alltrue(concat([for k, v in local.workload_sensitive : v != null], [for k, v in try(local.workload_secrets.env, {}) : can(tostring(v))])) ? file("${path_relative_to_include()}: every value in ${local.workload_secrets_file} must be one value, not a list or a map (LIB-0025)") : true
  guard_workload_version  = local.is_workload_leaf && local.workload_version == "" ? file("${path_relative_to_include()}: no terraform/${local.workload_module} tag matches version \"${local.workload_pin}\" (LIB-0023 §3)") : true
  guard_workload_reserved = local.is_workload_leaf && contains(try(keys(local.workload_buckets), []), "state") ? file("${local.workload_file}: scaleway.bucket.state is reserved for the workload's state bucket; configure it as scaleway.state (LIB-0028)") : true
  guard_workload_prefix   = local.is_workload_leaf && !can(regex("^[^/].*/$", local.workload_state_prefix)) ? file("${local.workload_file}: scaleway.state.prefix \"${local.workload_state_prefix}\" must not start with / and must end with one (LIB-0028 §3)") : true
  guard_workload_versions = local.is_workload_leaf && try(local.workload_scaleway.state.enable_versioning, true) == false ? file("${local.workload_file}: scaleway.state.enable_versioning can't be false; versioning is the state's only protection (LIB-0028 §2)") : true
  guard_workload_glacier  = local.is_workload_leaf && try(local.workload_scaleway.state.storage_class, "standard") == "glacier" ? file("${local.workload_file}: scaleway.state.storage_class can't be glacier; state moved to GLACIER after 90 days can't be read without a restore (LIB-0028 §2)") : true
  guard_workload_deployer = local.is_workload_leaf && can(local.workload_deployer.policy.project_permission_sets) && !contains(try(tolist(local.workload_deployer.policy.project_permission_sets), []), "ObjectStorageFullAccess") ? file("${local.workload_file}: scaleway.deployer.policy.project_permission_sets must keep ObjectStorageFullAccess; the deployer's key signs in to the workload's state bucket (LIB-0028 §5, LIB-0038 §1)") : true
  # LIB-0024 §1's flat scaleway.deployer, the bundle's inputs (LIB-0038 §1).
  workload_deployer_flat  = sort(setsubtract(concat(keys(local.workload_deployer), keys(local.workload_deployer_secrets)), local.workload_deployer_keys))
  guard_workload_dep_flat = local.is_workload_leaf && length(local.workload_deployer_flat) > 0 ? file("${local.workload_file}: scaleway.deployer.${join(", scaleway.deployer.", local.workload_deployer_flat)}: the deployer is three leaves, so each input goes under scaleway.deployer.application, .policy or .apiKey, by its module's own name (LIB-0038 §1)") : true
  guard_workload_backend  = !local.workload_stub_backend ? file("${path_relative_to_include()} keeps its state in the workload's bucket but its stub declares no remote_state; regenerate it with a resolve-workloads.sh from workflows v4.9.0 or later (LIB-0028 §5)") : true
  guard_workload_b2_on    = local.is_workload_leaf && local.leaf_provider == "backblaze" && !contains(keys(local.providers), "backblaze") ? file("${path_relative_to_include()} is a Backblaze workload leaf, but spoke.hcl's providers map has no backblaze (LIB-0029 §4)") : true
  guard_workload_b2_list  = local.is_workload_leaf && local.workload_module == "backblaze/api-key" && length(try(tolist(local.workload_b2_key_entry.buckets), [])) == 0 ? file("${local.workload_file}: backblaze.apiKey.${local.workload_instance}.buckets must list at least one of this workload's backblaze.bucket keys (LIB-0029 §3)") : true
  guard_workload_b2_known = local.is_workload_leaf && local.workload_module == "backblaze/api-key" && length(setsubtract(try(tolist(local.workload_b2_key_entry.buckets), []), try(keys(local.workload_b2_buckets), []))) > 0 ? file("${local.workload_file}: backblaze.apiKey.${local.workload_instance}.buckets names a bucket this workload's backblaze.bucket doesn't have (LIB-0029 §3)") : true
  guard_workload_b2_ids   = local.is_workload_leaf && local.workload_module == "backblaze/api-key" && (can(local.workload_b2_key_entry.bucket_ids) || can(local.workload_secrets.backblaze.apiKey[local.workload_instance].bucket_ids)) ? file("${local.workload_file}: backblaze.apiKey.${local.workload_instance}.bucket_ids can't be set; list the buckets in buckets instead (LIB-0029 §3)") : true
  guard_workload_cf_on    = local.is_workload_leaf && local.leaf_provider == "cloudflare" && !contains(keys(local.providers), "cloudflare") ? file("${path_relative_to_include()} is a Cloudflare workload leaf, but spoke.hcl's providers map has no cloudflare (LIB-0030 §1)") : true
  guard_workload_cf_spoke = local.is_workload_leaf && local.leaf_provider == "cloudflare" && (can(local.workload_cf_entry.account_id) || can(local.workload_cf_entry.zone_id) || can(local.workload_cf_secrets.account_id) || can(local.workload_cf_secrets.zone_id)) ? file("${local.workload_file}: ${local.workload_cf_path}.${local.workload_instance} can't set account_id or zone_id; the account is the spoke's, and a zone is named (LIB-0030 §§4-5)") : true
  guard_workload_cf_zone  = local.is_workload_leaf && local.workload_cf_zone_kind && local.workload_zone == "" ? file("${local.workload_file}: ${local.workload_cf_path}.${local.workload_instance} has no zone, and the workload sets no cloudflare.zone (LIB-0030 §3)") : true
  # Nested workloads (LIB-0037 §§1-4): what a workload.yaml can't say, read
  # before its defaults fill it in, then what its host allows.
  workload_record_name = try(tostring(local.workload_cf_entry.name), local.workload_instance)
  workload_nested_problems = local.is_nested_workload && local.workload_raw != null ? compact([
    can(local.workload_raw.features) ? "features is refused since root.hcl v7.0.0; githubPages moves to deployments.githubPages (LIB-0037 §§4, 6)" : "",
    can(local.workload_raw.prefix) || can(local.workload_raw.suffix) ? "prefix and suffix move to deployments.scaleway.project (LIB-0037 §2)" : "",
    can(local.workload_raw.scaleway.project) ? "scaleway.project moves to deployments.scaleway.project (LIB-0037 §2)" : "",
    can(local.workload_raw.cloudflare.zone) || can(local.workload_raw.cloudflare[local.workload_cf_yaml[local.workload_module]][local.workload_instance].zone) ? "cloudflare.zone is refused; the directory names the zone (LIB-0037 §§1, 6)" : "",
    local.workload_name == "zone" ? "name can't be zone, which a zone's own resources carry (LIB-0037 §1)" : "",
    fileexists("${get_parent_terragrunt_dir()}/${local.unit_dir}/secrets.yaml") ? "secrets.yaml is refused; rename it secrets.workload.yaml (LIB-0037 §§1, 6)" : "",
    !local.is_private_workload && local.workload_zone_raw == null ? "zone ${local.workload_parent} has no zones/${local.workload_parent}/zone.yaml (LIB-0037 §1)" : "",
    local.workload_pages_on && local.is_private_workload ? "deployments.githubPages needs a host, which a private workload never has (LIB-0037 §§1, 4)" : "",
    local.workload_pages_on && !local.is_private_workload && local.workload_host == "" ? "deployments.githubPages needs a host; give this workload one in zones/${local.workload_parent}/zone.yaml (LIB-0037 §4)" : "",
    local.workload_pages_on && local.workload_host != "" && local.workload_pages_user == "" ? "deployments.githubPages.username defaults to the spoke repo's owner, but neither GITHUB_REPOSITORY_OWNER nor origin's URL gives one (LIB-0037 §4)" : "",
    local.workload_cf_zone_kind && local.workload_host == "" && !local.is_private_workload ? "${local.workload_cf_path}.${local.workload_instance}: this workload has no host in zones/${local.workload_parent}/zone.yaml, so it can't write records (LIB-0037 §3)" : "",
    local.workload_cf_zone_kind && local.workload_host != "" && !(
      local.workload_host == "@" ? (contains(["@", "www"], local.workload_record_name) || can(regex("^_[^.]+(\\.www)?$", local.workload_record_name))) :
      (local.workload_record_name == local.workload_host || endswith(local.workload_record_name, ".${local.workload_host}"))
    ) ? "${local.workload_cf_path}.${local.workload_instance}: ${local.workload_record_name} is outside this workload's host, ${local.workload_host}, in zones/${local.workload_parent}/zone.yaml (LIB-0037 §3)" : "",
  ]) : []
  guard_workload_nested = length(local.workload_nested_problems) > 0 ? file("${local.workload_file}: ${join("; ", local.workload_nested_problems)}") : true

  # Zone units (LIB-0036 §§1-4).
  guard_zones_file    = fileexists("${get_parent_terragrunt_dir()}/zones.yaml") ? file("zones.yaml is refused: each zone is zones/<zone>/zone.yaml, naming the workload that may write in it (LIB-0036 §1)") : true
  guard_zone_leaf     = local.is_zone_leaf ? file("${path_relative_to_include()} is a hand-written zone leaf, and those are retired: declare its entries in zones/${local.cloudflare_zone}/zone.yaml (LIB-0036 §4)") : true
  guard_zone_apex     = local.is_zone_unit && length(regexall("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", local.workload)) == 0 ? file("zones/${local.workload}/: a zone's directory must be its apex domain (LIB-0036 §1)") : true
  guard_zone_prefix   = local.is_zone_unit && length(regexall("^[a-z0-9-]+$", local.workload_prefix)) == 0 ? file("${local.workload_file}: prefix \"${local.workload_prefix}\" may hold only a-z, 0-9 and - (LIB-0036 §1)") : true
  guard_zone_own_zone = local.is_zone_unit && (can(local.workload_raw.cloudflare.zone) || can(local.workload_raw.cloudflare[local.workload_cf_yaml[local.workload_module]][local.workload_instance].zone)) ? file("${local.workload_file}: a zone's entries can't set zone; the directory names it (LIB-0036 §1)") : true
  guard_zone_secrets  = local.is_zone_unit && fileexists("${get_parent_terragrunt_dir()}/${local.workload_secrets_file}") ? file("${local.workload_secrets_file}: a zone has no secrets.yaml (LIB-0036, Out of scope)") : true
  guard_zone_workload = local.is_zone_unit && can(local.workload_raw.workload) ? file("${local.workload_file}: workload is refused since root.hcl v7.0.0; hosts names the workloads under workloads/${local.workload}/ (LIB-0037 §§3, 6)") : true
  # An apexRedirect is a shorthand with the old module's four inputs (LIB-0038
  # §3), and a target_url it can take a host from.
  zone_redirect_problems = flatten([for k, e in local.workload_cf_redirects : concat(
    [for x in sort(setsubtract(keys(e), local.workload_cf_redirect_keys)) : "cloudflare.apexRedirect.${k}.${x} isn't one of ${join(", ", local.workload_cf_redirect_keys)}; set it on the entry it expands into (LIB-0038 §3)"],
    local.workload_cf_redirect_host[k] == "" ? ["cloudflare.apexRedirect.${k}.target_url must be an absolute http:// or https:// URL (LIB-0038 §3)"] : [],
  )])
  guard_zone_redirect = length(local.zone_redirect_problems) > 0 ? file("${local.workload_file}: ${join("; ", local.zone_redirect_problems)}") : true
  # A unit file's shape (LIB-0039 §§1-2): its wrapper alone at the top, its
  # records at dnsRecords, and services and dnsRecords only in a wrapped file.
  workload_shape_problems = local.is_workload_leaf ? compact(concat(
    [for k in try(keys(local.workload_doc), []) : "${k} sits beside ${local.workload_wrapper}; everything goes under ${local.workload_wrapper} (LIB-0039 §1)" if local.workload_wrapped && k != local.workload_wrapper],
    [local.workload_wrapped && can(local.workload_in.cloudflare.dnsRecord) ? "${local.workload_wrapper}.cloudflare.dnsRecord moves to ${local.workload_wrapper}.dnsRecords (LIB-0039 §2)" : ""],
    [local.workload_wrapped && local.is_nested_workload && can(local.workload_in.services) ? "services is a zone's alone; declare a workload's records in workload.dnsRecords (LIB-0039 §3)" : ""],
    [!local.workload_wrapped && (can(local.workload_doc.services) || can(local.workload_doc.dnsRecords)) ? "services and dnsRecords are read only in a wrapped file; move the file's keys under ${local.workload_wrapper} (LIB-0039 §§1-3)" : ""],
  )) : []
  guard_workload_shape = length(local.workload_shape_problems) > 0 ? file("${local.workload_file}: ${join("; ", local.workload_shape_problems)}") : true
  # A zone's services (LIB-0039 §3): the four, each with its own keys, an
  # enabled one with its inputs, and one mail provider.
  zone_service_known = { proton = ["enabled", "verification", "dmarc"], fastmail = ["enabled", "dmarc"], googleSearch = ["enabled", "verification"], bluesky = ["enabled", "did"] }
  zone_service_problems = flatten([
    [for n, v in local.zone_services_all : "services.${n} isn't a service; known: proton, fastmail, googleSearch, bluesky (LIB-0039 §3)" if !contains(keys(local.zone_service_known), n)],
    [for n, v in local.zone_services_all : [for x in sort(setsubtract(try(keys(v), []), local.zone_service_known[n])) : "services.${n}.${x} isn't one of ${join(", ", local.zone_service_known[n])} (LIB-0039 §3)"] if contains(keys(local.zone_service_known), n)],
    contains(keys(local.workload_services), "proton") && (try(tostring(local.workload_services.proton.verification.pm), "") == "" || try(tostring(local.workload_services.proton.verification.protonmail), "") == "") ? ["services.proton.verification needs pm and protonmail (LIB-0039 §3)"] : [],
    contains(keys(local.workload_services), "googleSearch") && try(tostring(local.workload_services.googleSearch.verification), "") == "" ? ["services.googleSearch.verification must be a non-empty string (LIB-0039 §3)"] : [],
    contains(keys(local.workload_services), "bluesky") && try(tostring(local.workload_services.bluesky.did), "") == "" ? ["services.bluesky.did must be a non-empty string (LIB-0039 §3)"] : [],
    contains(keys(local.workload_services), "proton") && contains(keys(local.workload_services), "fastmail") ? ["services.proton and services.fastmail are both enabled, and both claim MX and SPF at @; enable one (LIB-0039 §3)"] : [],
    [for n, d in local.workload_service_dmarc : "services.${n}.dmarc must be true, false or a DMARC policy (LIB-0039 §3)" if d == null],
  ])
  guard_zone_services = length(local.zone_service_problems) > 0 ? file("${local.workload_file}: ${join("; ", local.zone_service_problems)}") : true
  # A zone's hosts (LIB-0037 §3): each names a workload in workloads/<zone>/,
  # and a host's names are its workload's, not the zone's.
  zone_hosts        = local.is_zone_unit ? try(local.zones[local.workload].hosts, {}) : {}
  zone_record_type  = upper(try(tostring(local.workload_cf_entry.type), ""))
  zone_missing_host = [for h, w in local.zone_hosts : w if !fileexists("${get_parent_terragrunt_dir()}/workloads/${local.workload}/${w}/workload.yaml")]
  guard_zone_hosts  = length(local.zone_missing_host) > 0 ? file("${local.workload_file}: hosts names ${join(", ", local.zone_missing_host)}, with no workloads/${local.workload}/<workload>/workload.yaml (LIB-0037 §3)") : true
  guard_zone_host_record = local.is_zone_unit && local.workload_module == "cloudflare/dns-record" && (
    anytrue([for h, w in local.zone_hosts : h != "@" && (local.workload_record_name == h || endswith(local.workload_record_name, ".${h}"))]) ||
    (contains(keys(local.zone_hosts), "@") && (local.workload_record_name == "www" || endswith(local.workload_record_name, ".www") || (local.workload_record_name == "@" && contains(["A", "AAAA", "CNAME"], local.zone_record_type))))
  ) ? file("${local.workload_file}: ${local.workload_dns_path}.${local.workload_instance}: ${local.workload_record_name} is a host's, in hosts (LIB-0037 §3)") : true

  # The leaf's module call. Inputs are written as literals -- JSON is HCL
  # expression syntax -- with template sequences escaped, since a `type = any`
  # variable set through TF_VAR_ would arrive as a string. Only wiring inputs
  # are variables, set by the stub from its dependencies' outputs. The whole
  # module is one output, so a dependent reads dependency.<name>.outputs.module.id.
  workload_tf = <<EOF
# Generated by root.hcl from ${local.workload_file} (LIB-0023) -- do not edit.
%{for k, type in local.workload_wiring~}
variable "${k}" {
  type    = ${type}
  default = null
}

%{endfor~}
%{for k, v in local.workload_sensitive~}
variable "${k}" {
  type      = string
  sensitive = true
}

%{endfor~}
# The workload's secrets.yaml env (LIB-0025 §3), for kinds that take one.
variable "workload_env" {
  type      = map(string)
  sensitive = true
  default   = {}
}

%{if local.workload_credentials_cloudflare~}
# The workload's Cloudflare token (LIB-0033 §4), for provider_cloudflare_generated.tf.
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

%{endif~}
%{if local.workload_credentials_scaleway~}
# The workload deployer's key (LIB-0024 §2), for provider_scaleway_generated.tf.
variable "scaleway_access_key" {
  type      = string
  sensitive = true
}

variable "scaleway_secret_key" {
  type      = string
  sensitive = true
}

%{endif~}
module "this" {
  source = "https://noisypigeon.garden/terraform/${local.workload_module}/v${local.workload_version}"
%{for k, v in local.workload_inputs~}
  ${k} = ${replace(replace(jsonencode(v), "$${", "$$${"), "%%{", "%%%{")}
%{endfor~}
%{for k, type in local.workload_wiring~}
  ${k} = var.${k}
%{endfor~}
%{for k, v in local.workload_sensitive~}
  ${k} = var.${k}
%{endfor~}
}

output "module" {
  value     = module.this
  sensitive = ${try(local.workload_kind.sensitive, false)}
}
EOF

  # Appended to cloudflare_ids_generated.tf for a zone leaf only. The zone's ID
  # is no longer here: dns-record v1 looks it up from this apex (LIB-0011).
  cloudflare_zone_locals = local.is_zone_leaf ? "\n  cloudflare_zone    = \"${local.cloudflare_zone}\"" : ""

  # Scaleway region/zone for the provider. The state backend below is always
  # fr-par regardless.
  scaleway_region = try(local.providers.scaleway.region, "fr-par")
  scaleway_zone   = try(local.providers.scaleway.zone, "fr-par-1")

  cloudflare_required_providers_entry = <<EOF
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
EOF

  scaleway_required_providers_entry = <<EOF
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
EOF

  grafana_required_providers_entry = <<EOF
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
EOF

  grafana_provider_block = <<EOF
# Scaleway Cockpit's managed Grafana, authenticated with an IAM API key secret
# the leaf supplies as local.grafana_auth_token (ADR-0135).
data "scaleway_cockpit_grafana" "grafana" {
  project_id = local.scaleway_project_id
}

provider "grafana" {
  url  = data.scaleway_cockpit_grafana.grafana.grafana_url
  auth = "anonymous"

  http_headers = {
    "X-Auth-Token" = local.grafana_auth_token
  }
}
EOF

  backblaze_required_providers_entry = <<EOF
    b2 = {
      source  = "registry.terraform.io/Backblaze/b2"
      version = "~> 0.14"
    }
EOF

  backblaze_provider_block = <<EOF
provider "b2" {
  application_key_id = "${local.backblaze_application_key_id}"
  application_key    = "${local.backblaze_application_key}"
}
EOF

  # Every required_providers entry this leaf gets, one complete entry at a
  # time, so a disabled provider adds nothing -- not even a blank line.
  # Terraform allows only one required_providers block per module, across all
  # generated files.
  required_providers_entries = join("", concat(
    local.cloudflare_enabled ? [local.cloudflare_required_providers_entry] : [],
    local.scaleway_enabled ? [local.scaleway_required_providers_entry] : [],
    [for name, p in local.extra_required_providers : "    ${name} = {\n      source  = \"${p.source}\"\n      version = \"${p.version}\"\n    }\n"],
    local.backblaze_enabled ? [local.backblaze_required_providers_entry] : [],
    local.grafana_enabled ? [local.grafana_required_providers_entry] : [],
  ))

  # What a generated file holds when its provider is off for this leaf. Written
  # rather than disabled, so it overwrites whatever an earlier version left in
  # the leaf's .terragrunt-cache.
  provider_off = "# Not enabled for this leaf -- see spoke.hcl's providers map (LIB-0005).\n"

  # Leaf values (LIB-0012 §1): every key <NAME> in terraform/secrets/env.enc
  # is exposed to every leaf, whatever its providers, as local.<name>
  # (ADR-0006). The file is the namespace, so there is no prefix.
  env_secrets = {
    for k, v in local.secrets_env : lower(k) => get_env(k, v)
  }

  # The key is the same whichever backend holds it (LIB-0001 invariant 4), so
  # moving a spoke between backends moves objects, never keys.
  state_key = "${path_relative_to_include()}/terraform.tfstate"

  scaleway_state_config = {
    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
    region                      = "fr-par"
    bucket                      = local.terraform_state_bucket_name
    key                         = local.state_key
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_lockfile                = true

    access_key = local.terraform_state_access_key_id
    secret_key = local.terraform_state_access_key
  }

  # R2 has no bucket versioning (LIB-0007), so Terragrunt must not try to
  # enable it or otherwise update the bucket; the offsite B2 copy stands in.
  cloudflare_state_config = {
    endpoints = {
      s3 = "https://${local.cloudflare_account_id}.eu.r2.cloudflarestorage.com"
    }
    region                      = "auto"
    bucket                      = local.terraform_state_bucket_name
    key                         = local.state_key
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_bucket_versioning      = true
    disable_bucket_update       = true
    use_lockfile                = true

    access_key = local.terraform_state_access_key_id
    secret_key = local.terraform_state_access_key
  }
}

exclude {
  if      = !local.is_valid_leaf
  actions = ["all_except_output"]
}

# A workload leaf's secrets (LIB-0025 §3), as TF_VAR_s for the sensitive
# variables in workload_generated.tf. Merged with the stub's own inputs, its
# wiring, which never share a name with these. Empty for every other leaf.
inputs = merge(
  { for k, v in local.workload_sensitive : k => v if local.is_workload_leaf },
  { for k in(local.is_workload_leaf ? ["workload_env"] : []) : k => local.workload_env },
)

# Every env.enc key, in every leaf (LIB-0012 §1).
generate "env_secrets" {
  path      = "env_secrets_generated.tf"
  if_exists = "overwrite"
  contents  = length(local.env_secrets) == 0 ? "# No terraform/secrets/env.enc keys (LIB-0012).\n" : <<EOF
locals {
${join("\n", [for k, v in local.env_secrets : "  ${k} = \"${v}\""])}
}
EOF
}

# What v2 named env_scaleway_secrets_generated.tf. Still written, as a comment,
# so a copy an earlier version left in a leaf or its .terragrunt-cache can't
# define the same locals twice.
generate "env_scaleway_secrets" {
  path      = "env_scaleway_secrets_generated.tf"
  if_exists = "overwrite"
  contents  = "# Moved to env_secrets_generated.tf (LIB-0010).\n"
}

generate "cloudflare_ids" {
  path      = "cloudflare_ids_generated.tf"
  if_exists = "overwrite"
  contents  = !local.cloudflare_enabled ? local.provider_off : <<EOF
locals {
  cloudflare_account_id              = "${local.cloudflare_account_id}"${local.cloudflare_zone_locals}
}
EOF
}

# The one required_providers block, for every provider this leaf gets.
generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_providers {
${local.required_providers_entries}  }
}
EOF
}

generate "provider_cloudflare" {
  path      = "provider_cloudflare_generated.tf"
  if_exists = "overwrite"
  contents  = !local.cloudflare_enabled ? local.provider_off : <<EOF
provider "cloudflare" {
  api_token = ${local.workload_credentials_cloudflare ? "var.cloudflare_api_token" : "\"${local.cloudflare_api_token}\""}
}
EOF
}

generate "provider_scaleway" {
  path      = "provider_scaleway_generated.tf"
  if_exists = "overwrite"
  contents  = !local.scaleway_enabled ? local.provider_off : <<EOF
provider "scaleway" {
  access_key      = ${local.workload_credentials_scaleway ? "var.scaleway_access_key" : "\"${local.scaleway_access_key}\""}
  secret_key      = ${local.workload_credentials_scaleway ? "var.scaleway_secret_key" : "\"${local.scaleway_secret_key}\""}
  organization_id = "${local.scaleway_organization_id}"
  zone            = "${local.scaleway_zone}"
  region          = "${local.scaleway_region}"
}
EOF
}

generate "provider_backblaze" {
  path      = "provider_backblaze_generated.tf"
  if_exists = "overwrite"
  contents  = local.backblaze_enabled ? local.backblaze_provider_block : local.provider_off
}

# An enabled leaf must define local.grafana_auth_token (ADR-0135).
generate "provider_grafana" {
  path      = "provider_grafana_generated.tf"
  if_exists = "overwrite"
  contents  = local.grafana_enabled ? local.grafana_provider_block : local.provider_off
}

generate "scaleway_ids" {
  path      = "scaleway_ids_generated.tf"
  if_exists = "overwrite"
  contents  = !local.scaleway_enabled ? local.provider_off : <<EOF
locals {
  scaleway_organization_id = "${local.scaleway_organization_id}"
  scaleway_project_id      = "${local.scaleway_project_id}"
  scaleway_s3_provider_name = "Scaleway"
}
EOF
}

# A workload leaf's module call (LIB-0023); a comment in every other leaf, so a
# copy an earlier run left in its .terragrunt-cache can't call anything.
generate "workload" {
  path      = "workload_generated.tf"
  if_exists = "overwrite"
  contents  = local.is_workload_leaf ? local.workload_tf : "# Not a workload leaf (LIB-0023).\n"
}

# The spoke's own dedicated Terraform state bucket (ADR-0130/0132/0133), on the
# backend spoke.hcl's state_backend picks (LIB-0007). The Scaleway one is always
# fr-par, regardless of any leaf's scaleway_region/scaleway_zone above. The key
# carries no prefix: with this file at the spoke's root and leaves under
# terraform/, it is terraform/<leaf>/terraform.tfstate -- byte-identical to what
# the per-domain roots in noisypigeon/noisypigeon produced (LIB-0001 invariant 4).
remote_state {
  backend = "s3"

  # Indexed rather than a conditional: the two configs have different keys,
  # which HCL's ?: refuses.
  config = {
    scaleway   = local.scaleway_state_config
    cloudflare = local.cloudflare_state_config
  }[local.state_backend]

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
}
