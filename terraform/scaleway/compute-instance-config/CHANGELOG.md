# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-10

### Split cloud-init into compute-instance-config; stop composing modules inside compute-instance

`compute-instance` had grown to 659 lines owning six resources and composing three other modules internally — `block-volume` (ADR-0120) and the `iam-policy`/`iam-api-key` pair (ADR-0122). Because every one of those concerns sat behind a single version, any change to any of them cut a new `compute-instance` release, which `pigeon-cluster` then had to re-pin and release, which the consuming leaf then had to re-pin again. ADR-0152 paid exactly that toll to turn one `apt-get` line into a `curl`. This splits the module so a provisioning change no longer touches the module that owns the live server.

`compute-instance` is now a thin `scaleway_instance_server` wrapper — 140 lines, three resources: the random name suffix, the cloud-init hash that drives replacement, and the server. Its inputs are flattened: `name_prefix`, `name_suffix`, `image`, `type`, `ssh_key`, `cloud_init`, `ip_ids`, `additional_volume_ids`, `enabled`. The `instance_config` and `user_config` objects are gone, along with `keyring`, `iam_config`, `self_delete_on_exit` and all four networking inputs. Outputs shrink from seven to three (`id`, `name`, `public_ips`) because the resources behind the others now belong to the caller, which can read them directly. A welcome side effect: the module is no longer `sensitive` as a whole, so values derived from `image`/`type` stop being marked sensitive by propagation in plan output.

Cloud-init rendering moves wholesale into a new `compute-instance-config` module. It creates nothing — its only output is the rendered document — which makes it the first module here that returns a string rather than infrastructure. The four locals move across verbatim; two references that could no longer resolve became inputs: `self_delete_credentials` (an object replacing the internally-composed API key, with the `self_delete_on_exit` validation ported across the boundary) and `has_attached_volume` (a plain bool replacing the volume-ID length check, deliberately caller-supplied so the rendered document never depends on an apply-time-unknown value).

Correctness was verified by rendering `local.cloud_init` from the original module and from the new one with matched inputs and diffing: byte-identical across all four combinations of `self_delete_on_exit` and `enable_transcoding`, plus a minimal no-cockpit/no-volume/empty-keyring case, with the output confirmed to parse as valid cloud-config YAML.

Two behavioural notes for callers. ADR-0126's `enabled` kill switch now destroys the server and only the server — the IPs, volume and IAM it used to tear down are the caller's resources now, so a full teardown has to gate those too; the input description says so. And rotating the self-delete API key changes the rendered document, which replaces the server; that was already true via the internal composition, but it is now an explicit property of a module boundary rather than an inherited accident.

This restores the principle ADR-0081 set and ADR-0085 reaffirmed — no module in this provider root composes another internally — and reverses the exceptions ADR-0120 and ADR-0122 carved out. ADR-0138 asked for that revisit "if a third shape of this exception shows up"; this is it. ADR-0120's own test for the carve-out was that `block-volume` had one consumer, always paired 1:1; with `pigeon-cluster` composing N jobs that each independently choose a volume, an IP, a NIC or self-deletion, that is no longer the case. ADR-0120, ADR-0121 and ADR-0122 are marked superseded, ADR-0126 superseded in part. ADR-0121's finding is restated in ADR-0153 rather than lost: a split module must be referenced by released-tag URL, never a relative path, which fails for HTTP-sourced consumers with `Local module path escapes module package`.

`pigeon-cluster` still pins `compute-instance/v6.1.0` and is unchanged by this PR; it is rewired to both new tags in a follow-up, since its new source URLs only resolve once these tags exist.


[#269](https://github.com/noisypigeon/noisypigeon/pull/269)
