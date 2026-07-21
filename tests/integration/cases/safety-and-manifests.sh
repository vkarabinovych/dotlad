# shellcheck shell=bash
# shellcheck disable=SC2015,SC2154  # sourced integration cases share the orchestrator fixture
# --- safety: degenerate dir DEST rejected -----------------------------------
mkdir -p "$FAKE/tools/evil/files"
printf 'x\n' >"$FAKE/tools/evil/files/f"
printf 'keep\n' >"$H/precious.txt"
# shellcheck disable=SC2016
for d in '$HOME/.' '$HOME//' '$HOME/x/..' '$HOME'; do
    cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Safety fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files"
DEST="${d}"
EOF
    rc_is "unsafe dir DEST rejected: ${d}" 1 df all
done
rm -rf "$FAKE/tools/evil"
check "\$HOME contents intact after evil manifest" test -f "$H/precious.txt"

# Source type is inferred from the filesystem; a directory is mirrored without
# any manifest type field.
mkdir -p "$FAKE/tools/evil/files"
printf 'x\n' >"$FAKE/tools/evil/files/config"
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Inferred directory fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files"
DEST="$H/.config/evil"
EOF
df evil >/dev/null 2>&1
check "directory SOURCE is inferred and mirrored" cmp -s \
    "$FAKE/tools/evil/files/config" "$H/.config/evil/config"
rm -rf "$H/.config/evil"

# Resolvers declare which source types they support.
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Unknown resolver fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
DEST="$H/.config/evil/config"
RESOLVER="missing-resolver"
EOF
rc_is "unknown resolver is rejected" 1 df evil
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Directory resolver fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files"
DEST="$H/.config/evil"
RESOLVER="json"
EOF
rc_is "resolver rejects a directory SOURCE" 1 df evil
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Valid companion fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
DEST="$H/.config/evil/config"
EOF

# A resolver that cannot render blocks the entire foreground batch before an
# earlier valid tool can mutate its destination.
mkdir -p "$FAKE/tools/invalid-resolver/files"
printf '{invalid json\n' >"$FAKE/tools/invalid-resolver/files/config.json"
cat >"$FAKE/tools/invalid-resolver/tool.conf" <<EOF
NAME="invalid-resolver"
DESC="Resolver preflight fixture"
ICON="!"
ORDER="998"
[config.main]
SOURCE="files/config.json"
DEST="$H/.config/invalid-resolver/config.json"
RESOLVER="json"
EOF
mkdir -p "$H/.config/multipkg"
printf 'preflight-keep\n' >"$H/.config/multipkg/config"
invalid_plan="$(df --config-only --json plan invalid-resolver)"
printf '%s' "$invalid_plan" | jq -e \
    ".tools[0].blockers | index(\"config.main: cannot resolve config with 'json'\")" >/dev/null &&
    pass "plan reports a resolver blocker" ||
    fail "plan missed a resolver blocker (got '$invalid_plan')"
rc_is "resolver failure blocks the full foreground batch" 1 \
    df --config-only multipkg invalid-resolver
check "resolver preflight prevents earlier config mutation" \
    grep -qxF preflight-keep "$H/.config/multipkg/config"
rm -rf "$FAKE/tools/invalid-resolver"

cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Incomplete config fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
EOF
rc_is "SOURCE without DEST is rejected" 1 df evil
rm -rf "$FAKE/tools/evil"

# A file deployment never copies into an existing directory by accident.
mkdir -p "$FAKE/tools/evil/files" "$H/.config/existing-dir"
printf 'x\n' >"$FAKE/tools/evil/files/config"
printf 'keep\n' >"$H/.config/existing-dir/keep"
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Destination type fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
DEST="$H/.config/existing-dir"
EOF
rc_is "file deployment rejects a directory destination" 1 df evil
check "directory destination remains intact" test -f "$H/.config/existing-dir/keep"
mkfifo "$H/.config/unsupported-link-destination"
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Symlink destination safety fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
DEST="$H/.config/unsupported-link-destination"
RESOLVER="symlink"
EOF
rc_is "symlink deployment rejects a special destination" 1 df --config-only evil
check "rejected special destination remains intact" test -p "$H/.config/unsupported-link-destination"
rm -f "$H/.config/unsupported-link-destination"
rm -rf "$FAKE/tools/evil"

