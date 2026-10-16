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

locals {
  # The spoke's instance values. Missing spoke.hcl is a hard error, which is
  # what we want: guessing a state bucket is how a plan lands in the wrong one.
  spoke = read_terragrunt_config("${get_parent_terragrunt_dir()}/spoke.hcl")

  # Optional spoke.hcl extensions (LIB-0003 amendments: v1.1.0, v1.2.0). All
  # default to off, and off renders byte-identically to v1.0.1.
  #
  # extra_required_providers: { <name> = { source = "...", version = "..." } },
  # appended to the one required_providers block. A provider's configuration,
  # if it needs any, lives in the leaf that uses it.
  extra_required_providers = lookup(local.spoke.locals, "extra_required_providers", {})

  # backblaze: turns on DEV-0148's latent Backblaze B2 provider. Even then it
  # stays inert for any leaf that does not drop a sibling backblaze_config.hcl
  # setting `enabled = true`.
  backblaze_supported = lookup(local.spoke.locals, "backblaze", false)

  # grafana: turns on a latent Scaleway Cockpit Grafana provider (v1.2.0). It
  # stays inert for any leaf without a sibling grafana_config.hcl setting
  # `enabled = true`. An enabled leaf must define local.grafana_auth_token -- the
  # Cockpit API key secret the provider authenticates with (ADR-0135).
  grafana_supported = lookup(local.spoke.locals, "grafana", false)

  # Name of the secrets.enc key (or environment variable) holding the spoke's
  # own Terraform state bucket name, e.g. PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME.
  state_bucket_secret = local.spoke.locals.state_bucket_secret

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

  backblaze_application_key_id = get_env("BACKBLAZE_APPLICATION_KEY_ID", lookup(local.secrets, "BACKBLAZE_APPLICATION_KEY_ID", ""))
  backblaze_application_key    = get_env("BACKBLAZE_APPLICATION_KEY", lookup(local.secrets, "BACKBLAZE_APPLICATION_KEY", ""))

  # Enforce the terraform/<leaf> convention (ADR-0092, ADR-0096): anything this
  # root is included from outside <spoke>/terraform/ is excluded.
  path_segments = split("/", path_relative_to_include())
  is_valid_leaf = length(local.path_segments) >= 1 && local.path_segments[0] == "terraform"

  # Per-leaf Scaleway region/zone override (ADR-0098) -- every leaf defaults to
  # fr-par unless it drops a sibling scaleway_config.hcl.
  workload_dir             = dirname(find_in_parent_folders("root.hcl"))
  workload_definition_path = "${local.workload_dir}/${path_relative_to_include()}/scaleway_config.hcl"
  workload_definition      = read_terragrunt_config(local.workload_definition_path, { locals = {} })
  scaleway_region          = lookup(local.workload_definition.locals, "scaleway_region", "fr-par")
  scaleway_zone            = lookup(local.workload_definition.locals, "scaleway_zone", "fr-par-1")

  # Per-leaf Backblaze opt-in (DEV-0148), the same read_terragrunt_config
  # default-fallback mechanism as scaleway_config.hcl, only consulted when the
  # spoke supports Backblaze at all.
  backblaze_config_path = "${local.workload_dir}/${path_relative_to_include()}/backblaze_config.hcl"
  backblaze_config      = read_terragrunt_config(local.backblaze_config_path, { locals = {} })
  backblaze_enabled     = local.backblaze_supported && lookup(local.backblaze_config.locals, "enabled", false)

  grafana_config_path = "${local.workload_dir}/${path_relative_to_include()}/grafana_config.hcl"
  grafana_config      = read_terragrunt_config(local.grafana_config_path, { locals = {} })
  grafana_enabled     = local.grafana_supported && lookup(local.grafana_config.locals, "enabled", false)

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

  # Everything appended to required_providers, one complete line at a time, so
  # an empty extension adds nothing -- not even a blank line. Terraform allows
  # only one required_providers block per module, across all generated files.
  required_providers_extension = join("", concat(
    [for name, p in local.extra_required_providers : "    ${name} = {\n      source  = \"${p.source}\"\n      version = \"${p.version}\"\n    }\n"],
    local.backblaze_enabled ? [local.backblaze_required_providers_entry] : [],
    local.grafana_enabled ? [local.grafana_required_providers_entry] : [],
  ))

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
}

exclude {
  if      = !local.is_valid_leaf
  actions = ["all_except_output"]
}

generate "env_scaleway_secrets" {
  path      = "env_scaleway_secrets_generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
  locals {
  ${join("\n", [for k, v in local.env_scaleway_secrets : "  ${k} = \"${v}\""])}
  }
  EOF
}

generate "cloudflare_ids" {
  path      = "cloudflare_ids_generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
locals {
  cloudflare_account_id              = "${local.cloudflare_account_id}"
  ${join("\n", [for k, v in local.env_cloudflare_secrets : "  ${k} = \"${v}\""])}
}
EOF
}

generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
${local.required_providers_extension}  }
}

provider "cloudflare" {
  api_token = "${local.cloudflare_api_token}"
}

provider "scaleway" {
  access_key      = "${local.scaleway_access_key}"
  secret_key      = "${local.scaleway_secret_key}"
  organization_id = "${local.scaleway_organization_id}"
  zone            = "${local.scaleway_zone}"
  region          = "${local.scaleway_region}"
}
EOF
}

# Only generated for a spoke that supports Backblaze. Within such a spoke, a
# leaf that has not opted in gets a comment-only file, as DEV-0148 designed.
generate "provider_backblaze" {
  path      = "provider_backblaze_generated.tf"
  if_exists = "overwrite"
  disable   = !local.backblaze_supported
  contents  = local.backblaze_enabled ? local.backblaze_provider_block : "# Backblaze not enabled for this leaf -- see backblaze_config.hcl.\n"
}

# Only generated for a spoke that supports Grafana. Within such a spoke, a leaf
# that has not opted in gets a comment-only file.
generate "provider_grafana" {
  path      = "provider_grafana_generated.tf"
  if_exists = "overwrite"
  disable   = !local.grafana_supported
  contents  = local.grafana_enabled ? local.grafana_provider_block : "# Grafana not enabled for this leaf -- see grafana_config.hcl.\n"
}

generate "scaleway_ids" {
  path      = "scaleway_ids_generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
locals {
  scaleway_organization_id = "${local.scaleway_organization_id}"
  scaleway_project_id      = "${local.scaleway_project_id}"
  scaleway_s3_provider_name = "Scaleway"
}
EOF
}

# The spoke's own dedicated Terraform state bucket (ADR-0130/0132/0133). Always
# fr-par, regardless of any leaf's scaleway_region/scaleway_zone above. The key
# carries no prefix: with this file at the spoke's root and leaves under
# terraform/, it is terraform/<leaf>/terraform.tfstate -- byte-identical to what
# the per-domain roots in noisypigeon/noisypigeon produced (LIB-0001 invariant 4).
remote_state {
  backend = "s3"

  config = {
    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
    region                      = "fr-par"
    bucket                      = local.terraform_state_bucket_name
    key                         = "${path_relative_to_include()}/terraform.tfstate"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    access_key = local.scaleway_access_key
    secret_key = local.scaleway_secret_key
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
}
