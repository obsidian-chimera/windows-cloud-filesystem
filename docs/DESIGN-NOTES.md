# Design Notes

## Mount vs full local mirror

A traditional desktop sync client often maintains a local representation of cloud data and uses placeholders/on-demand hydration to reduce disk use. This project instead exposes Google Drive through an rclone **mount**.

The benefits are direct control over the filesystem layer, cache size, logging, startup and permissions. The cost is that the mounted filesystem depends on rclone/WinFsp/cloud availability rather than being a normal local NTFS tree.

## VFS cache vs `rclone bisync`

This architecture is a live cloud filesystem with a local VFS cache. It is **not `rclone bisync`**.

`bisync` is useful when you intentionally maintain two independent trees — one local and one remote — and periodically reconcile changes between them. That is not needed for folders already living directly on the mounted Google Drive because syncing `G:` back to the same Google remote would add complexity and risk without creating a meaningful second copy.

The VFS cache instead exists to make object storage behave sufficiently like a normal file for Windows applications. With `--vfs-cache-mode full`, rclone can cache reads and writes locally while the cloud remains canonical.

## Windows service vs interactive mount

An interactive user mount is simpler but may disappear across logoff/reboot and can have Windows visibility differences between elevated/non-elevated sessions.

Running the mount as SYSTEM through a Windows service gives a system-wide drive and a clean lifecycle. It also means:

- config/cache paths must be explicit;
- SYSTEM becomes the mount owner;
- the normal user needs an explicit WinFsp FileSecurity ACL;
- boot-time network ordering must be handled deliberately.

Rclone documents both scheduled-task and Windows-service approaches for Windows mounts: <https://rclone.org/install/> and <https://rclone.org/commands/rclone_mount/>.

## Why a manual service + startup task

Starting the service automatically at boot sounds simpler, but the reference system demonstrated a DNS race: Service Control Manager started rclone before `www.googleapis.com` could resolve.

The resulting design separates responsibilities:

- **service:** knows how to mount;
- **SYSTEM startup task:** runs at boot;
- **network helper:** waits for DNS + HTTPS reachability and then starts the service.

This makes the readiness condition observable and logged rather than relying on an arbitrary fixed delay.

## 10-second polling trade-off

Rclone's `--poll-interval` asks supported backends for changes and must be shorter than `--dir-cache-time`. A 10-second interval makes remote changes feel responsive compared with the default one-minute interval, at the cost of more frequent API activity.

The 10-second value is a tuning choice, not a correctness requirement and not a guarantee that a remote edit will appear exactly ten seconds later.

## 2-second write-back trade-off

With VFS caching, rclone writes a file back only after it has been closed and inactive for `--vfs-write-back`. Reducing that from the default five seconds to two makes short local edits appear remotely sooner.

The trade-off is churn: software that repeatedly opens/closes or modifies the same file can trigger more frequent uploads/revisions. Workloads with large frequently rewritten files may benefit from a longer delay.

## 50 GiB / 7-day cache

The cache is deliberately bounded rather than being a full mirror. Frequently used data can stay fast while older cached objects age out.

`--vfs-cache-max-size` is not a strict instantaneous disk quota when open/in-use files require space, so the host disk still needs headroom.

## Filtering Windows metadata

Windows shell metadata such as `desktop.ini` normally relies on NTFS Hidden/System attributes. Those attributes do not necessarily survive a cloud-object round-trip in the way Explorer expects. Filtering `desktop.ini` and `Thumbs.db` from the mounted view avoids visible shell noise without pretending Google Drive is NTFS.

## Deletion recovery

Google Drive is a useful backend for this design because rclone sends deletions to Drive Trash by default. That creates a recovery layer for ordinary accidental deletes performed through the mount.

This is not a backup by itself: users can empty trash, account compromise can delete data, and retention policies can change. Important data still needs an independent backup strategy.

Official Google Drive backend documentation: <https://rclone.org/drive/>.
