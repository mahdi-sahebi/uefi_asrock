# Gooxixe G4DEL / Xeon Sapphire Rapids bring-up plan

## Purpose

Bring up the Gooxixe/Gooxi G4DEL platform using the coreboot implementation
based on the ASRock SPC741D8 board support, with the Dasharo EDK2 payload, and
make it possible to identify the exact point where execution stops before the
EDK2 menu or UEFI Shell.

Implementation is now in progress. The copied `DasharoPayloadPkg` directory
remains out of scope and must not be modified.

## Implementation status

- Coreboot error-only serial policy and board-specific log-level override:
  implemented.
- G4DEL SOL selection on AST SUART2/`0x2f8`: implemented based on the
  existing board comments; verify on hardware before flashing.
- Coreboot payload VGA checkpoints with 500 ms delays: implemented.
- EDK2 PEI/DXE IPL and DXE Core/BDS checkpoints with 500 ms delays:
  implemented in the active EDK2 source tree.
- EDK2 debug/shell/menu configuration: enabled in the active build config.
- Full EDK2 payload build and hardware validation: pending.

## Scope and invariants

- Use the `asrock-spc741d8` board support as the starting point for the Xeon
  Sapphire Rapids platform.
- Confirm the exact Git base branch and commit before changing source. The
  currently checked-out branch must not be assumed to be the intended base.
- Do not modify, regenerate, replace, or reformat the copied
  `DasharoPayloadPkg` directory.
- Do not overwrite existing local changes, generated logs, build output, or
  EDK2 workspace artifacts. Record them first and keep the debugging work in
  separate commits or a separate worktree where practical.
- Keep the instrumentation clearly identifiable and removable after bring-up.
- The first debugging image is allowed to be slow because it pauses after
  checkpoints; this must not become an implicit production default.

## Phase 0: establish the build baseline

1. Record:
   - Git branch, commit, and remotes.
   - The intended `asrock-spc741d8` base branch/commit.
   - `git status` for coreboot and every nested EDK2 repository.
   - The active `.config`, toolchain versions, FSP version, EDK2 repository,
     EDK2 revision, and Dasharo build parameters.
2. Verify that the board selected by Kconfig is the SPC741D8 board and that
   the SoC is Sapphire Rapids/Sapphire Rapids-SP rather than a superficially
   similar Xeon board.
3. Confirm the actual EDK2 source used by the build. The coreboot build system
   can select an EDK2 repository and revision; the source used for the build
   must be the source inspected and instrumented.
4. Build an untouched baseline image before adding new instrumentation. Save:
   - the build log;
   - the CBFS listing;
   - the resulting image hash;
   - the serial/SOL output from a cold boot and a warm reboot.

## Phase 1: verify hardware paths

### Serial and SOL

1. Identify which UART is physically connected to the G4DEL BMC SOL channel.
   The existing SPC741D8 debug code refers to an AST Super I/O UART and a
   possible second UART at I/O base `0x2f8`, but this must be verified against
   the G4DEL wiring and current board configuration.
2. Verify the complete path independently:

   CPU/PCH UART decode -> Super I/O or AST UART -> eSPI/LPC routing -> BMC ->
   SOL client.

3. Use a short, unmistakable early-boot test string only while validating the
   path. Confirm baud rate, data format, flow control, and whether SOL is
   connected to UART1 or UART2.
4. Remove or disable the raw test once the normal coreboot console path is
   proven. The final debug trace must use the configured console path so that
   coreboot and EDK2 output can be correlated.

### VGA

1. Confirm that the VGA text buffer at `0xB8000` is usable at the point where
   the coreboot and PEI checkpoints run.
2. Determine when EDK2 switches from VGA text memory to a GOP/framebuffer or
   reinitializes the console. A write to `0xB8000` after that transition may
   not be visible even though execution continues.
3. Keep VGA checkpoints as an early-boot fallback, and use the active EDK2
   console/debug path for checkpoints after console initialization.

## Phase 2: configure the debug image

### Coreboot serial output

Configure the board debug image to:

- enable `CONSOLE_SERIAL`;
- route the console to the verified UART/SOL path;
- use the coreboot error threshold (`BIOS_ERR`) so errors, critical, alert,
  and emergency messages remain visible while debug/info/spew messages are
  suppressed;
- ensure the setting applies to bootblock, romstage, postcar, ramstage, and
  any relevant SMM diagnostic path.

