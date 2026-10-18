# The `DEV-` archive

These 122 records are the `DEV-` ADR domain. They were moved here verbatim from
`noisypigeon/garden`'s `adr/` by LIB-0017, which decided that spokes hold no
ADRs of their own. Each file is byte-identical to its last version in garden,
at commit `13bcee9a79c86a3a0054ebda7cd6d7fa7c238df2`, where its earlier
history also remains.

Most of this corpus is the family's history from before this hub existed. That
covers the Terraform modules and how they were versioned, the compute
instance and the `pigeon-cli` cluster, the DigitalOcean and Scaleway eras, the
Zola theme, and the workflows. It lived in garden only because garden was once
`pigeon.dev`, the repo that held all of those things.

## Rules

- **Frozen.** Nothing here is edited, renumbered or renamed. A record keeps the
  `Status` it was filed with.
- **Closed.** No new `DEV-` number will be issued. A new decision is a `LIB-`
  record, or an amendment on one, in the directory above.
- **Still binding where still in force.** Archiving is not superseding. A
  record that nothing has superseded is still the decision of record. Library
  relies on several, including:
  - DEV-0031, filing out-of-scope items as issues (filed in `noisypigeon/library`
    since LIB-0017 §6);
  - DEV-0156, why a Pages caller lives in the repo it deploys;
  - DEV-0160, the root-changelog contract `root-changelog.sh` implements;
  - DEV-0110 and DEV-0112 to DEV-0114, short URLs and the theme's versioning;
  - DEV-0139, how the theme is resolved.
- **Citations are aliases, never rewritten.** `ADR-NNNN` in older prose means
  `DEV-NNNN` (DEV-0160). Numbers `0136`, `0138` and `0156` are each used twice,
  from parallel branches, so a citation of one of those needs its slug or its
  context.
- **Folded records.** DEV-0162 to DEV-0165 were written after this hub existed
  and apply its standards to one spoke. They are also condensed as amendments on
  the `LIB-` records they apply:

  | Record | Folded into |
  |---|---|
  | DEV-0162 | LIB-0002 |
  | DEV-0163 | LIB-0003 |
  | DEV-0164 | LIB-0007 |
  | DEV-0165 | LIB-0009 |

  The `COM-` and `RUN-` records were folded the same way and exist only as
  amendments. LIB-0017 lists where each one went.
