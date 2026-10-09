#!/usr/bin/env bash
# Synchronize committed EDK2 development to the payload consumed by this tree.
set -euo pipefail

project_root=$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)
cd "$project_root"
source_repo=${1:-/home/uefi/workspace/uefi_edk2}
source_branch=${2:-feature/vga}
payload_path=payloads/external/edk2/workspace/mahdi-sahebi

if [[ -n $(git -C "$source_repo" status --porcelain) ]]; then
  echo 'Commit the EDK2 development changes before synchronizing.' >&2
  exit 1
fi
if [[ -n $(git -C "$payload_path" status --porcelain) ]]; then
  echo 'The payload checkout has local changes; preserve them before synchronizing.' >&2
  exit 1
fi
if [[ $(grep -c '^CONFIG_EDK2_TAG_OR_REV=' .config) != 1 ]]; then
  echo 'Expected exactly one EDK2 revision setting in .config.' >&2
  exit 1
fi

revision=$(git -C "$source_repo" rev-parse --verify "$source_branch^{commit}")
git -C "$payload_path" fetch "$source_repo" "$source_branch"
git -C "$payload_path" checkout --detach "$revision"
# Initialize EDK2's declared dependencies, not OpenSSL's optional upstream
# test corpora, which are not part of this firmware build.
git -C "$payload_path" submodule update --init --checkout
test "$(git -C "$payload_path" rev-parse HEAD)" = "$revision"
sed -i "s/^CONFIG_EDK2_TAG_OR_REV=.*/CONFIG_EDK2_TAG_OR_REV=\"$revision\"/" .config

update_time=$(TZ=Europe/Amsterdam date '+%Y-%m-%d %H:%M %Z')
printf '\n## Plan update — %s (Europe/Amsterdam)\n\n' "$update_time" >> doc/plan.md
printf 'Synchronized EDK2 branch `%s` from `%s`.\n' "$source_branch" "$source_repo" >> doc/plan.md
printf 'Result: payload HEAD and `.config` select `%s`.\n' "$revision" >> doc/plan.md
printf 'Build, hardware validation, and the matching coreboot commit are pending.\n' >> doc/plan.md
printf 'Payload synchronized to %s. Commit the coreboot pin/config/plan with the same message as EDK2:\n' "$revision"
git -C "$source_repo" log -1 --format=%B "$revision"