Use coreboot's supported log-level override mechanism if a board-specific
choice cannot force the console-level choice. Do not rely on a stale generated
`build/config.h`; regenerate configuration and verify the effective symbols.

### EDK2 serial output

Enable EDK2 serial support and ensure that the serial terminal is not disabled
by the payload build parameters. Configure the active EDK2 debug libraries to
emit only `DEBUG_ERROR` (the error bit, `0x80000000`) through the serial
debug path. If the selected EDK2 revision uses both fixed and runtime debug
level PCDs, set both relevant PCDs to the error bit through build parameters
or a non-copied build overlay.

Do not edit the copied `DasharoPayloadPkg` directory to make this change. Use
the coreboot EDK2 build configuration/custom build parameters or a separate
overlay that is explicitly selected by the build.

### Menu and Shell targets

For the debug image:

- enable the EDK2 boot manager/menu;
- enable the boot-manager escape key path;
- set a sufficiently long boot timeout for observation;
- enable the EDK2 UEFI Shell package/application;
- keep serial terminal support enabled;
- make sure the shell is not removed by a release-only package rule;
- disable secure-boot restrictions only if they prevent the debug shell from
  launching, and record that change.

The first success criterion is reaching the EDK2 menu. The second is launching
the UEFI Shell and obtaining a usable prompt over the intended console.

## Phase 3: add checkpoint instrumentation

### Common checkpoint format

Use one common, searchable format on both VGA and serial, for example:

`[GX-DXE] seq=NN phase=<phase> event=<event> status=<EFI status>`

Each checkpoint should include enough context to identify the last completed
operation without requiring a second log source. Status values should be
printed for every EFI operation that can fail. Include addresses only where
they are safe and useful; avoid dereferencing unvalidated pointers merely to
print diagnostics.

### VGA output and delay semantics

1. Centralize checkpoint output in a small helper rather than manually adding
   unrelated print-and-delay pairs throughout the code.
2. Emit the checkpoint to VGA and serial with the same sequence number and
   text.
3. Add a calibrated 500 ms delay after each logical VGA checkpoint. Use the
   EDK2 timer/delay library available in the active PEI/DXE build rather than
   an uncalibrated nested busy loop.
4. A clear-screen operation is not 25 independent diagnostic checkpoints; it
   should not cause 25 delays. A hex dump is one logical checkpoint followed
   by one delay after the dump completes.
5. Put the final delay immediately before a non-returning DXE handoff. A
   checkpoint after a successful handoff is not expected to execute.
6. Make the delay and checkpoint code debug-build-only or controlled by a
   clearly named build option so normal firmware is not slowed down.
7. Bounds-check VGA row and column values and ensure formatted strings cannot
   overrun the VGA line buffer.

### Required checkpoint coverage

Instrument the path in this order:

1. Coreboot payload lookup and payload load.
2. Entry into the EDK2 PEI image.
3. DXE IPL PEIM initialization.
4. PEI shadow registration and permanent-memory discovery.
5. Guided-section and decompression PPI installation.
6. HOB validation and key HOB addresses.
7. DXE Core firmware-volume search.
8. DXE Core file discovery.
9. PEI Load File PPI lookup and DXE Core image load.
10. DXE Core file information and module HOB creation.
11. Stack allocation, IDT setup, page-table creation, and memory protection.
12. End-of-PEI PPI installation.
13. IA32-to-long-mode transition where applicable.
14. Final handoff to `DxeCore`.
15. DXE Core entry and early DXE dispatcher initialization.
16. DXE driver dispatch start, progress, failure, and completion.
17. Console/GOP initialization.
18. Platform Boot Manager entry, boot option enumeration, menu entry, and
    shell launch.

Every error return should produce a serial `DEBUG_ERROR` record and a VGA
record when VGA is still available. Assertions and dead loops should have a
last checkpoint immediately before them.

## Phase 4: build and inspect

1. Regenerate Kconfig output from the intended baseline.
2. Build the EDK2 payload separately first, checking that the build uses the
   intended EDK2 revision and does not rewrite the copied payload directory.
3. Inspect the payload contents and confirm the shell and serial components
   are present.
4. Build coreboot with the payload embedded.
5. Inspect CBFS and confirm the expected payload name, compression, size, and
   board configuration.
6. Preserve the complete build command and logs for reproducibility.
7. Do not flash until the image identity and target programmer/device are
   independently verified.

## Phase 5: hardware test procedure