# Tools may not own the same destination or nest under another tool.
for tool in overlap-a overlap-b; do
    mkdir -p "$FAKE/tools/$tool/files"
    printf 'x\n' >"$FAKE/tools/$tool/files/config"
done
cat >"$FAKE/tools/overlap-a/tool.conf" <<EOF
NAME="overlap-a"
DESC="Overlap fixture A"
ICON="!"
ORDER="997"
[config.main]
SOURCE="files/config"
DEST="$H/.config/shared"
EOF
cat >"$FAKE/tools/overlap-b/tool.conf" <<EOF
NAME="overlap-b"
DESC="Overlap fixture B"
ICON="!"
ORDER="998"
[config.main]
SOURCE="files/config"
DEST="$H/.config/shared/child"
EOF
rc_is "overlapping tool destinations are rejected" 1 df all
rm -rf "$FAKE/tools/overlap-a" "$FAKE/tools/overlap-b"

mkdir -p "$FAKE/tools/section-overlap/files"
printf 'a\n' >"$FAKE/tools/section-overlap/files/a"
printf 'b\n' >"$FAKE/tools/section-overlap/files/b"
cat >"$FAKE/tools/section-overlap/tool.conf" <<EOF
NAME="section-overlap"
DESC="Overlapping config sections fixture"
ICON="!"
ORDER="997"
[config.parent]
SOURCE="files/a"
DEST="$H/.config/section-overlap"
[config.child]
SOURCE="files/b"
DEST="$H/.config/section-overlap/child"
EOF
rc_is "overlapping destinations within one tool are rejected" 1 df section-overlap
rm -rf "$FAKE/tools/section-overlap"

# Mutually exclusive platform tools may own the same destination: only the
# active platform enters overlap validation or execution.
for platform_tool in platform-macos platform-linux platform-wsl; do
    mkdir -p "$FAKE/tools/$platform_tool/files"
    printf '%s\n' "$platform_tool" >"$FAKE/tools/$platform_tool/files/config"
done
cat >"$FAKE/tools/platform-macos/tool.conf" <<EOF
NAME="platform-macos"
DESC="macOS destination fixture"
ICON="!"
PLATFORMS="macos"
[config.main]
SOURCE="files/config"
DEST="$H/.config/platform-shared/config"
EOF
cat >"$FAKE/tools/platform-linux/tool.conf" <<EOF
NAME="platform-linux"
DESC="Linux destination fixture"
ICON="!"
PLATFORMS="linux"
[config.main]
SOURCE="files/config"
DEST="$H/.config/platform-shared/config"
EOF
cat >"$FAKE/tools/platform-wsl/tool.conf" <<EOF
NAME="platform-wsl"
DESC="WSL destination fixture"
ICON="!"
PLATFORMS="wsl"
[config.main]
SOURCE="files/config"
DEST="$H/.config/platform-shared/config"
EOF
check "disjoint platform tools may share a destination on macOS" \
    macos_df --config-only --json plan platform-macos
check "disjoint platform tools may share a destination on Linux" \
    linux_df --config-only --json plan platform-linux
rc_is "WSL rejects overlapping Linux and WSL destinations" 1 \
    wsl_df --config-only --json plan platform-wsl
rm -rf "$FAKE/tools/platform-macos" "$FAKE/tools/platform-linux" \
    "$FAKE/tools/platform-wsl"

mkdir -p "$FAKE/tools/inject-collision/files/a" "$FAKE/tools/inject-collision/files/b"
printf 'a\n' >"$FAKE/tools/inject-collision/files/a/shared.conf"
printf 'b\n' >"$FAKE/tools/inject-collision/files/b/shared.conf"
cat >"$FAKE/tools/inject-collision/tool.conf" <<EOF
NAME="inject-collision"
DESC="Inject metadata collision fixture"
ICON="!"
ORDER="997"
[config.first]
SOURCE="files/a/shared.conf"
DEST="$H/.config/inject-collision.rc"
RESOLVER="inject"
[config.second]
SOURCE="files/b/shared.conf"
DEST="$H/.config/inject-collision.rc"
RESOLVER="inject"
EOF
rc_is "inject sections in one tool require unique source identities" 1 df inject-collision
rm -rf "$FAKE/tools/inject-collision"

for inject_owner in inject-owner-a inject-owner-b; do
    mkdir -p "$FAKE/tools/$inject_owner/files"
    printf '%s\n' "$inject_owner" >"$FAKE/tools/$inject_owner/files/shared.conf"
    cat >"$FAKE/tools/$inject_owner/tool.conf" <<EOF
