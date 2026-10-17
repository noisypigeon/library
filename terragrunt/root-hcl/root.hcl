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
  provider_on = {
    for name in local.known_providers : name => contains(keys(local.providers), name) && (
      length(try(local.providers[name].leaves, [])) == 0 ||
      anytrue([for prefix in try(local.providers[name].leaves, []) : startswith(local.leaf, prefix)])
    )
  }

  cloudflare_enabled = local.provider_on.cloudflare
  scaleway_enabled   = local.provider_on.scaleway
  backblaze_enabled  = local.provider_on.backblaze
  grafana_enabled    = local.provider_on.grafana

  # Breakglass (LIB-0014): a provider's entry may set
  #
  #   scaleway = { breakglass = { leaves = ["terraform/scaleway/terraform-deployer-iam/"] } }
  #
  # and a leaf under one of those prefixes, with the provider on, then reads
  # that provider's credentials from <provider>_breakglass.enc. There is no
  # "every leaf" default: a breakglass key every leaf reads is just a second
  # provider key, so leaves is required.
  breakglass_providers = [for name in local.known_providers : name if can(local.providers[name].breakglass)]
  breakglass_on = {
    for name in local.known_providers : name => local.provider_on[name] && contains(local.breakglass_providers, name) &&
    anytrue([for prefix in try(local.providers[name].breakglass.leaves, []) : startswith(local.leaf, prefix)])
  }

  # Misconfigurations fail the run rather than silently dropping a provider.
  # Terragrunt has no assert, so each guard reads a file whose name is the
  # message when its condition fails.
  guard_legacy_flags = anytrue([for k in ["backblaze", "grafana"] : contains(keys(local.spoke.locals), k)]) ? file("spoke.hcl sets backblaze/grafana: root.hcl v2 reads providers only (LIB-0005); move them into the providers map and delete any *_config.hcl") : true
  guard_unknown      = length(local.unknown_providers) > 0 ? file("spoke.hcl providers has unknown keys ${join(", ", local.unknown_providers)}; known: ${join(", ", local.known_providers)}") : true
  guard_prefixes     = alltrue([for p in local.provider_prefixes : endswith(p, "/")]) ? true : file("spoke.hcl providers: every leaves prefix must end in a slash, or it matches sibling paths too")
  guard_backend      = contains(local.known_state_backend, local.state_backend) ? true : file("spoke.hcl state_backend is ${local.state_backend}; known: ${join(", ", local.known_state_backend)}")
  guard_grafana      = local.grafana_enabled && !local.scaleway_enabled ? file("providers.grafana is on for ${path_relative_to_include()} but providers.scaleway is not; its data source needs the Scaleway provider") : true
  guard_bucket_key   = contains(keys(local.spoke.locals), "state_bucket_secret") ? file("spoke.hcl sets state_bucket_secret: root.hcl v3 reads the state bucket from TERRAFORM_STATE_BUCKET_NAME (LIB-0010) in terraform/secrets/terraform.enc; delete state_bucket_secret") : true
  guard_r2_account   = local.state_backend == "cloudflare" && !contains(keys(local.providers), "cloudflare") ? file("spoke.hcl state_backend is cloudflare but providers has no cloudflare; the R2 endpoint is built from CLOUDFLARE_PROVIDER_ACCOUNT_ID in terraform/secrets/cloudflare.enc (LIB-0010, LIB-0012)") : true
  guard_breakglass_leaves = alltrue([for name in local.breakglass_providers : length(try(local.providers[name].breakglass.leaves, [])) > 0]) ? true : file("spoke.hcl providers sets breakglass without leaves for ${join(", ", [for name in local.breakglass_providers : name if length(try(local.providers[name].breakglass.leaves, [])) == 0])}; breakglass must list the leaves allowed to use it (LIB-0014)")
  guard_breakglass_file   = alltrue([for name in local.breakglass_providers : contains(keys(local.secret_files), "${name}_breakglass")]) ? true : file("spoke.hcl providers sets breakglass for ${join(", ", [for name in local.breakglass_providers : name if !contains(keys(local.secret_files), "${name}_breakglass")])}, which has no <provider>_breakglass file in secrets-schema.json (LIB-0014)")
  guard_r2_backup    = local.state_backend == "cloudflare" && local.state_backup != true ? file("spoke.hcl state_backend is cloudflare but state_backup is not true; R2 can't version objects, so its state must be backed up to B2 (LIB-0007, LIB-0012)") : true

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
  # root is included from outside <spoke>/terraform/ is excluded.
  path_segments = split("/", path_relative_to_include())
  is_valid_leaf = length(local.path_segments) >= 1 && local.path_segments[0] == "terraform"

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

    access_key = local.terraform_state_access_key_id
    secret_key = local.terraform_state_access_key
  }
}

exclude {
  if      = !local.is_valid_leaf
  actions = ["all_except_output"]
}

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
  api_token = "${local.cloudflare_api_token}"
}
EOF
}

generate "provider_scaleway" {
  path      = "provider_scaleway_generated.tf"
  if_exists = "overwrite"
  contents  = !local.scaleway_enabled ? local.provider_off : <<EOF
provider "scaleway" {
  access_key      = "${local.scaleway_access_key}"
  secret_key      = "${local.scaleway_secret_key}"
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