For each test, capture SOL output, VGA observations, reset type, and the last
checkpoint.

1. Cold boot with no keyboard input.
2. Cold boot with the EDK2 boot-menu escape key held.
3. Warm reboot.
4. Boot with DIMM population matching the known-good SPC741D8/G4DEL setup.
5. Boot with optional PCIe devices removed, then add them back one at a time
   if the failure point changes.
6. Attempt to reach the EDK2 menu.
7. Attempt to launch the UEFI Shell.
8. From the shell, verify memory, PCI, filesystem, and console visibility as
   needed for the next debugging step.

The last checkpoint is the primary result. Do not infer a DXE failure merely
because the VGA screen stopped changing; verify whether serial checkpoints
continued after VGA became unavailable.

## Failure triage map

- No coreboot serial output: investigate UART decode, Super I/O/AST routing,
  eSPI/LPC setup, SOL configuration, or baud mismatch.
- Coreboot output stops before payload entry: investigate CBFS payload lookup,
  decompression, memory mapping, or payload entry address.
- PEI checkpoints stop before DXE Core discovery: investigate HOBs, permanent
  memory, PPIs, and firmware-volume access.
- DXE Core load succeeds but handoff fails: investigate stack, IDT, page
  tables, long-mode transition, memory permissions, and entry-point address.
- Serial reaches DXE but VGA stops: treat this first as a console transition,
  GOP, or VGA ownership issue rather than an execution failure.
- DXE Core starts but no menu: investigate DXE dispatcher errors, missing
  console/GOP drivers, boot-manager policy, boot timeout, and shell package
  inclusion.
- Menu appears but Shell is absent: inspect shell build flags, FV contents,
  boot options, secure-boot policy, and shell launch dependencies.

## Acceptance criteria

The work is complete when all of the following are true:

- The image is built from the intended `asrock-spc741d8` base and the verified
  EDK2 revision.
- The copied `DasharoPayloadPkg` directory remains unmodified.
- Coreboot and EDK2 serial/SOL output show only error-level diagnostics plus
  the explicitly added `DEBUG_ERROR` checkpoints.
- Every checkpoint has a corresponding VGA output while VGA is available.
- Each logical VGA checkpoint is followed by approximately 500 ms of delay.
- The serial trace identifies the last successful stage on failure.
- The system reaches the EDK2 menu.
- The system can launch and use the UEFI Shell, or the remaining blocker is
  narrowed to a specific documented hardware or firmware operation.

## Cleanup after diagnosis

After the failing operation is identified, save the logs and checkpoint map,
then remove or disable the 500 ms delays and temporary raw UART tests. Keep
the useful error handling and a minimal optional checkpoint mode in a separate
debug configuration. Rebuild and compare the normal image against the saved
baseline before considering the work complete.

## Plan update — 2026-10-09 21:34 CEST (Europe/Amsterdam)

### Update policy and authorization

- Append each subsequent plan update at the end of this file with its local
  date/time, the change or finding, and the actual result, including pending
  validation. Preserve earlier entries as history; the latest explicit
  correction takes precedence over conflicting earlier statements.
- Only this documentation update is authorized now. Implementation, source
  synchronization, configuration changes, builds, and commits remain on hold
  until the user confirms starting the baseline-first sequence.
- The earlier statement that implementation is in progress describes prior
  work, not authorization to resume it in this session.

### Corrected observations and logging requirements

- The user reports that the current development image has **no VGA output**.
  Existing instrumentation and earlier implementation notes do not establish
  that VGA works. The separate `/home/uefi/workspace/coreboot` reference is
  reported to display VGA output and reach DXE; do not conflate these images.
- The user reports that current serial/SOL output is **not limited to errors**.
  Record observed output separately from configured filters. The current
  `.config` passes `0x80000000` for both EDK2 debug-level PCDs, but this does
  not prove that every serial/SOL output path honors those filters.
- Keep broader serial/SOL visibility and emit our custom EDK2 diagnostics
  through the serial debug path at `DEBUG_ERROR` level. Custom checkpoint
  coverage must include SEC/SecCore, PEI entry, PeiCore and PEIM entry/dispatch,
  SmmStore and related variable/FTW paths, DXE IPL, DXE Core and dispatch, and
  the boot-manager/shell handoff. A `DEBUG_ERROR` checkpoint is an intentional
  diagnostic marker, not necessarily a reported firmware failure.