NAME="$inject_owner"
DESC="Inject owner identity fixture"
ICON="i"
ORDER="997"
[config.main]
SOURCE="files/shared.conf"
DEST="$H/.config/inject-owner.rc"
RESOLVER="inject"
EOF
done
check "inject tool identity permits shared source filenames" \
    df --config-only --json plan inject-owner-a inject-owner-b
rm -rf "$FAKE/tools/inject-owner-a" "$FAKE/tools/inject-owner-b"

# Existing parent symlinks must not redirect a deployment outside HOME.
mkdir -p "$SB/outside" "$FAKE/tools/evil/files"
ln -s "$SB/outside" "$H/.unsafe"
printf 'escape\n' >"$FAKE/tools/evil/files/config"
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Safety fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
DEST="$H/.unsafe/config"
EOF
rc_is "symlink parent destination rejected" 1 df evil
checknot "symlink escape wrote nothing outside HOME" test -e "$SB/outside/config"
rm -rf "$FAKE/tools/evil"

# SOURCE may not escape its tool through an intermediate symlink.
mkdir -p "$FAKE/tools/evil" "$SB/source-outside"
printf 'outside\n' >"$SB/source-outside/config"
ln -s "$SB/source-outside" "$FAKE/tools/evil/files"
cat >"$FAKE/tools/evil/tool.conf" <<EOF
NAME="evil"
DESC="Source symlink fixture"
ICON="!"
ORDER="999"
[config.main]
SOURCE="files/config"
DEST="$H/.config/source-escape"
EOF
rc_is "symlink parent SOURCE is rejected" 1 df evil
checknot "source symlink copied nothing" test -e "$H/.config/source-escape"
rm -rf "$FAKE/tools/evil"

# Manifests and profiles must be real project files, not links to external
# data that happen to parse as valid declarations.
mkdir -p "$SB/external-tool"
cat >"$SB/external-tool/tool.conf" <<'EOF'
NAME="linked-tool"
DESC="External tool fixture"
ICON="!"
BREW="linked-tool"
EOF
ln -s "$SB/external-tool" "$FAKE/tools/linked-tool"
rc_is "symlinked tool directory is rejected" 1 df all
rm -f "$FAKE/tools/linked-tool"
mkdir -p "$FAKE/tools/linked-manifest"
cat >"$SB/external-manifest.conf" <<'EOF'
NAME="linked-manifest"
DESC="External manifest fixture"
ICON="!"
BREW="linked-manifest"
EOF
ln -s "$SB/external-manifest.conf" "$FAKE/tools/linked-manifest/tool.conf"
rc_is "symlinked tool manifest is rejected" 1 df all
rm -rf "$FAKE/tools/linked-manifest"
printf 'extends=""\ntools="multipkg"\n' >"$SB/external-profile.conf"
ln -s "$SB/external-profile.conf" "$FAKE/profiles/linked-profile.conf"
rc_is "symlinked profile is rejected" 1 df profile linked-profile
rm -f "$FAKE/profiles/linked-profile.conf"

# Required presentation metadata fails fast instead of producing broken rows.
mkdir -p "$FAKE/tools/evil"
cat >"$FAKE/tools/evil/tool.conf" <<'EOF'
NAME="evil"
DESC="Missing icon fixture"
ORDER="999"
EOF
rc_is "tool without an icon is rejected" 1 df all
rm -rf "$FAKE/tools/evil"

# Every accepted tool must own an installation or config action.
mkdir -p "$FAKE/tools/empty-tool"
cat >"$FAKE/tools/empty-tool/tool.conf" <<'EOF'
NAME="empty-tool"
DESC="No-op fixture"
ICON="!"
ORDER="999"
EOF
rc_is "tool without package or config is rejected" 1 df all
rm -rf "$FAKE/tools/empty-tool"

