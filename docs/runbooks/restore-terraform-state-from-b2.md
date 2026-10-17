# Restore Terraform state from the B2 backup

For a spoke on `state_backend = "cloudflare"`, where Terraform state lives in R2
and, with `state_backup = true` in `spoke.hcl`, `state-backup.yml` copies it to
a versioned Backblaze B2 bucket
([LIB-0007](../adr/LIB-0007-terraform-state-on-r2-with-offsite-backup.md) §4,
[LIB-0012](../adr/LIB-0012-per-concern-secrets-files.md) §2).
This puts one leaf's state back into R2 from a version B2 kept.

## When to use it

Use it when a leaf's `terraform/<leaf>/terraform.tfstate` in R2 is gone,
corrupted, or holds a bad write you need to undo.

Check how far back you can go first. B2 holds every version the backup job
copied:
- **after a CI apply,** the state just before the next apply;
- **after a local apply,** at most a day old, from the daily run.

Anything written to R2 after the last copy isn't in B2.

## The two traps

- **Use B2's native API v4, not its S3 API.** The admin key you restore with can
  be the account's master key, and B2's S3-compatible API rejects the master key
  with `403 Forbidden`.
- **Don't use rclone's `b2` backend.** It authenticates with B2's API v1, which
  B2 refuses ("not currently supported on API version number 1"), even in
  rclone 1.72. The backup job reaches B2 through its S3 API with a separate,
  write-only key, which can't read anything back. That's why a restore needs the
  admin key.

## What you need

All of it is in the spoke's `terraform/secrets/` files, under the fixed names
LIB-0010 gives every spoke, one file per concern (LIB-0012). Load it into the
environment of one shell, and never onto disk or the screen.

| File | Key | For |
| --- | --- | --- |
| `backblaze.enc` | `BACKBLAZE_PROVIDER_ACCESS_KEY_ID`, `BACKBLAZE_PROVIDER_ACCESS_KEY` | the admin B2 key that reads the backup |
| `terraform.enc` | `TERRAFORM_STATE_BACKUP_BUCKET_NAME` | the backup bucket |
| `cloudflare.enc`, `terraform.enc` | `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, `TERRAFORM_STATE_ACCESS_KEY_ID`, `TERRAFORM_STATE_ACCESS_KEY` | writing the state back to R2 |
| `terraform.enc` | `TERRAFORM_STATE_BUCKET_NAME` | the R2 state bucket's name |

```bash
cd <spoke checkout>
for f in backblaze cloudflare terraform; do
  eval "$(sops --decrypt --input-type dotenv --output-type dotenv "terraform/secrets/$f.enc" \
    | grep -E '^(BACKBLAZE_PROVIDER_ACCESS_KEY(_ID)?|CLOUDFLARE_PROVIDER_ACCOUNT_ID|TERRAFORM_STATE_(BUCKET_NAME|ACCESS_KEY_ID|ACCESS_KEY|BACKUP_BUCKET_NAME))=' \
    | sed 's/^/export /')"