- The earlier error-only serial acceptance criterion is superseded by this
  update. After implementation is authorized, verify the actual libraries,
  filters, UART routing, and any direct serial writes against captured SOL
  output; do not claim successful logging from PCD settings alone.

### Baseline-first implementation sequence — pending confirmation

1. Use `/home/uefi/workspace/coreboot` as the reference. Its inspected coreboot
   HEAD is `0175444e946cc7f595d7f8bba770b038a118954d`; its configured payload
   checkout, `payloads/external/edk2/workspace/mahdi-sahebi`, is at
   `ec1955278bd437aaea828f1217bfcab9b396a6e8`. Capture all effective build
   inputs, dependency revisions, local files, and toolchain details before
   synchronization, including any ignored files used by the build.
2. Match `/home/uefi/workspace/uefi_edk2` to the reference EDK2 source and
   dependencies, and create the EDK2 baseline commit first. Preserve existing
   history. Do not add shell fixes or new instrumentation to this baseline.
3. Match `/home/uefi/workspace/test/uefi_coreboot` to the reference coreboot
   source, configuration, and dependencies, then synchronize its EDK2 payload
   checkout to the exact new EDK2 baseline commit. Document any necessary
   revision-pinning or local-path differences from the reference explicitly.
4. Bring the reference `doc/` content and relevant `logs/` text and pictures
   into the current project's `doc/`, including the Claude reports. Exclude
   firmware dumps, binary build artifacts, archives, and movies from this
   documentation import. Preserve existing local documentation and do not
   import the reference `.gitignore`.
5. The proposed baseline plan includes the board's required `descriptor.bin`
   and `me.bin` as explicit exceptions to the binary-copy exclusion; this
   interpretation was included in the pending confirmation request. Verify
   their hashes and build paths against the reference.
6. Create the coreboot baseline commit with exactly the same full commit
   message as the EDK2 baseline commit:
   `baseline: reproduce reference VGA output and DXE handoff`.
   Record both resulting commit hashes and the exact payload revision used by
   coreboot. The repositories will have different commit hashes.
7. Verify source/input equality, build the paired baseline, and inspect the
   payload and ROM. Record image hashes, build commands, and any remaining
   differences. Identical boot behavior and VGA output remain unverified until
   a corresponding hardware run is captured; compilation is insufficient.
8. Only after preserving the paired baseline, read the complete Claude
   analysis, correlate it with the actual source and latest boot evidence,
   diagnose missing VGA and the unreachable UEFI Shell, and make subsequent
   fixes in separate commits. Both inspected configs already enable
   `CONFIG_EDK2_HAVE_EFI_SHELL`; inclusion alone does not prove launchability.
9. After every EDK2 update, commit in `/home/uefi/workspace/uefi_edk2`, pull or
   fetch that development branch into the current coreboot payload checkout,
   and select and verify the exact intended commit. Record the paired revision
   in coreboot so a moving branch cannot silently change a reproducible build.
   Use identical full commit messages for corresponding EDK2/coreboot pairs.

### Result

Plan updated by appending this entry only. No firmware source, configuration,
dependency checkout, or Git history was changed; no build, flash, or hardware
test was performed. The reference Claude report directory and the current
`doc/reports/claude/` were compared and are byte-for-byte identical. Full
analysis review, baseline reproduction, VGA recovery, SOL verification, and
shell diagnosis/fixes are pending implementation confirmation. Current absence
of VGA and the serial/SOL behavior above are user-reported observations.

## Plan update — 2026-10-09 21:45 CEST (Europe/Amsterdam)

The user authorized implementation. The reference-first sequence is now active.
Backup branches preserve both previous development tips. The EDK2 baseline
commit is `2c42a878f26d7078b54fe83ece24bb57f87d3020`; its complete Git tree
matches the reference `ec1955278bd437aaea828f1217bfcab9b396a6e8` exactly.
Coreboot source and dependency revisions have been restored to the reference.
The copied DasharoPayloadPkg was restored as required by the user's explicit
reference-matching request, which supersedes the earlier blanket prohibition
on replacing that package. Subsequent functional edits still require evidence.

The active EDK2 checkout and `.config` now pin the paired EDK2 commit. The
reference descriptor and ME contents are included as tracked board inputs;
only paths and dependency pins differ in the baseline configuration. Text and
pictures from reference logs were copied into `doc/`, excluding new binary,
archive, and movie imports. Existing project documentation remains preserved.