# tool.conf is parsed as data: unknown/duplicate fields and shell
# substitutions are rejected without executing project code.
mkdir -p "$FAKE/tools/strict-manifest/files"
printf 'strict\n' >"$FAKE/tools/strict-manifest/files/config"
cat >"$FAKE/tools/strict-manifest/tool.conf" <<'EOF'
NAME="strict-manifest"
DESC="Invalid platform fixture"
ICON="!"
PLATFORMS="macos windows"
BREW="strict-manifest"
EOF
rc_is "manifest rejects an unknown platform" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<'EOF'
NAME="strict-manifest"
DESC="Duplicate platform fixture"
ICON="!"
PLATFORMS="linux linux"
BREW="strict-manifest"
EOF
rc_is "manifest rejects duplicate platforms" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<'EOF'
NAME="strict-manifest"
DESC="Linux cask fixture"
ICON="!"
PLATFORMS="macos linux"
BREW="strict-manifest"
CASK="1"
EOF
rc_is "manifest rejects a cask enabled on Linux" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<'EOF'
NAME="strict-manifest"
DESC="WSL cask fixture"
ICON="!"
PLATFORMS="macos wsl"
BREW="strict-manifest"
CASK="1"
EOF
rc_is "manifest rejects a cask enabled on WSL" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<EOF
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
UNKNOWN="nope"
EOF
rc_is "strict manifest rejects unknown fields" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<EOF
NAME="strict-manifest"
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
EOF
rc_is "strict manifest rejects duplicate fields" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<EOF
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
RESOLVER="copy"

[config.main.options]
COMMENT_PREFIX="#"
EOF
rc_is "resolver options are validated by their resolver" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<EOF
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
RESOLVER="inject"

[config.main.options]
COMMENT_SUFFIX="-->"
EOF
rc_is "custom comment suffix requires a prefix" 1 df all
cat >"$FAKE/tools/strict-manifest/tool.conf" <<EOF
NAME="strict-manifest"
DESC="broken"quote"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
EOF
rc_is "strict manifest rejects unescaped inner quotes" 1 df all
marker="$SB/manifest-executed"
cat >"$FAKE/tools/strict-manifest/tool.conf" <<EOF
NAME="strict-manifest"
DESC="\$(touch $marker)"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
EOF
rc_is "strict manifest rejects command substitution" 1 df all
checknot "strict manifest executes no project code" test -e "$marker"
cat >"$FAKE/tools/strict-manifest/tool.conf" <<'EOF'
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
[config.main]
SOURCE="files/config"
DEST="$HOME/.config/strict-manifest"
EOF
df --config-only strict-manifest >/dev/null 2>&1
check "strict manifest expands HOME without eval" grep -qxF strict "$H/.config/strict-manifest"
rm -rf "$FAKE/tools/strict-manifest"

# Remote installers may pin their downloaded script. A mismatch must prevent
# execution, and malformed checksum declarations fail during manifest loading.
mkdir -p "$FAKE/tools/remote-installer"
remote_payload="$SB/remote-installer.sh"
remote_marker="$H/.local/bin/remote-installer"
remote_tmp="$SB/remote-installer-tmp"
mkdir -p "$remote_tmp"
# shellcheck disable=SC2016  # variables belong to the generated installer
printf '#!/bin/sh\nmkdir -p "$(dirname "$REMOTE_INSTALLER_MARKER")"\nprintf "installed\\n" > "$REMOTE_INSTALLER_MARKER"\n' \
    >"$remote_payload"
cat >"$SB/bin/curl" <<'EOF'
#!/bin/sh
cat "$REMOTE_INSTALLER_SOURCE"
EOF
chmod +x "$SB/bin/curl"
export REMOTE_INSTALLER_SOURCE="$remote_payload" REMOTE_INSTALLER_MARKER="$remote_marker"
remote_sha256="$(test_sha256 "$remote_payload")"
cat >"$FAKE/tools/remote-installer/tool.conf" <<EOF
NAME="remote-installer"
DESC="Pinned remote installer fixture"
ICON="!"
ORDER="999"
CHECK="$remote_marker"
INSTALL_URL="https://example.invalid/install.sh"
INSTALL_SHA256="$remote_sha256"
EOF
TMPDIR="$remote_tmp" df remote-installer >/dev/null 2>&1
check "matching remote installer checksum permits execution" test -f "$remote_marker"
checknot "successful remote installer leaves no temporary script" \
    test -n "$(find "$remote_tmp" -type f -print -quit)"
rm -f "$remote_marker"
sed 's/INSTALL_SHA256="[^"]*"/INSTALL_SHA256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"/' \
    "$FAKE/tools/remote-installer/tool.conf" >"$SB/remote-mismatch.conf"
