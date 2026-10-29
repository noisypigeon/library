# LIB-0043: Compute, network and IAM policy kinds for workloads

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed. Amends:
  - LIB-0023 §2, whose kind table gains nine kinds and whose
    `scaleway.iam.apiKey` becomes a map;
  - LIB-0025 §3, whose `secretRef` reaches a keyring entry's fields;
  - LIB-0024 §1 and LIB-0028 §5, whose deployer policy grows with the kinds
    a workload declares;
  - LIB-0038's Out of scope, whose `scaleway.iam.policy` kind
    ([#191](https://github.com/noisypigeon/library/issues/191)) this
    decides.

## Context

`scaleway/compute-cluster`, `pigeon-cluster` until LIB-0020, is pigeon-cli's
job fleet in one module. Each job gets:

- an IAM application;
- a work policy and key, and a self-delete policy and key;
- a block volume;
- cloud-init, from `compute-instance-config`;
- a routed IPv4, the server and a private NIC.

The cluster as a whole gets a Private Network, a Public Gateway with its IP
and its attachment, and an optional bastion behind a PAT rule.

runway's one caller, `terraform/scaleway/compute-cluster/pigeon-cli/`, has
its module block commented out. Every job it describes is commented out too.

LIB-0038 retired the hub's two bundle modules, because the kind table can
compose single-resource modules as well as a module can. `compute-cluster` is
the biggest bundle left. Nothing lets a workload declare an instance, a
volume, a network or a policy. So a pigeon-cli fleet can't be declared in a
`workload.yaml` today.

Reading the bundle against Scaleway's IAM and the kind table turned up five
things:

1. **An application's keys share its policies.** A policy attaches to an
   application, never to one key. ADR-0144 and DEV's ADR-0153 kept the
   self-delete key apart from the job's keyring key, so that the keyring
   credential wouldn't carry `InstancesFullAccess`. Both keys sat on one
   application, though, so both carried it.
2. **A NIC can't land a stage after its server.** A job with no public IP
   reaches the internet only through the gateway's route on the Private
   Network. Its cloud-init runs at first boot. A NIC in a leaf of its own
   would apply a stage later (LIB-0024 §3), after cloud-init had already
   failed.
3. **`compute-instance` has no `project_id`.** root.hcl's provider block sets
   no project either, so a workload's instance would land in the provider's
   default project, not the workload's.
4. **A secret is one scalar per input** (LIB-0025). A keyring email's
   `secret` sits inside `compute-instance-config`'s `keyring` list.
5. **`scaleway.iam.apiKey` is a singleton that nothing uses.** The LIB-0023
   proof of concept, its only user, is gone.

## Decision

### 1. The kinds

The kind table (LIB-0023 §2) gains these rows. Every one is a `workload`
unit's alone. In the instance column, `<k>` is the entry's key.

| YAML key | Module | Shape | Instance | Credentials | State |
| --- | --- | --- | --- | --- | --- |
| `scaleway.iam.policy.<k>` | `scaleway/iam-policy` | map | `<k>` | spoke | workload |
| `scaleway.iam.apiKey.<k>` | `scaleway/iam-api-key` | map (was singleton) | `<k>` | spoke | workload |
| `scaleway.blockVolume.<k>` | `scaleway/block-volume` | map | `<k>` | workload | workload |
| `scaleway.cockpit` | `scaleway/cockpit-observability` | singleton | `main` | workload | workload |
| `scaleway.privateNetwork` | `scaleway/private-network` (new) | singleton | `main` | workload | workload |
| `scaleway.publicGateway` | `scaleway/public-gateway` (new) | singleton | `main` | workload | workload |
| `scaleway.instance.<k>` | `scaleway/compute-instance` | map | `<k>` | workload | workload |
| implied by `scaleway.instance.<k>` | `scaleway/compute-instance-config` | implied | `<k>` | workload | workload |
| implied by `…network.sshViaGateway` | `scaleway/gateway-pat-rule` (new) | implied | `<k>` | workload | workload |

- **The IAM kinds sign in with the spoke's key.** That's why the existing
  `iam.application` and `iam.apiKey` do too: a deployer whose grants could
  mint IAM could grant itself anything.
- **`scaleway.iam.application` stays a singleton.** A workload declares
  exactly one application, and every declared policy and key hangs off it.
  The table doesn't pretend that keys are scoped (Context, item 1). Two keys
  differ only in their lifetime and their rotation, and in where they're
  handed out.
- **Names default** from the workload, as LIB-0023 §4's do:
  - a policy is `<prefix>-<suffix><tag>-<k>`, which the module suffixes with
    `-policy`;
  - a volume is `<prefix><tag>-<k>` with suffix `<suffix>`;
  - a private network and a gateway are `<prefix>-<suffix><tag>`;
  - cockpit is `<prefix>-<suffix><tag>`;
  - an instance is `<prefix><tag>`, with suffix `<k>`, and the module's
    random segment sits between them.

  `<tag>` is LIB-0040's amended name tag.
- **Wiring, within one workload:**
  - `project_id` comes from the project for a volume, cockpit, the private
    network, the gateway and an instance. A policy takes `project_ids =
    [project.id]`.
  - A policy and a key take `application_id` from `iam.application`. A key
    takes `default_project_id` from the project.
  - The gateway takes `private_network_id` from `privateNetwork`.
  - An instance takes `cloud_init` from its config leaf,
    `additional_volume_ids` from its volumes, and `private_network_id` from
    `privateNetwork` when it attaches.
  - A PAT rule takes `gateway_id` from the gateway and `private_ip` from its
    instance.
  - A config leaf takes its keyring's wiring (§4), `cockpit` from the cockpit
    leaf, and its self-delete credential (§3).
- **An instance with no public IPv4 waits for the gateway.** Its stub
  declares `dependencies { paths = [<gateway>] }`. That fills no input, but it
  makes the gateway apply first.
- **An entry can't set a wired input.** That covers `application_id`,
  `project_id`, `project_ids`, `default_project_id`, `private_network_id`,
  `gateway_id`, `private_ip`, `cloud_init` and `additional_volume_ids`, each
  on the kinds that wire it.
- **Reserved keys:** `deployer`, for a policy or a key (LIB-0038 §1); `main`
  and `deployer`, for an instance; and any policy, key or application name
  starting `self-delete-` (§3).

### 2. An instance entry

Below `scaleway.instance.<k>`, `compute-instance`'s own inputs (`type`,
`image`, `enabled`, `ssh_key`) pass through by their own names, as LIB-0023
§2 has it. Six camelCase keys are this interface's, and expand into the
instance's and its config leaf's inputs:

| Key | Type, default | Becomes |
| --- | --- | --- |
| `network.privateNetwork` | bool, default whether `scaleway.privateNetwork` is enabled | instance `private_network_id`, wired |
| `network.publicIpv4` | bool, default `false` | instance `public_ipv4` |
| `network.sshViaGateway` | port number, optional | a `gateway-pat-rule/<k>` leaf, gateway `<port>` to the instance's port 22 |
| `volumes` | list of `blockVolume` keys, default `[]` | instance `additional_volume_ids`; config `has_attached_volume` |
| `cockpit` | bool, default whether `scaleway.cockpit` is declared | config `cockpit`, wired |
| `transcoding` | bool, default `false` | config `enable_transcoding` |
| `selfDelete` | bool, default `false` | config `self_delete_on_exit`, and §3 |
| `commands` | list of strings, default `[]` | config `post_provision_commands`, templated with `keyring` as ADR-0144's are |
| `keyring` | map of alias to entry | config `keyring`, `keyring_wiring` and `keyring_secrets` (§4) |

`scaleway.sharedKeyring` holds entries of the same shape. It merges under
every instance's `keyring`, and the instance's entry wins on a shared alias,
as `cluster_config.shared_keyring` did.

### 3. A self-deleting instance has an application of its own

`selfDelete: true` implies three more leaves for that instance:

```
scaleway/iam-application/self-delete-<k>
scaleway/iam-policy/self-delete-<k>     # InstancesFullAccess on the workload's project
scaleway/iam-api-key/self-delete-<k>
```

The key's `access_key` and `secret_key` go into the config leaf's
`self_delete_credentials`, with the project's ID.

- **Its grant never reaches the workload's keys,** because it sits on a
  different application. This is what ADR-0144 meant to do, and what one
  application per job didn't achieve (Context, item 1).
- **"Exactly one application" means one declared application.** The
  self-delete applications are implied, one per self-deleting instance. They
  go when the instance's entry goes.
- **A declared policy that grants `InstancesFullAccess` is a warning,** not
  an error, in `resolve-workloads.sh --check`. It reaches every key the
  workload hands out, and `selfDelete` is the narrow way to get it.

### 4. A keyring entry

An entry has `compute-instance-config`'s `kind` and its fields, plus `apiKey`.
Any field may be `{ secretRef: NAME }`, resolved from `secrets.workload.yaml`'s
`env`.

- **`bucket` names a `scaleway.bucket` key, or a bucket outside the
  workload.**
  - A key wires the bucket's name from its leaf, and an `endpoint` of
    `https://s3.<region>.scw.cloud`, unless the entry sets one.
  - Anything else is the bucket's literal name, or a `secretRef`, and needs
    `endpoint`.
- **`apiKey` names an `iam.apiKey` key,** whose `access_key` and `secret_key`
  become the entry's credentials. A bucket entry takes `apiKey` or both of
  `access_key_id` and `secret_key`, never both.
- **What a dependency fills** reaches the config leaf as `keyring_wiring`, a
  map from alias to `{ bucket, access_key_id, secret_key }`. The stub
  assembles it from its dependencies, as it assembles `bucket_ids`
  (LIB-0029 §3).
- **What a `secretRef` fills** reaches the config leaf as `keyring_secrets`,
  a sensitive map from alias to a partial entry. root.hcl writes it as one
  variable, never a literal. This amends LIB-0025 §3, which resolved a
  `secretRef` only for a module input of its own.
- **Everything else is a literal** in `keyring`. `compute-instance-config`
  merges all three by alias, and only then runs its own required-field
  validations.

### 5. The gateway turns on and off on its own

`scaleway.privateNetwork` and `scaleway.publicGateway` each take `enabled`,
which is `true` when the key is present. `enabled: false` keeps the entry in
the file and drops its stub, so its leaf plans a destroy (LIB-0023's second
amendment). The gateway's `type` is `VPC-GW-S`, `-M`, `-L` or `-XL`, by
default `VPC-GW-S`. An upgrade happens in place, and there's no downgrade.

Every instance needs a way out, and the file has to say which:

- **E1:** every instance has `network.publicIpv4: true`, or
  `network.privateNetwork: true` with the gateway on.
- **E2:** while the gateway is absent or `enabled: false`, every instance
  writes `network.publicIpv4: true` itself. A default doesn't count, so
  turning the gateway off fails until each instance has been edited on
  purpose.
- **E3:** the gateway on needs the private network on, since it reaches
  instances only through it.
- **E4:** an instance on the private network may also take a public IPv4
  while the gateway is on. While the gateway pushes its default route, that
  IP works outbound only (ADR-0146). The schema's description says so, and
  nothing refuses it.
- **E5:** `sshViaGateway` needs the gateway on and
  `network.privateNetwork: true`. No two instances may share a port.
- **E6:** `network.privateNetwork: true` needs `scaleway.privateNetwork` on.

The bastion and its flag don't come across. An instance with
`sshViaGateway` and no `commands` is a bastion.

### 6. The other rules

- **I1:** a workload that declares a policy or a key declares
  `iam.application`.
- **I2:** every `apiKey` names an `iam.apiKey` key.
- **S1:** `volumes` names `blockVolume` keys. An instance takes at most one
  volume, since its cloud-init mounts only `/dev/sdb`. A volume attaches to at
  most one instance.
- **S2:** an email entry has `email`, `provider`, `host`, `port` and `secret`.
  A bucket entry has a bucket and its credentials (§4).
- **M1:** `transcoding` is refused on a `COPARM*` type, since the pinned
  ffmpeg is x86_64 (ADR-0152).
- **M2:** `cockpit: true` needs `scaleway.cockpit`.
- **M3:** an instance key is kebab-case and at most 40 characters.

Each rule is checked in all three places that check a unit file:

- the workload schema, as far as JSON Schema can say it, E2 included;
- `resolve-workloads.sh --check`;
- a root.hcl guard, before planning.

Each message names this record.

### 7. Modules

- **`scaleway/private-network`, new:** one `scaleway_vpc_private_network`. It
  takes `name` and `project_id`.
- **`scaleway/public-gateway`, new:** the gateway's IP, the gateway, and its
  attachment to the private network. It takes `name`, `type`, `project_id`,
  `private_network_id`, `enable_masquerade` and `push_default_route`. The
  three parts are always one to one, and no other module wraps any of them,
  so LIB-0038's concern doesn't arise.
- **`scaleway/gateway-pat-rule`, new:** one
  `scaleway_vpc_public_gateway_pat_rule`.
- **`scaleway/compute-instance` v8.0.0:**
  - It takes `project_id`.
  - It takes `private_network_id`, and attaches the NIC itself, as a
    standalone `scaleway_instance_private_nic`, so attaching or detaching
    never replaces the server (ADR-0145).
  - It takes `public_ipv4`, and creates the routed IP itself. This reverses
    DEV's ADR-0153 for the IP. Nothing stops one module from creating an IP
    and the server that references it, and the IP goes with the server, as
    self-delete already has it.
  - It keeps `ip_ids`, for a caller that brings its own IP.
  - It outputs `private_ipv4`.
  - It's a major because a new required `project_id` breaks every caller.
- **`scaleway/compute-instance-config` v1.1.0:** it takes `keyring_wiring`
  and `keyring_secrets` (§4). Without them it renders exactly what v1.0.0
  renders.

### 8. The deployer's grants

The deployer policy's default `project_permission_sets` keeps
`ObjectStorageFullAccess` (LIB-0028 §5), and gains a grant for each kind the
workload declares:

| Kind | Permission set |
| --- | --- |
| `blockVolume` | `BlockStorageFullAccess` |
| `instance` | `InstancesFullAccess` |
| `privateNetwork` | `PrivateNetworksFullAccess` |
| `publicGateway` | `VPCGatewayFullAccess` |
| `cockpit` | `ObservabilityFullAccess` |

An explicit `scaleway.deployer.policy.project_permission_sets` still wins,
and still has to keep `ObjectStorageFullAccess`.

### 9. Release impact

Each is its own labelled PR, in this order:

1. `scaleway/private-network`, `scaleway/public-gateway` and
   `scaleway/gateway-pat-rule`, v0.1.0 each.
2. `scaleway/compute-instance` v8.0.0 and `scaleway/compute-instance-config`
   v1.1.0.
3. `workflows/v9.0.0`: `resolve-workloads.sh`'s kinds, stubs and checks, and
   `generate-module-redirects.sh`'s schema list and
   `schemas/workload/v5.json`. `v4.json` stays published, unchanged.
4. `terragrunt/root-hcl` v9.0.0: the kinds, the expansions, the guards and
   the deployer's grants.

The last two are majors, because `scaleway.iam.apiKey` changes shape and an
instance's leaves need v8's `project_id`. A spoke takes the workflows alone
first (LIB-0024 §5), then dispatches `garden-generate.yml`, so that the new
modules' `inputs.schema.json` exist before a `--check` fetches them. Only
then does it bump `root_hcl_version`.

`scaleway/compute-cluster` is unchanged and keeps its releases.

## Consequences

- **A fleet is one `workload.yaml`.** A job is one `instance` entry, and the
  gateway is one `enabled` flag.
- **Turning the gateway off is a deliberate edit to every instance.** E2
  refuses the plan until each instance says how it reaches the internet.
- **A self-delete grant reaches only its own instance's key.** The workload's
  keys stay narrow, which `compute-cluster` meant to do and didn't.
- **An instance has two leaves,** its config and its server, plus three for
  `selfDelete` and one for `sshViaGateway`. A new fleet takes more stages
  than a bucket-only workload: the gateway, then the configs, then the
  instances, then the PAT rules.
- **A self-deleted instance leaves its leaves behind.** Its entry is removed
  once it's gone, and that destroy plans nothing that still exists, as with
  `compute-cluster`.
- **Every `compute-instance` caller moves to v8** when it next bumps, with a
  `project_id`. `compute-cluster` pins v7 and doesn't move.

## Out of scope

- **Migrating runway's hand-written pigeon-cli leaves,** its cluster, IAM,
  Cockpit and buckets. This record only makes the workload possible. Their
  resources live in the `runway` project, and a private workload's are in a
  project of its own. Deferred
  ([#98](https://github.com/noisypigeon/library/issues/98)).
- **More than one volume per instance.** `compute-instance-config` mounts
  `/dev/sdb` alone. Deferred
  ([#217](https://github.com/noisypigeon/library/issues/217)).
- **Deprecating `scaleway/compute-cluster`.** That waits until no spoke calls
  it. Deferred
  ([#218](https://github.com/noisypigeon/library/issues/218)).
- **A shared `scaleway.bastion`.** `sshViaGateway` covers it, and a bastion
  is just an instance. This is a design boundary.
- **Keys scoped narrower than their application.** Scaleway has no such
  thing. This is a design boundary.

## Verification

1. **Each module validates and plans** in a scratch root against a sandbox
   project. A v8 instance with `public_ipv4` and `private_network_id` gets
   one IP and one NIC. A v1.1.0 config with neither new input renders the
   same document as v1.0.0.
2. **Each rule is refused by name, before planning,** by both
   `resolve-workloads.sh --check` and root.hcl, on a fixture spoke: E1–E3,
   E5, E6, I1, I2, S1, S2 and M1–M3, plus each reserved key and each wired
   input set by hand. E2 also fails against `schemas/workload/v5.json` in an
   editor.
3. **Stubs carry the wiring the table gives.** An instance's config stub has
   a dependency for each keyring `apiKey` and `bucket` it names, and its
   `keyring_wiring` names them. An instance with no public IPv4 depends on the
   gateway. Turning the gateway off removes exactly its stub and the PAT
   stubs.
4. **It converges.** On a scratch spoke, never runway, an example workload
   applies in stages until every leaf re-plans `No changes.` Then the gateway
   is turned off, with every instance on `publicIpv4: true`, and only the
   gateway's and the PAT rules' leaves are destroyed.
