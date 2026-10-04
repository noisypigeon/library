# Changelog

All notable changes to this theme are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-10-03

### First versioned release

`templates/zola-site` is now a versioned, releasable unit
([ADR-0113](../../docs/adr/0113-version-templates-zola-site.md)). This
release has no code changes of its own — it marks the theme's existing,
already-production state (extracted from the live blog by
[ADR-0112](../../docs/adr/0112-extract-reusable-zola-site-template.md), and
running `noisypigeon.com` since before that extraction) as its formal
`1.0.0` baseline, rather than restarting at `0.1.0` the way the original
Terraform modules' own pre-automation changelog entries did.

[#146](https://github.com/noisypigeon/noisypigeon/pull/146)
