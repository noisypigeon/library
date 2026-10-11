resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "scaleway_instance_ip" "ipv6" {
  count = var.enabled && var.enable_ipv6 ? 1 : 0
  type  = "routed_ipv6"
}

resource "scaleway_instance_ip" "ipv4" {
  count = var.enabled && var.enable_ipv4 ? 1 : 0
  type  = "routed_ipv4"
}

# ADR-0145: bring-your-own Private Network attachment -- a separate resource
# (not an inline private_network block on scaleway_instance_server) so
# attaching/detaching never forces server replacement. count gates on
# enable_private_network, not on private_network_id != null -- the ID is
# frequently apply-time-unknown (e.g. a PN created in the same apply, as
# pigeon-cluster does), and count/for_each can never depend on such a value.
resource "scaleway_instance_private_nic" "private_nic" {
  count              = var.enabled && var.enable_private_network ? 1 : 0
  server_id          = scaleway_instance_server.server[0].id
  private_network_id = var.private_network_id
}

# ADR-0120: compute-instance composes block-volume internally for this one
# pairing, so callers configure instance_config.block_volume instead of
# wiring a separate module call themselves. ADR-0121: pinned to a released
# tag rather than a relative path, since a relative source escapes the
# module package once compute-instance itself is fetched over HTTP (e.g.
# the noisypigeon.com short URLs).
module "block_volume" {
  count  = var.enabled && var.instance_config.block_volume != null && var.instance_config.block_volume.size != null ? 1 : 0
  source = "https://pigeon.dev/modules/scaleway/block-volume/v4.0.0"

  name_prefix = var.name_prefix
  name_suffix = var.name_suffix
  size        = var.instance_config.block_volume.size
  iops        = var.instance_config.block_volume.iops
  project_id  = var.instance_config.block_volume.project_id
}

