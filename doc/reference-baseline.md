# Reference baseline — 2026-10-09

The first paired commits use the exact message:
`baseline: reproduce reference VGA output and DXE handoff`.

## Source identity

- Reference coreboot: `0175444e946cc7f595d7f8bba770b038a118954d` in
  `/home/uefi/workspace/coreboot`.
- Reference EDK2: `ec1955278bd437aaea828f1217bfcab9b396a6e8` in its configured
  `payloads/external/edk2/workspace/mahdi-sahebi` checkout.
- New EDK2 baseline: `2c42a878f26d7078b54fe83ece24bb57f87d3020`.
  Both EDK2 commits have Git tree `26cd7211de7f926b1ee468109a5be38fc180f6c4`:
  tracked content and submodule pointers match exactly.
- EDK2 platforms: `9ef9bcef5090effeb569f61c8585795fdb41d41d`.
- Coreboot source and dependency gitlinks are restored from the reference.
  The obsolete reference EDK2 gitlink named `dasharo` is replaced with the
  actually configured `mahdi-sahebi` checkout, pinned to the paired commit.
- The development repositories retain their histories and the backup branch
  `backup/pre-reference-baseline-20261009`.

## Deliberate nonfunctional differences

The current `.gitignore` and project documentation are preserved. Reference
text/log/image documentation is imported into `doc/`; movies, archives, and
firmware dumps are not imported. Existing historical files are retained.
The six Claude reports already matched the reference byte-for-byte.

Relative to the reference `.config`, only the two dependency revision strings
and the two descriptor/ME file paths change. The board inputs are now tracked
in this repository rather than relying on untracked files in a blob submodule.
Their contents are unchanged. The EDK2 submodule URL is the local development
repository so unpublished development commits can be fetched reproducibly.
No functional shell or diagnostic fix is part of the baseline.

SHA-256 inputs:

| Input | SHA-256 |
| --- | --- |
| descriptor.bin | `a71b8c312544d2e0be8e0148d7ad52053e2735ca663a2a55e1c6637fdc6553b4` |
| me.bin | `e11310fc96a3402e9cfe11fef1a7197a6c566849d0fe5db44f31dac9cebf1779` |
| EagleStream Fsp.fd | `776100021418dba4fb62446e7c420ce2bd161e849fc6d19c9f72b80a6b479e77` |

## Build and validation

Use the reference toolchain, not the newer compiler build in this checkout:

```sh
make -j8 obj=build/reference-baseline build/reference-baseline/UEFIPAYLOAD.fd \
  XGCCPATH=/home/uefi/workspace/coreboot/util/crossgcc/xgcc/bin/
# The baseline recipe writes to build/ even when obj points elsewhere.
cp -p build/UEFIPAYLOAD.fd build/reference-baseline/UEFIPAYLOAD.fd
make -j8 obj=build/reference-baseline \
  CONFIG_PAYLOAD_FILE=build/reference-baseline/UEFIPAYLOAD.fd \
  XGCCPATH=/home/uefi/workspace/coreboot/util/crossgcc/xgcc/bin/
```

The reference GCC identifies as coreboot toolchain
`v2024-12-19_e3150e819d`, GCC 14.2.0. The payload checkout fetches from
`/home/uefi/workspace/uefi_edk2`; `.config` pins the paired commit rather than
the moving branch. EDK2 source edits belong in that development repository.
After committing an update there, fetch it into the payload checkout, select
the exact revision, update `.config` and the gitlink, and commit coreboot with
the same message. Never build an unrecorded moving payload revision.

Build success and hardware behavior are not yet established. New Git commit
IDs/timestamps enter generated firmware metadata, so identical source does not
by itself imply a byte-identical ROM or identical banner text. Compare ROM
contents and captured VGA/SOL behavior explicitly before claiming equivalence.
The reference has no current `build/coreboot.rom` available for a binary
comparison. Do not claim the unreachable-shell issue has been fixed merely
because the baseline compiles.

Previous local EDK2 build output and no-longer-referenced AMD submodule
directories are retained under `.git/baseline-backup-20261009/`; no reference
repository files are changed.

## Result — 2026-10-09

Coreboot baseline commit: `34ed879d4c7108d83c9d8267d364254304bbba27`.
The fresh EDK2 build completed, and the paired 64 MiB ROM was packaged with
the 256 KiB preserved SMMSTORE region. Artifacts:

- `build/reference-baseline/UEFIPAYLOAD.fd` SHA-256:
  `f656dd345ca3d9beb21ae87964e7b217e9488c6aa046c4d3914b8cf4399b2537`
- `build/reference-baseline/coreboot.rom` SHA-256:
  `e0aba4de943e33cd3e70ba5acd3fd382de968e79ae8fd41b4ba3cfa3921a8952`
- Build logs: `build/reference-baseline/rebuild.log` (EDK2),
  `build/reference-baseline/package.log` (final ROM packaging).

The initial coreboot-only build reused an old `build/UEFIPAYLOAD.fd`; its ROM
was moved to `.git/baseline-backup-20261009/coreboot-stale-payload.rom` and is
not the verified paired artifact. The reference payload recipe's hard-coded
output directory required the explicit copy above. The subsequent fix commit
makes the output follow `obj` and records the payload path in `.config`.
Make reported a future timestamp on a generated dependency file during
packaging; artifact structure/contents must be checked independently.
Hardware validation remains pending.
