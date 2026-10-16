# pigeon-lib's spoke root.hcl template (LIB-0001 §6, LIB-0003).
#
# GENERATED in a spoke -- do not edit there. .github/scripts/resolve-root-hcl.sh
# copies this file to the spoke's repo root at the version the spoke's
# spoke.hcl pins (root_hcl_version); the spoke commits the copy, and its CI runs
# the same script with --check to fail on any drift. To change it, change it in
# pigeon-lib and bump root_hcl_version. Every leaf under <spoke>/terraform/
# includes it with find_in_parent_folders("root.hcl"). Materialized rather than
# included from the library clone because Terragrunt does not support nested
# includes (DEV-0059), and because a leaf's path_relative_to_include() -- its
# state key -- is relative to this file's own directory, which has to be the
# spoke's root (LIB-0001 invariant 4). Committed rather than gitignored because
# Terragrunt's [main...HEAD] filter plans inside git worktrees, where only
# tracked files exist.
#
# Generalized from the three per-domain root.hcl files in noisypigeon/noisypigeon
# (pigeon.dev/, noisypigeon.com/, willowgraysen.com/), which differed only in
# what spoke.hcl now supplies. Everything a spoke varies comes from spoke.hcl;
# everything else is one copy here.
#
# Since v2.0.0 (LIB-0005) that includes which providers a leaf gets: spoke.hcl's
# required `providers` map enables and configures each one, optionally scoped
# to leaf path prefixes. There are no per-leaf *_config.hcl files.
#
# Since v2.1.0 (LIB-0007) spoke.hcl may also set `state_backend` to keep state
# in Cloudflare R2 instead of Scaleway Object Storage.