cp "$SB/remote-mismatch.conf" "$FAKE/tools/remote-installer/tool.conf"
TMPDIR="$remote_tmp" rc_is "remote installer checksum mismatch exits non-zero" 1 df remote-installer
checknot "checksum mismatch prevents remote installer execution" test -e "$remote_marker"
checknot "rejected remote installer leaves no temporary script" \
    test -n "$(find "$remote_tmp" -type f -print -quit)"
sed 's/INSTALL_SHA256="[^"]*"/INSTALL_SHA256="not-a-digest"/' \
    "$FAKE/tools/remote-installer/tool.conf" >"$SB/remote-invalid.conf"
cp "$SB/remote-invalid.conf" "$FAKE/tools/remote-installer/tool.conf"
rc_is "manifest rejects malformed installer checksum" 1 df all
cat >"$FAKE/tools/remote-installer/tool.conf" <<'EOF'
NAME="remote-installer"
DESC="Checksum without URL fixture"
ICON="!"
BREW="remote-installer"
INSTALL_SHA256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EOF
rc_is "manifest rejects installer checksum without URL" 1 df all
rm -rf "$FAKE/tools/remote-installer"
rm -f "$SB/bin/curl"
unset REMOTE_INSTALLER_SOURCE REMOTE_INSTALLER_MARKER

# A runtime install failure must reach automation as a non-zero command status.
mkdir -p "$FAKE/tools/broken"
cat >"$FAKE/tools/broken/tool.conf" <<'EOF'
NAME="broken"
DESC="Failure propagation fixture"
ICON="!"
ORDER="999"
BREW="broken"
EOF
printf 'broken\n' >"$BREW_FAIL_FILE"
rc_is "foreground install failure exits non-zero" 1 df broken
cat >"$FAKE/profiles/broken.conf" <<'EOF'
extends=""
tools="broken"
EOF
rc_is "profile propagates a tool failure" 1 df profile broken
rc_is "all propagates a tool failure" 1 df all
rm -f "$BREW_FAIL_FILE" "$FAKE/profiles/broken.conf"
rm -rf "$FAKE/tools/broken"

# Package-manager success is not enough when CHECK still says the tool is
# absent; automation must receive a failure instead of a false installed state.
mkdir -p "$FAKE/tools/unverified"
cat >"$FAKE/tools/unverified/tool.conf" <<'EOF'
NAME="unverified"
DESC="Post-install verification fixture"
ICON="!"
ORDER="999"
BREW="unverified"
CHECK="definitely-not-created-by-the-fixture"
EOF
rc_is "post-install state is verified" 1 df unverified
rm -rf "$FAKE/tools/unverified" "$BREW_PREFIX/opt/unverified" "$BREW_PREFIX/bin/unverified"

# Re-loading in the same process replaces, rather than duplicates, the model.
reload_counts="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/console.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/resolvers.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
    manifest_load; first="$T_COUNT"; manifest_load
    printf "%s %s" "$first" "$T_COUNT"')"
tool_count="$(find "$FAKE/tools" -mindepth 2 -maxdepth 2 -name tool.conf | wc -l | tr -d ' ')"
[[ "$reload_counts" == "$tool_count $tool_count" ]] &&
    pass "manifest reload is idempotent" || fail "manifest reload duplicated entries: $reload_counts"

# Profiles resolve inheritance without duplicates and only contain tools.
profile_out="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/console.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/resolvers.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"; manifest_load; profile_tools complete')"
[[ "$(printf '%s\n' "$profile_out" | sort -u | wc -l | tr -d ' ')" == "$tool_count" ]] &&
    pass "complete profile resolves every tool once" ||
    fail "complete profile resolution"
profile_marker="$SB/profile-executed"
cat >"$FAKE/profiles/strict-profile.conf" <<EOF
extends=""
tools="\$(touch $profile_marker)"
EOF
rc_is "strict profile rejects command substitution" 1 df profile strict-profile
checknot "strict profile executes no project code" test -e "$profile_marker"
rm -f "$FAKE/profiles/strict-profile.conf"
printf 'extends="cycle-b"\ntools=""\n' >"$FAKE/profiles/cycle-a.conf"
printf 'extends="cycle-a"\ntools=""\n' >"$FAKE/profiles/cycle-b.conf"
rc_is "profile inheritance cycle is rejected" 1 df profile cycle-a
rm -f "$FAKE/profiles/cycle-a.conf" "$FAKE/profiles/cycle-b.conf"
