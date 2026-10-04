resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "scaleway_instance_ip" "ipv6" {
  count = var.enable_ipv6 ? 1 : 0
  type  = "routed_ipv6"
}

resource "scaleway_instance_ip" "ipv4" {
  count = var.enable_ipv4 ? 1 : 0
  type  = "routed_ipv4"
}

locals {
  cloud_init = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
    %{~if var.profile == "docker"~}
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
    %{~endif~}
    %{~if var.profile == "pigeon-cli"~}
      - rclone
      - neovim
    %{~endif~}

    write_files:
      - path: /etc/profile.d/pigeon-env.sh
        permissions: '0600'
        defer: true
        content: |
          %{~for key, value in var.environment_variables~}
          export ${key}="${value}"
          %{~endfor~}
          %{~if var.cockpit != null~}
          export PIGEON_LOG_DIR="/var/log/pigeon"
          %{~endif~}
      - path: /etc/environment
        permissions: '0600'
        defer: true
        append: true
        content: |
          %{~for key, value in var.environment_variables~}
          ${key}="${value}"
          %{~endfor~}
          %{~if var.cockpit != null~}
          PIGEON_LOG_DIR="/var/log/pigeon"
          %{~endif~}
    %{~if var.profile == "pigeon-cli"~}
      - path: /root/.config/rclone/rclone.conf
        permissions: '0600'
        defer: true
        content: |
          %{~for bucket in var.buckets~}
          [${bucket.bucket_alias}]
          type = alias
          remote = ${bucket.bucket_name}:${bucket.bucket_name}
          [${bucket.bucket_name}]
          type = s3
          provider = ${bucket.bucket_provider}
          access_key_id = ${bucket.bucket_access_key}
          secret_access_key = ${bucket.bucket_secret_key}
          endpoint = ${bucket.bucket_endpoint}
          acl = private
          no_check_bucket = true
          %{~endfor~}
      - path: /root/.config/pigeon/keyring.toml
        permissions: '0600'
        defer: true
        content: |
          %{~for entry in var.keyring_entries~}
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
    %{~endif~}
    %{~if var.cockpit != null~}
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
            targets = [{"__address__" = "localhost:${var.cockpit.scrape_port}"}]
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
              url = "${var.cockpit.metrics_push_url}"
              headers = {
                "X-TOKEN" = "${var.cockpit.token_secret}",
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
              url = "${var.cockpit.logs_push_url}"
              headers = {
                "X-TOKEN" = "${var.cockpit.token_secret}",
              }
            }
          }
    %{~endif~}

    runcmd:
      - export HOME=/root
      - . /etc/profile.d/pigeon-env.sh
    %{~if length(var.additional_volume_ids) > 0~}
      - mkfs.ext4 -L data /dev/sdb
      - mkdir -p /mnt/data
      - mount /dev/sdb /mnt/data
      - UUID=$(blkid -s UUID -o value /dev/sdb)
      - echo "UUID=$UUID /mnt/data ext4 defaults,nofail 0 2" >> /etc/fstab
      - mount -a
    %{~endif~}
      - curl -fsSL https://mise.run | sh
      - echo 'eval "$(/root/.local/bin/mise activate bash)"' >> /root/.bashrc
    %{~if var.profile == "docker"~}
      - mkdir -p /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      - apt-get update
      - apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      - systemctl enable docker
      - systemctl start docker
    %{~endif~}
    %{~if var.profile == "pigeon-cli"~}
      - curl -fsSL https://gist.githubusercontent.com/noisypigeon/1e96e8ef94380f913f6ae02782965149/raw/pigeon.sh | bash
    %{~endif~}
    %{~if var.cockpit != null~}
      - mkdir -p /etc/apt/keyrings
      - wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg.key
      - echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null
      - apt-get update
      - DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" alloy
      - systemctl enable alloy
      - systemctl restart alloy
    %{~endif~}
  EOF
}

resource "terraform_data" "cloud_init" {
  input = md5(local.cloud_init)
}

resource "scaleway_instance_server" "server" {
  name  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image = var.image
  type  = var.type
  ip_ids = compact([
    var.enable_ipv4 ? scaleway_instance_ip.ipv4[0].id : null,
    var.enable_ipv6 ? scaleway_instance_ip.ipv6[0].id : null,
  ])
  tags                  = [for key in var.ssh_keys : "AUTHORIZED_KEY=${replace(key, " ", "_")}"]
  additional_volume_ids = var.additional_volume_ids

  user_data = {
    cloud-init = local.cloud_init
  }

  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init.output]
  }
}
