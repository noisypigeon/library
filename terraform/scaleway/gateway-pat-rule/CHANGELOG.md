# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-28

### Add scaleway/private-network, public-gateway and gateway-pat-rule

Three new single-resource modules for the Scaleway networking that `compute-cluster` creates inline today. They back the `scaleway.privateNetwork` and `scaleway.publicGateway` workload kinds and the PAT rule a workload instance's `network.sshViaGateway` implies ([LIB-0043](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0043-workload-compute-kinds.md) §7). Each starts at v0.1.0.

- **`scaleway/private-network`** wraps one `scaleway_vpc_private_network`. It takes `name` and `project_id`, and outputs `id` and `name`.
- **`scaleway/public-gateway`** creates a gateway's public IP, the gateway, and its attachment to one Private Network. It takes `name`, `project_id`, `private_network_id` and `type` (`VPC-GW-S` by default, validated against the four offers, upgrade-only). `enable_masquerade` and `push_default_route` both default to `true`, as `compute-cluster` sets them. It outputs `id`, `ip_address` and `gateway_network_id`. The three resources sit in one module because they're always one to one and no other module wraps any of them.
- **`scaleway/gateway-pat-rule`** wraps one `scaleway_vpc_public_gateway_pat_rule`, forwarding `public_port` on a gateway's IP to `private_ip:private_port` (port 22 and `tcp` by default). It outputs `id` and, for a rule to port 22, a `connect_command`.

While a gateway pushes its default route, an attached instance's own public IP works outbound only (ADR-0146), so a PAT rule is the way in.

Verified with `tofu init` and `tofu validate` on each module, and `tofu fmt -check`. No plan was run against a live project.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#220](https://github.com/noisypigeon/library/pull/220)