locals {
  # The spoke's instance values. Missing spoke.hcl is a hard error, which is
  # what we want: guessing a state bucket is how a plan lands in the wrong one.
  spoke = read_terragrunt_config("${get_parent_terragrunt_dir()}/spoke.hcl")

  # The providers this spoke uses, and how (LIB-0005). Required: a spoke.hcl
  # without it is a hard error, like a missing state_bucket_secret.
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
  provider_prefixes = flatten([for name, cfg in local.providers : try(cfg.leaves, [])])

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

  # Misconfigurations fail the run rather than silently dropping a provider.
  # Terragrunt has no assert, so each guard reads a file whose name is the
  # message when its condition fails.
  guard_legacy_flags = anytrue([for k in ["backblaze", "grafana"] : contains(keys(local.spoke.locals), k)]) ? file("spoke.hcl sets backblaze/grafana: root.hcl v2 reads providers only (LIB-0005); move them into the providers map and delete any *_config.hcl") : true
  guard_unknown      = length(local.unknown_providers) > 0 ? file("spoke.hcl providers has unknown keys ${join(", ", local.unknown_providers)}; known: ${join(", ", local.known_providers)}") : true
  guard_prefixes     = alltrue([for p in local.provider_prefixes : endswith(p, "/")]) ? true : file("spoke.hcl providers: every leaves prefix must end in a slash, or it matches sibling paths too")
  guard_backend      = contains(local.known_state_backend, local.state_backend) ? true : file("spoke.hcl state_backend is ${local.state_backend}; known: ${join(", ", local.known_state_backend)}")
  guard_grafana      = local.grafana_enabled && !local.scaleway_enabled ? file("providers.grafana is on for ${path_relative_to_include()} but providers.scaleway is not; its data source needs the Scaleway provider") : true

  # extra_required_providers: { <name> = { source = "...", version = "..." } },
  # appended to the one required_providers block (LIB-0003 v1.1.0). A
  # provider's configuration, if it needs any, lives in the leaf that uses it.
  extra_required_providers = lookup(local.spoke.locals, "extra_required_providers", {})

  # Name of the secrets.enc key (or environment variable) holding the spoke's
  # own Terraform state bucket name, e.g. PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME.
  state_bucket_secret = local.spoke.locals.state_bucket_secret

  # Where that bucket lives (LIB-0007): "scaleway" (the default) or
  # "cloudflare", an EU-jurisdiction R2 bucket (LIB-0006). One backend per
  # spoke -- Terraform allows exactly one per leaf.
  state_backend       = lookup(local.spoke.locals, "state_backend", "scaleway")
  known_state_backend = ["scaleway", "cloudflare"]

  # Secrets: decrypted in-memory from the spoke's terraform/secrets.enc via
  # sops/age (ADR-0123, ADR-0131). No plaintext copy ever touches disk, and
  # nothing ever falls back to another repo's secrets.
  secrets_enc_path = find_in_parent_folders("secrets.enc", "")

  secrets_decrypted = local.secrets_enc_path != "" ? run_cmd(
    "--terragrunt-quiet", "sops", "--decrypt",
    "--input-type", "dotenv", "--output-type", "dotenv",
    local.secrets_enc_path
  ) : ""

  secrets = { for pair in [
    for line in split("\n", local.secrets_decrypted) :
    regex("^([^=]+)=(.*)$", trimspace(line))
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
    && !startswith(trimspace(line), "sops_")
    && can(regex("^([^=]+)=(.*)$", trimspace(line)))
  ] : trimspace(pair[0]) => trimspace(pair[1]) }

  cloudflare_api_token  = get_env("CLOUDFLARE_TOKEN", lookup(local.secrets, "CLOUDFLARE_TOKEN", ""))
  cloudflare_account_id = get_env("CLOUDFLARE_ACCOUNT_ID", lookup(local.secrets, "CLOUDFLARE_ACCOUNT_ID", ""))

  scaleway_access_key      = get_env("SCALEWAY_ACCESS_KEY", lookup(local.secrets, "SCALEWAY_ACCESS_KEY", ""))
  scaleway_secret_key      = get_env("SCALEWAY_SECRET_KEY", lookup(local.secrets, "SCALEWAY_SECRET_KEY", ""))
  scaleway_organization_id = get_env("SCALEWAY_ORGANIZATION_ID", lookup(local.secrets, "SCALEWAY_ORGANIZATION_ID", ""))
  scaleway_project_id      = get_env("SCALEWAY_PROJECT_ID", lookup(local.secrets, "SCALEWAY_PROJECT_ID", ""))

  # R2's S3-compatible keys, for the state backend only (LIB-0007). Cloudflare
  # has no Terraform resource for them, so they are created by hand in the
  # dashboard. Read whether or not the cloudflare provider is on for the leaf.
  cloudflare_r2_access_key_id     = get_env("CLOUDFLARE_R2_ACCESS_KEY_ID", lookup(local.secrets, "CLOUDFLARE_R2_ACCESS_KEY_ID", ""))
  cloudflare_r2_secret_access_key = get_env("CLOUDFLARE_R2_SECRET_ACCESS_KEY", lookup(local.secrets, "CLOUDFLARE_R2_SECRET_ACCESS_KEY", ""))

  backblaze_application_key_id = get_env("BACKBLAZE_APPLICATION_KEY_ID", lookup(local.secrets, "BACKBLAZE_APPLICATION_KEY_ID", ""))
  backblaze_application_key    = get_env("BACKBLAZE_APPLICATION_KEY", lookup(local.secrets, "BACKBLAZE_APPLICATION_KEY", ""))

  # Enforce the terraform/<leaf> convention (ADR-0092, ADR-0096): anything this
  # root is included from outside <spoke>/terraform/ is excluded.
  path_segments = split("/", path_relative_to_include())
  is_valid_leaf = length(local.path_segments) >= 1 && local.path_segments[0] == "terraform"

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

  # Injected secrets/sensitive values: any secrets.enc key prefixed ENV_SW_ or
  # ENV_CF_ is exposed as a local named after the rest of the key (ADR-0006).
  env_scaleway_secrets = {
    for k, v in local.secrets : "${lower(trimprefix(k, "ENV_SW_"))}" => get_env(k, v)
    if startswith(k, "ENV_SW_")
  }

  env_cloudflare_secrets = {
    for k, v in local.secrets : "${lower(trimprefix(k, "ENV_CF_"))}" => get_env(k, v)
    if startswith(k, "ENV_CF_")
  }

  terraform_state_bucket_name = get_env(local.state_bucket_secret, lookup(local.secrets, local.state_bucket_secret, ""))

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

    access_key = local.scaleway_access_key
    secret_key = local.scaleway_secret_key
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

    access_key = local.cloudflare_r2_access_key_id
    secret_key = local.cloudflare_r2_secret_access_key
  }
}

exclude {
  if      = !local.is_valid_leaf
  actions = ["all_except_output"]
}

generate "env_scaleway_secrets" {
  path      = "env_scaleway_secrets_generated.tf"
  if_exists = "overwrite"
  contents  = !local.scaleway_enabled ? local.provider_off : <<EOF
  locals {
  ${join("\n", [for k, v in local.env_scaleway_secrets : "  ${k} = \"${v}\""])}
  }
  EOF
}

generate "cloudflare_ids" {
  path      = "cloudflare_ids_generated.tf"
  if_exists = "overwrite"
  contents  = !local.cloudflare_enabled ? local.provider_off : <<EOF
locals {
  cloudflare_account_id              = "${local.cloudflare_account_id}"
  ${join("\n", [for k, v in local.env_cloudflare_secrets : "  ${k} = \"${v}\""])}
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