locals {
  attached_volume_ids = compact(concat(
    var.instance_config.block_volume != null ? [try(module.block_volume[0].id, null)] : [],
    var.instance_config.block_volume != null ? var.instance_config.block_volume.additional_volume_ids : []
  ))

  # ADR-0138: self_delete_on_exit must still run the post-provision unit even
  # when the caller passes zero post_provision_commands -- the self-delete
  # trap is the thing that has to execute, not the caller's own commands.
  post_provision_enabled = var.self_delete_on_exit || length(var.instance_config.post_provision_commands) > 0

  # ADR-0138: prepended as a trap (not appended after the caller's commands)
  # so it fires whether the post-provision script succeeds or fails --
  # post_provision_script runs under set -e, so a failing caller command
  # would otherwise abort the script before a plain appended call ever ran.
  # Uses the module's own composed iam_api_key credentials (ADR-0122) --
  # $${...} escapes the shell variable so Terraform doesn't try to
  # interpolate it itself.
  self_delete_script = !var.self_delete_on_exit ? "" : <<-SCRIPT
    export SCW_ACCESS_KEY="${try(module.iam_api_key[0].access_key, "")}"
    export SCW_SECRET_KEY="${try(module.iam_api_key[0].secret_key, "")}"
    export SCW_DEFAULT_PROJECT_ID="${try(var.iam_config.project_ids[0], "")}"
    SELF_ID=$(curl -fsSL http://169.254.42.42/conf?format=json | jq -r '.id')
    # ADR-0138: .location.zone_id is this module's best guess at the metadata
    # schema from docs alone -- confirm the real field path against a live
    # instance's http://169.254.42.42/conf?format=json before relying on this;
    # a wrong path means SELF_ZONE is empty and the instance never self-deletes.
    SELF_ZONE=$(curl -fsSL http://169.254.42.42/conf?format=json | jq -r '.location.zone_id')
    trap 'scw instance server delete $${SELF_ID} zone=$${SELF_ZONE} with-ip=true with-volumes=all force-shutdown=true' EXIT
    SCRIPT

  # Rendered once here (not inside the cloud_init heredoc's own %{for/if}
  # scanning) and base64-encoded below, so arbitrary caller-supplied shell
  # (quotes, $, backticks, %) never has to survive YAML or systemd
  # ExecStart= parsing (ADR-0125).
  post_provision_script = !local.post_provision_enabled ? null : <<-SCRIPT
    #!/bin/bash
    set -euo pipefail
    export PATH="/root/.local/bin:$PATH"
    cd /root
    ${local.self_delete_script}
    %{~for cmd in var.instance_config.post_provision_commands~}
    ${cmd}
    %{~endfor~}
  SCRIPT

  cloud_init = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - rclone
      - neovim
    %{~if var.self_delete_on_exit~}
      - jq
    %{~endif~}

    write_files:
      - path: /etc/profile.d/pigeon-env.sh
        permissions: '0600'
        defer: true
        content: |
          %{~for entry in var.keyring~}
          %{~if entry.secret_key != null~}
          export PIGEON_SECRET_${upper(replace(entry.alias, "-", "_"))}="${entry.secret_key}"
          %{~endif~}
          %{~endfor~}
          %{~if var.instance_config.cockpit != null~}
          export PIGEON_LOG_DIR="/var/log/pigeon"
          %{~endif~}
      - path: /etc/environment
        permissions: '0600'
        defer: true
        append: true
        content: |
          %{~for entry in var.keyring~}
          %{~if entry.secret_key != null~}
          PIGEON_SECRET_${upper(replace(entry.alias, "-", "_"))}="${entry.secret_key}"
          %{~endif~}
          %{~endfor~}
          %{~if var.instance_config.cockpit != null~}
          PIGEON_LOG_DIR="/var/log/pigeon"
          %{~endif~}
      - path: /root/.config/rclone/rclone.conf
        permissions: '0600'
        defer: true
        content: |
          %{~for entry in var.keyring~}
          %{~if entry.kind == "bucket"~}
          [${entry.alias}]
          type = alias
          remote = ${entry.bucket}:${entry.bucket}
          [${entry.bucket}]
          type = s3
          provider = ${entry.provider}
          access_key_id = ${entry.access_key_id}
          secret_access_key = ${entry.secret_key}
          endpoint = ${entry.endpoint}
          acl = private
          no_check_bucket = true
          %{~endif~}
          %{~endfor~}
      - path: /root/.config/pigeon/keyring.toml
        permissions: '0600'
        defer: true
        content: |
          %{~for entry in var.keyring~}
          [[entries]]
          kind = "${entry.kind}"
          alias = "${entry.alias}"
          %{~if entry.kind == "email"~}
          email = "${entry.email}"
          provider = "${entry.provider}"
          host = "${entry.host}"
          port = ${entry.port}
          %{~if entry.max_imap_connections != null~}
          max_imap_connections = ${entry.max_imap_connections}
          %{~endif~}
          %{~endif~}
          %{~if entry.kind == "bucket"~}
          endpoint = "${entry.endpoint}"
          bucket = "${entry.bucket}"
          access_key_id = "${entry.access_key_id}"
          %{~if entry.encryption_key_alias != null~}
          encryption_key_alias = "${entry.encryption_key_alias}"
          %{~endif~}
          %{~endif~}
          %{~if entry.kind == "encryption-key"~}
          created_at = "${entry.created_at}"
          %{~endif~}

          %{~endfor~}
    %{~if var.instance_config.cockpit != null~}
      - path: /etc/alloy/config.alloy
        permissions: '0644'
        defer: true
        content: |
          prometheus.exporter.unix "node" { }

          // Alloy's default `instance` label is the scraped address
          // (e.g. "localhost:9091"), identical on every host -- useless
          // once every instance shares one Cockpit store (ADR-0103).
          // discovery.relabel overrides it to the real hostname, the
          // standard Alloy/Prometheus idiom for this.
          discovery.relabel "node_with_instance" {
            targets = prometheus.exporter.unix.node.targets
            rule {
              target_label = "instance"
              replacement  = constants.hostname
            }
          }

          prometheus.scrape "node" {
            scrape_interval = "60s"
            targets         = discovery.relabel.node_with_instance.output
            forward_to      = [prometheus.remote_write.cockpit.receiver]
          }

          discovery.relabel "pigeon_cli_with_instance" {
            targets = [{"__address__" = "localhost:${var.instance_config.cockpit.scrape_port}"}]
            rule {
              target_label = "instance"
              replacement  = constants.hostname
            }
          }

          prometheus.scrape "pigeon_cli" {
            scrape_interval = "15s"
            targets         = discovery.relabel.pigeon_cli_with_instance.output
            forward_to      = [prometheus.remote_write.cockpit.receiver]
          }

          prometheus.remote_write "cockpit" {
            endpoint {
              url = "${var.instance_config.cockpit.metrics_push_url}"
              headers = {
                "X-TOKEN" = "${var.instance_config.cockpit.token_secret}",
              }
            }
          }

          local.file_match "pigeon_logs" {
            path_targets = [{"__path__" = "/var/log/pigeon/pigeon.jsonl"}]
          }

          loki.source.file "pigeon_logs" {
            targets    = local.file_match.pigeon_logs.targets
            forward_to = [loki.process.pigeon_logs.receiver]
          }

          // Two fixes needed once every instance shares one Loki store
          // (ADR-0103): (1) pigeon-cli's JSONL already carries its own
          // event timestamp, which was previously shown a second time,
          // redundantly, next to Loki's own per-entry ingest timestamp --
          // stage.timestamp makes Loki's real timestamp *be* that field
          // instead of a second, independently-drifting clock. (2) with
          // no labels set, every instance's logs land in the same
          // unlabeled stream -- extract pigeon-cli's `command`/`instance`
          // span fields (ADR-0093) into real Loki labels so the shared
          // store stays filterable per-job/per-host. `spans[0]` is always
          // the outermost ("command") span per pigeon-cli's schema, except
          // on the one auto-emitted span-close event per run, where
          // `spans` is empty -- that single line per run won't get these
          // two labels; exact JMESPath syntax here should be verified
          // against Alloy's current stage.json docs when first applied.
          loki.process "pigeon_logs" {
            stage.json {
              expressions = {
                ts       = "timestamp",
                pigeon_job = "spans[0].command",
                instance = "spans[0].instance",
              }
            }

            stage.timestamp {
              source = "ts"
              format = "RFC3339Nano"
            }

            stage.labels {
              values = {
                pigeon_job = "",
                instance   = "",
              }
            }

            forward_to = [loki.write.cockpit.receiver]
          }

          loki.write "cockpit" {
            endpoint {
              url = "${var.instance_config.cockpit.logs_push_url}"
              headers = {
                "X-TOKEN" = "${var.instance_config.cockpit.token_secret}",
              }
            }
          }
    %{~endif~}
    %{~if local.post_provision_enabled~}
      - path: /etc/systemd/system/pigeon-post-provision.service
        permissions: '0644'
        defer: true
        content: |
          [Unit]
          Description=Pigeon post-provision commands (ADR-0125), run once cloud-init has genuinely finished
          After=cloud-final.service
          Wants=cloud-final.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          WorkingDirectory=/root
          EnvironmentFile=-/etc/environment
          ExecStart=/bin/bash /root/.config/pigeon/post-provision.sh
          ExecStartPost=/bin/systemctl disable pigeon-post-provision.service

          [Install]
          WantedBy=multi-user.target
      - path: /root/.config/pigeon/post-provision.sh
        permissions: '0600'
        defer: true
        encoding: b64
        content: ${base64encode(local.post_provision_script)}
    %{~endif~}

    runcmd:
      - export HOME=/root
      - . /etc/profile.d/pigeon-env.sh
    %{~if length(local.attached_volume_ids) > 0~}
      - mkfs.ext4 -L data /dev/sdb
      - mkdir -p /mnt/data
      - mount /dev/sdb /mnt/data
      - UUID=$(blkid -s UUID -o value /dev/sdb)
      - echo "UUID=$UUID /mnt/data ext4 defaults,nofail 0 2" >> /etc/fstab
      - mount -a
    %{~endif~}
      - curl -fsSL https://mise.run | sh
      - echo 'eval "$(/root/.local/bin/mise activate bash)"' >> /root/.bashrc
      - curl -fsSL https://gist.githubusercontent.com/noisypigeon/1e96e8ef94380f913f6ae02782965149/raw/pigeon.sh | bash
    %{~if var.instance_config.enable_transcoding~}
      # ADR-0150, renamed by ADR-0151: a general-purpose ffmpeg for
      # pigeon-cli transform. This third-party PPA is used rather than
      # Ubuntu's own archive build because the archive build isn't compiled
      # with --enable-libheif, so it can't decode .heic input.
      - apt-get install -y software-properties-common
      - add-apt-repository -y ppa:savoury1/ffmpeg4
      - apt-get update
      - DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg
    %{~endif~}
    %{~if var.instance_config.cockpit != null~}
      - mkdir -p /etc/apt/keyrings
      - wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg.key
      - echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null
      - apt-get update
      - DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" alloy
      - systemctl enable alloy
      - systemctl restart alloy
    %{~endif~}
    %{~if var.self_delete_on_exit~}
      - curl -fsSL https://raw.githubusercontent.com/scaleway/scaleway-cli/main/scripts/get.sh | sh
    %{~endif~}
    %{~if local.post_provision_enabled~}
      - systemctl daemon-reload
      - systemctl --no-block enable --now pigeon-post-provision.service
    %{~endif~}
  EOF
}

resource "terraform_data" "cloud_init" {
  input = md5(local.cloud_init)
}

resource "scaleway_instance_server" "server" {
  count = var.enabled ? 1 : 0

  name  = "${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"
  image = var.instance_config.image
  type  = var.instance_config.type
  ip_ids = compact([
    var.enable_ipv4 ? scaleway_instance_ip.ipv4[0].id : null,
    var.enable_ipv6 ? scaleway_instance_ip.ipv6[0].id : null,
  ])
  tags                  = var.user_config.ssh_key != null ? ["AUTHORIZED_KEY=${replace(var.user_config.ssh_key, " ", "_")}"] : []
  additional_volume_ids = local.attached_volume_ids

  user_data = {
    cloud-init = local.cloud_init
  }

  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init.output]
  }
}

# ADR-0126: giving the server a kill switch moves it from a singleton
# resource to count = var.enabled ? 1 : 0, changing its address. This
# protects any existing state through that change for any caller.
moved {
  from = scaleway_instance_server.server
  to   = scaleway_instance_server.server[0]
}