done
```

## Steps

Freeze Terraform PRs in the spoke until you've finished.

1. **List the versions and download one.** Run the script below with the
   leaf's path. It authorizes with the native API v4 and finds the backup
   bucket's ID. Then it lists that leaf's versions, newest first, and writes
   the one you pick to a scratch file outside the repo. It prints sizes,
   serials and lineages, never state content.

   ```bash
   python3 -I restore_state.py terraform/<provider>/<module>/<instance>            # list versions
   python3 -I restore_state.py terraform/<provider>/<module>/<instance> <fileId> <scratch file>
   ```

2. **Check what you got.** The script confirms the file parses as Terraform
   state and prints its `serial` and `lineage`. The lineage should match the
   leaf's: compare with `mise exec -- terragrunt state pull`, if R2 still has
   anything. A different lineage means a different state; stop.

3. **Put it back in R2.** Copy it to the same key with rclone's `s3` backend.
   `--s3-no-check-bucket` is needed because the R2 token is scoped to one
   bucket and can't create one.

   ```bash
   RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
   RCLONE_CONFIG_R2_ENDPOINT="https://$CLOUDFLARE_PROVIDER_ACCOUNT_ID.eu.r2.cloudflarestorage.com" \
   RCLONE_CONFIG_R2_ACCESS_KEY_ID="$TERRAFORM_STATE_ACCESS_KEY_ID" \
   RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$TERRAFORM_STATE_ACCESS_KEY" \
   rclone copyto --s3-no-check-bucket <scratch file> "r2:$TERRAFORM_STATE_BUCKET_NAME/terraform/<leaf>/terraform.tfstate"
   ```

4. **Plan, then clean up.** Clear the leaf's `.terragrunt-cache`, then run
   `mise exec -- terragrunt plan` in the leaf. Always run it through
   `mise exec`: a bare `terragrunt` falls back to OpenTofu, and an OpenTofu apply
   re-addresses providers in state. Read the plan. A restored older version may
   show the drift since that version, and that's real. Delete the scratch file;
   it contains secrets.

5. **Let the next backup run.** Run `gh workflow run state-backup.yml` in the
   spoke, so B2's newest version is the restored state.

## The script

`restore_state.py` uses Python's standard library only. Save it outside the
repo, next to your scratch file.

```python
# Lists or downloads one leaf's Terraform state versions from the B2 backup,
# through B2's native API v4. Reads the admin key and bucket name from the
# environment; prints sizes, serials and lineages, never state content.
import base64, datetime, json, os, sys, urllib.request

def call(url, token, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Authorization": token})
    with urllib.request.urlopen(req) as r:
        return json.load(r)

leaf = sys.argv[1].strip("/")
key = f"{leaf}/terraform.tfstate"
basic = base64.b64encode(f"{os.environ['BACKBLAZE_PROVIDER_ACCESS_KEY_ID']}:{os.environ['BACKBLAZE_PROVIDER_ACCESS_KEY']}".encode()).decode()
auth = json.load(urllib.request.urlopen(urllib.request.Request(
    "https://api.backblazeb2.com/b2api/v4/b2_authorize_account", headers={"Authorization": "Basic " + basic})))
api = auth["apiInfo"]["storageApi"]
token, base = auth["authorizationToken"], api["apiUrl"] + "/b2api/v4/"

bucket_name = os.environ["TERRAFORM_STATE_BACKUP_BUCKET_NAME"]
buckets = call(base + "b2_list_buckets", token, {"accountId": auth["accountId"], "bucketName": bucket_name})["buckets"]
if not buckets:
    sys.exit(f"no bucket named {bucket_name}")
bucket_id = buckets[0]["bucketId"]

if len(sys.argv) == 2:
    files = call(base + "b2_list_file_versions", token,
                 {"bucketId": bucket_id, "startFileName": key, "prefix": key, "maxFileCount": 1000})["files"]
    for f in sorted(files, key=lambda f: f["uploadTimestamp"], reverse=True):
        when = datetime.datetime.fromtimestamp(f["uploadTimestamp"] / 1000, datetime.timezone.utc)
        print(f"{when:%Y-%m-%d %H:%M:%S}Z  {f['contentLength']:>8} bytes  {f['action']:<6}  {f['fileId']}")
    sys.exit()

file_id, out = sys.argv[2], sys.argv[3]
req = urllib.request.Request(f"{api['downloadUrl']}/b2api/v4/b2_download_file_by_id?fileId={file_id}",
                             headers={"Authorization": token})
body = urllib.request.urlopen(req).read()
state = json.loads(body)
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "wb") as f:
    f.write(body)
print(f"wrote {out}: serial {state['serial']}, lineage {state['lineage']}, {len(state['resources'])} resources")
```

## Verified

The script's list and download steps (1 and 2) were run against
noisypigeon.com's backup on 2026-10-16. The downloaded file matched its R2 copy
by sha256. Step 3 isn't exercised by that check; it's the same `rclone copyto`
COM-0004 used to move the state onto R2.
