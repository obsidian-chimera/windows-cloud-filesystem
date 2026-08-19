# OneDrive → Google Drive Migration

The reference migration moved the active dataset **cloud-to-cloud** through rclone rather than downloading hundreds of GiB to the laptop and uploading it again. The safe pattern is:

**copy → verify → second pass → observe → clean up later**

Never make `move` your first migration operation.

## 1. Configure both remotes

Create private rclone remotes, for example:

```text
onedrive:
gdrive:
```

Use `rclone config` and verify each remote separately:

```powershell
rclone lsd 'onedrive:'
rclone lsd 'gdrive:'
```

Keep `rclone.conf` private. See [`SECURITY.md`](../SECURITY.md).

Official backend docs:

- <https://rclone.org/onedrive/>
- <https://rclone.org/drive/>

## 2. Establish a baseline

Before copying, record source size/listing information so you can reason about the result later:

```powershell
rclone size 'onedrive:<SOURCE_PATH>' --disable ListR
```

For very large trees, provider listings themselves can take significant time. Treat this as a baseline, not a substitute for final verification.

## 3. Perform a small test copy

Choose a small non-sensitive folder first:

```powershell
rclone copy 'onedrive:<SMALL_TEST_PATH>' 'gdrive:<TEST_DEST_PATH>' `
  --disable ListR `
  --create-empty-src-dirs `
  -P
```

Inspect the destination in Google Drive and open a representative sample of files before scaling up.

## 4. Full copy

A conservative full-pass template:

```powershell
rclone copy 'onedrive:<SOURCE_PATH>' 'gdrive:<DEST_PATH>' `
  --disable ListR `
  --create-empty-src-dirs `
  --transfers 8 `
  --checkers 16 `
  --retries 20 `
  --low-level-retries 50 `
  --stats 30s `
  -P
```

`copy` is intentional: files that already exist at the destination are updated as needed, but the source is left intact.

### Why `--disable ListR` may help OneDrive

Rclone's OneDrive backend can use recursive `ListR`/delta facilities for efficient listings. The official backend documentation also exposes `--disable ListR` for cases where you need to turn recursive listing off.

In the reference migration, direct listing of a problematic deep directory worked while recursive ListR/delta traversal produced malformed-drive-ID errors. Disabling ListR traded some efficiency for a stable recursive walk.

This is a workaround for a specific failure mode, not a universal performance recommendation.

## 5. Personal Vault API failures

OneDrive Personal Vault may behave differently from ordinary folders. In the reference migration, traversal returned an error containing:

```text
invalidResourceId: ObjectHandle is Invalid
```

Rather than treating the whole migration as failed, the Vault was explicitly excluded and handled separately:

```powershell
rclone copy 'onedrive:' 'gdrive:<DEST_PATH>' `
  --exclude '/Personal Vault/**' `
  --disable ListR `
  ...
```

Only add this exclusion if you understand what is being skipped. Do not silently omit data you actually need.

## 6. Run a second pass

After the first copy completes, run the same `rclone copy` command again. A second pass should transfer little or nothing unless files changed during the first pass.

This is especially valuable after a long migration because the source may have changed while the initial copy was running.

## 7. Verify with `rclone check`

Rclone's `check` command compares source and destination without changing either side. When both remotes expose a compatible checksum, hashes provide a stronger comparison. Across different providers, however, there may be **no common native hash** available for all files.

The reference migration therefore used:

```powershell
rclone check 'onedrive:<SOURCE_PATH>' 'gdrive:<DEST_PATH>' `
  --disable ListR `
  --size-only `
  -P
```

`--size-only` compares paths/sizes rather than hashes. It is useful for cross-provider parity but weaker than byte-for-byte verification.

For a stronger independent check on an appropriately sized sample, consider `rclone check --download`, which downloads data from both remotes and compares it on the fly. That has bandwidth/time costs.

Official command documentation: <https://rclone.org/commands/rclone_check/>

### Reference outcome

The real migration converged to:

```text
0 differences found
264,869 matching files
```

That number is a **case-study result**, not an expected count for anyone reproducing the process.

## 8. Observe before cleanup

After a clean second pass and verification:

1. browse the destination normally;
2. open files from several important folders;
3. test edits and deletes on disposable files;
4. confirm Google Drive Bin behaviour;
5. leave the source intact for an observation period.

Only then consider reducing or deleting the old OneDrive copy. The safest cleanup is intentionally decoupled from the migration itself.