Result: EDK2 baseline committed and content equality verified; coreboot baseline
prepared for its matching commit and clean build. See `reference-baseline.md`
for input hashes, provenance, reproduction instructions, and metadata limits.
No runtime fix has been introduced and no hardware has been flashed.

## Plan update — 2026-10-09 21:54 CEST (Europe/Amsterdam)

Result: paired baseline commits are preserved: EDK2 `2c42a878f26d` and coreboot
`34ed879d4c71`, both with the agreed identical message. A fresh EDK2 payload
and a 64 MiB coreboot ROM were built; hashes and build-path caveats are recorded
in `reference-baseline.md`. No hardware execution is claimed.

The complete six-file Claude analysis was read. Its claims refer to older
revisions and contain inconsistent SMMSTORE status descriptions; the actual
reference config enables SMMSTORE and the stored SOL trace shows valid geometry.
Current source inspection found concrete additional blockers:

- DXE's first diagnostic checkpoint calls TimerLib before its HOB services and
  library constructors are ready.
- The ACPI timer constructor assumes an existing HOB list already contains the
  ACPI board HOB, which a later PEIM actually creates.
- FTW diagnostics dereference the deliberately NULL interface of a signal PPI;
  lookup/conversion errors and spare-scan bounds also need guards.
- Early PEI/FTW debug delays run hundreds of millions/billions of iterations;
  SEC uses a null DebugLib, suppressing its custom serial diagnostics.
- The payload build recipe writes to `build/` regardless of `obj`, allowing an
  alternate-output build to embed a stale payload unless explicitly corrected.

Fixes are being prepared in a separate commit pair. Early PEI and pre-constructor
DXE markers must not depend on an unavailable timer; calibrated DXE delays are
retained after constructors. This supersedes the unconditional early-checkpoint
delay requirement. Custom markers use DEBUG_ERROR alongside broader normal
bring-up logging. Host regression checks of actual guard functions pass for
native X64 and simulated IA32 address-width geometry; full firmware build and
VGA/SOL/shell validation of the fixes are pending.

## Plan update — 2026-10-09 21:54 CEST (Europe/Amsterdam)

Synchronized EDK2 branch `feature/vga` from `/home/uefi/workspace/uefi_edk2`.
Result: payload HEAD and `.config` select `5b0e13cd9ec781ac81c34d9ed4752d8f02d0206c`.
Build, hardware validation, and the matching coreboot commit are pending.

## Plan update — 2026-10-10 03:14 CEST (Europe/Amsterdam)

The paired fix implementation and local verification are complete. EDK2 commit
`2646640ee3919f57c675ee90f670b63d7756271d` and the corresponding coreboot
commit use the identical message `fix: unblock PEI/DXE diagnostics and preserve
SOL visibility`. Coreboot pins that exact EDK2 revision in both `.config` and
the payload gitlink.

Result: the host regression test passes for native X64 and simulated IA32
address arithmetic. The full EDK2 and coreboot builds complete without compiler
or linker errors. The resulting 64 MiB image contains a 1,280,517-byte payload,
the expected FSP and microcode files, descriptor and ME regions, and a preserved
256 KiB SMMSTORE region. The built payload contains the UEFI Shell application
GUID `7C04A583-9E3E-4F1C-AD65-E05268D0B4D1`.

The completed pre-final-commit artifacts were:

- `build/shell-fix/UEFIPAYLOAD.fd`:
  `b76ce84fabe0c1da56a1feb4e529b2221efe7492c8ddd0f5478c043a11dba61f`
- `build/shell-fix/coreboot.rom`:
  `812ecb73a63489bc3b74dc1600691b0e784ae6331a08148b296c6a85f7615f6c`

The build reports clock skew because generated dependency files have timestamps
in the future relative to the execution clock. No build failure resulted, but
a final rebuild is required after this documentation is committed so embedded
Git metadata corresponds to the final coreboot commit. The diagnosis and exact
hardware validation procedure are recorded in
`doc/2026-10-09-shell-diagnosis.md`. VGA, SOL progression, boot-menu access,
and an interactive shell remain pending a real board flash and capture; they
are not claimed from static inspection or build success.

## Plan update — 2026-10-09 21:56 CEST (Europe/Amsterdam)

Synchronized EDK2 branch `feature/vga` from `/home/uefi/workspace/uefi_edk2`.
Result: payload HEAD and `.config` select `2646640ee3919f57c675ee90f670b63d7756271d`.
Build, hardware validation, and the matching coreboot commit are pending.
