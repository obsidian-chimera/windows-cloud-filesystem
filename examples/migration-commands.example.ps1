# Safe migration pattern: test copy -> full copy -> second pass -> check -> observe -> cleanup later.
# Replace all angle-bracket placeholders before running.
#
# OneDrive Personal Vault can fail traversal through the API. If that happens when
# migrating the remote root, add: --exclude "/Personal Vault/**"
#
# Start with a small subfolder before copying the entire source tree.

$Source = 'onedrive:<SOURCE_PATH>'
$Destination = 'gdrive:<DEST_PATH>'

# First/full pass. "copy" leaves the source intact.
rclone copy $Source $Destination `
  --disable ListR `
  --create-empty-src-dirs `
  --transfers 8 `
  --checkers 16 `
  --retries 20 `
  --low-level-retries 50 `
  --stats 30s `
  -P

# Run the same copy again. A clean/near-empty second pass catches late changes
# and proves the destination can be converged without using destructive sync/move.
rclone copy $Source $Destination `
  --disable ListR `
  --create-empty-src-dirs `
  --transfers 8 `
  --checkers 16 `
  --stats 30s `
  -P

# When the two providers do not expose a compatible common native hash for every
# object, compare path/size. For stronger verification, evaluate --download on a
# suitably scoped sample or use another independent integrity method.
rclone check $Source $Destination `
  --disable ListR `
  --size-only `
  -P

# Do not delete the source immediately. Observe the destination in normal use first.
