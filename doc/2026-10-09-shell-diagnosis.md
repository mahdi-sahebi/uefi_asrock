# VGA/SOL and pre-shell boot diagnosis — 2026-10-09

## Evidence and limits

The user reports that the development image has no VGA output, while the
separate reference tree displays VGA and reaches DXE. The paired baseline
restores the reference firmware source/dependencies and preserves it before
fixes. Neither this source restoration nor the fixes below have been booted
on the physical board in this session.

The historical SOL capture
`1405-05-30/SOLHostCapture_Archive_6_01011970_08_05_33.txt` shows:

1. PEI dispatch and the PCD PEIM.
2. `ASSERT [PeiCore] AcpiTimerLib.c(57): GuidHob != ((void *) 0)`.
3. SMMSTORE at `0xFF000000`, four blocks of `0x10000` bytes each.
4. Another timer assertion and dispatch into FaultTolerantWritePei.

That capture predates the current build and does not prove its final failure
point. The six Claude reports under `reports/claude/` were read and retained
unchanged. They discuss an older EDK2 revision, and their SMMSTORE-off statement
conflicts with their later summary and the actual reference config. Therefore
re-enabling SMMSTORE or the shell alone is not a sufficient diagnosis: both
are already enabled. The fresh baseline payload includes the Shell application
GUID `7C04A583-9E3E-4F1C-AD65-E05268D0B4D1`.

## Concrete defects corrected after the baseline

- **DXE entry diagnostics call an unavailable timer.**
  `MdeModulePkg/Core/Dxe/DxeMain/DxeMain.c` invokes its first checkpoint before
  memory/GCD services set `gHobList`. That checkpoint previously called
  `MicroSecondDelay`, whose ACPI implementation calls `GetHobList`, which
  asserts when the DXE HOB list is NULL. With assertions not stopping execution,
  the unavailable timer can still return a constant zero and cause the delay
  loop to spin. Delay is now gated until library constructors have completed;
  the early VGA/serial checkpoint remains available.
- **Early PEI does not yet have the ACPI board HOB.**
  `DasharoPayloadPkg/Library/AcpiTimerLib/AcpiTimerLib.c` checked for an absent
  HOB list but not for an absent ACPI HOB within an existing list. It now defers
  initialization in both cases. `BlSupportPei` publishes the HOB later.
- **FTW diagnostics read a NULL signal-PPI interface.**
  `MdeModulePkg/Universal/FaultTolerantWritePei/FaultTolerantWritePei.c` defines
  its completion PPI with `.Ppi = NULL`, yet two debug arguments dereferenced
  that pointer. These reads are removed; the installation result is logged
  as a correctly typed `EFI_STATUS`.
- **FTW geometry and scan arithmetic lacked failure handling.**
  Lookup and UINT64-to-UINTN conversion errors now return explicitly. Zero,
  undersized, overflowing and unaddressable regions are rejected before
  dereferencing memory. The reverse scan stops before unsigned subtraction
  can leave the spare region. SMMSTORE publication also validates block
  arithmetic, MMIO bounds, and HOB allocation.
- **Early debug delays can resemble a hang.**
  PEI Core and FTW used hundreds of millions/billions of arithmetic iterations
  per debug pause. Those delays are removed, without introducing TimerLib
  calls before the ACPI HOB exists. Existing calibrated DXE delays remain once
  libraries are initialized.
- **Serial checkpoint visibility was inconsistent.**
  SEC selected a null DebugLib. It now uses serial DebugLib and constructor-free
  CF8 PCI access, matching the early PEI model. The initial attempt exposed a
  constructor cycle through the default PCI Express library; the SEC-specific
  PCI selection resolves that dependency and avoids requiring an ACPI HOB.
  Formatted custom SEC/PEI/SMMSTORE/FTW checkpoints now use DEBUG_ERROR, as the
  existing DXE checkpoints already do. VGA helpers have row/column bounds and
  volatile framebuffer stores. Coreboot allows BIOS_DEBUG output, and EDK2
  uses mask `0x8000004F` (error, info, load, warning and initialization).
- **Alternate build directories could embed a stale payload.**
  Coreboot's EDK2 recipe always moved its output to `build/UEFIPAYLOAD.fd`.
  The output now follows the parent make target; `.config` resolves the payload
  through `$(obj)`. Payload updates fetch the local development branch but
  build an exact recorded commit. Optional nested dependency test corpora are
  not initialized by the synchronization helper.

These are source-proven boot blockers and diagnostic defects. They do not
establish that every possible board-specific shell/console problem is solved.

## Verification and reproduction

Host regression checks compile the actual guard functions from source, with
stubs for firmware services, under the undefined-behavior sanitizer. They cover
missing HOB list, missing ACPI HOB, valid timer initialization, pre/post-library
DXE checkpoints, normal/invalid FTW geometry, IA32 address limits, exact boundary
matches, and no-match spare scans including a low address that would underflow.
The IA32 checks simulate address-width arithmetic on the host; the firmware
build separately compiles the real IA32 modules.

```sh
python3 /home/uefi/workspace/uefi_edk2/DasharoPayloadPkg/Tests/BootRegressionTest.py
make -j8 obj=build/shell-fix \
  XGCCPATH=/home/uefi/workspace/coreboot/util/crossgcc/xgcc/bin/
```

The paired fix commits share the message:
`fix: unblock PEI/DXE diagnostics and preserve SOL visibility`.
The EDK2 fix revision is
`2646640ee3919f57c675ee90f670b63d7756271d`. Its exact revision is recorded
both in `.config` and in the coreboot
payload gitlink. Build artifacts and logs are under `build/shell-fix/`.
Baseline artifacts remain under `build/reference-baseline/`.

After future EDK2 changes, commit them in the development repository, then run:

```sh
util/scripts/sync-edk2-payload.sh
```

The script refuses dirty EDK2 worktrees, fetches `feature/vga` from the local
development repository, pins its exact commit, and appends a dated result to
`doc/plan.md`. Commit coreboot's updated `.config`, payload gitlink and plan
using the same full message as EDK2. It does not push or flash anything.

## Remaining hardware validation

Capture a cold boot and warm reboot with VGA and SOL at 115200 baud. Record
the exact ROM hash and whether the following stages appear:

- `[GX-SEC]`, `[GX-PeiCore]`, `[GX-PeiDispatch]`.
- `[GX-SmmStorePei]` and `[GX-FTW] completion PPI installed: Success`.
- `[GX-BlSupportPei]`, DXE IPL handoff and `[GX-DXE] ... DxeCore entry`.
- `DXE library constructors completed`, dispatcher completion and BDS handoff.
- Boot menu access and an interactive UEFI Shell prompt (keyboard and/or SOL).

If output stops earlier, use the last marker and error status as evidence; do
not infer execution stopped solely because VGA is blank. If DXE reaches BDS
but there is no usable console, investigate the board's GOP/console and input
paths next rather than claiming a missing shell binary. No BMC firmware change,
remote reboot, or flash operation is performed by this implementation.
