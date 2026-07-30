# MacBookPro12,1 Internal Keyboard/Trackpad Not Working Under Linux

## Status: unresolved

The internal keyboard and trackpad on this 2015 13" MacBook Pro
(MacBookPro12,1, no Touch Bar) do not work under Arch Linux. This has been
reproduced on two separate installs (an older one with accumulated
config, and a from-scratch fresh install), across two bootloaders (GRUB
and rEFInd), and survives every fix that normally addresses this class of
problem on Mac hardware. This document explains the hardware/software
background in enough depth to pick this up cold, then lists everything
that has been tried, then ends with a short, submittable bug report.

---

## Background - the technologies involved

This section explains the pieces involved, for anyone picking this up
without prior context.

### How the keyboard/trackpad are physically connected

**Correction (see step 19 in the timeline below):** this document
originally stated that MacBookPro11,x/12,1 are plain USB-wired, full
stop, and that SPI was categorically the wrong bus for this model. That
was an overcorrection based on a maintainer comment that was actually
about a different model generation (MacBookPro15,x). The real picture,
confirmed by reading the mainline `applespi.c` driver source directly and
by decompiling this machine's actual DSDT, is more specific:

This model's keyboard/trackpad controller is **dual-mode** - the same
physical pins can carry either a USB signal or an SPI signal, and a
firmware-controlled electrical switch (implemented as real ACPI methods
backed by real GPIOs, not a placeholder) selects which one is active at
any given time:

- `UIEN`/`UIST` (USB Interface Enable/Status) and `SIEN`/`SIST` (SPI
  Interface Enable/Status) are ACPI methods, defined on this exact
  machine's DSDT under `\_SB.PCI0.SPI1.SPIT`, that toggle two GPIO pin
  groups (`GD26`/`GP26` for USB, `GD13`/`GP13` for SPI) - calling
  `SIEN(1)` internally calls `UIEN(0)` and vice versa, i.e. the two modes
  are mutually exclusive on the wire.
- The mainline kernel's own `applespi.c` source states this directly, in
  its top-of-file comment: *"The keyboard and touchpad controller on the
  MacBookAir6, MacBookPro12, MacBook8 and newer can be driven either by
  USB or SPI. However the USB pins are only connected on the MacBookAir6
  and 7 and the MacBookPro12... UIEN and UIST are only provided on models
  where the USB pins are connected."* In other words: MacBookPro12,1 is
  explicitly named as one of the small number of models with *both*
  wiring modes present, not as a USB-only exception to SPI-based models.
- What actually happens on boot: this machine's firmware defaults to USB
  mode (`UIST=1`) under Linux. `applespi`'s own probe function checks
  `UIST` first, and if it sees USB already active, it deliberately backs
  off with `-ENODEV` rather than attempting to switch modes itself - by
  design, not by bug (see step 19).

So "is this SPI or USB" was the wrong framing from the start - it's both,
with a live runtime switch, and the real open question is which mode
should be active and why the driver doesn't switch it automatically on
this model.

### xHCI, ports, and enumeration

USB devices are managed by a **host controller** - on modern PCs this is
an **xHCI** (Extensible Host Controller Interface) controller, a
standardized piece of silicon that all USB-capable operating systems
talk to via a well-defined register interface. On this Mac, the xHCI
controller is built into the Intel chipset: **Intel Wildcat Point-LP
xHCI**, PCI ID `8086:9cb1`, PCI address `0000:00:14.0`, using the
`xhci_hcd`/`xhci_pci` Linux kernel drivers.

An xHCI controller exposes multiple **ports** (both physical, exposed
connectors, and internal, hardwired-to-a-fixed-device ports). Linux
tracks each port's `connect_type` in sysfs - `hotplug` for a real
external connector, `hardwired` for an internal device that's
permanently wired to that port and can never be unplugged. On this
machine, two ports report `connect_type: hardwired`:

- `usb1-port3` (ACPI path `\_SB_.PCI0.XHC1.RHUB.HS03`) - the internal
  **Bluetooth** controller (`05ac:8290`). This one works correctly.
- `usb1-port5` (ACPI path `\_SB_.PCI0.XHC1.RHUB.HS05`) - the internal
  **keyboard/trackpad**. This is the port that never enumerates a
  device under Linux.

Each xHCI port has a hardware register called **portsc** (Port Status and
Control). Two bits matter here:

- **PP** (Port Power, bit 7) - whether the controller is supplying power
  to the port.
- **CCS** (Current Connect Status, bit 0) - whether the controller's
  hardware has detected something physically connected to that port.

The normal sequence for a device to become usable is: the port is
powered (PP=1) → hardware detects a physical connection and sets CCS=1 →
the host controller driver notices the change and starts USB enumeration
(assigning an address, reading descriptors, loading a matching driver).
If CCS never becomes 1, nothing past that point can happen - there is no
"device" for Linux's USB stack to even attempt to talk to. This is a
hardware-visible signal, not something a driver decides to ignore.

### ACPI's role

**ACPI** (Advanced Configuration and Power Interface) is the standard
firmware/OS interface for hardware description and power management.
The system firmware ships tables (DSDT, and various SSDTs - Secondary/
Differentiated System Description Tables) written in a bytecode
language (AML) that the OS's ACPI interpreter runs. These tables can:

- Describe hardware topology (e.g. which port maps to which named ACPI
  device, like `HS05` above).
- Provide power-control methods (e.g. `_PS0`/`_PS3` to power a device on
  or off) that the OS is expected to call at the right time.
- Branch behavior based on `_OSI` (Operating System Interface) queries -
  a mechanism firmware historically used to detect "am I booting Windows,
  Linux, or macOS" and adjust its own behavior (including, on Apple
  hardware, real hardware initialization differences, not just cosmetic
  ones).

Apple's firmware reports a specific numeric "OS" value depending on what
the bootloader/OS identifies itself as (Darwin, Windows-various, or
Linux - deliberately given the lowest-priority value in this Mac's
tables). This raised a real hypothesis: if the firmware is told
"Darwin," does it initialize the keyboard's hardware differently before
handing off to the OS?

### The Apple `set_os` UEFI protocol

Separately from ACPI's `_OSI`, there is a **pre-boot, firmware-level**
mechanism specific to Apple's UEFI implementation: a UEFI protocol call
(`AppleSetOsVersion`/`AppleSetOsVendor`) that a bootloader can make
*before* the OS kernel even starts, to tell Apple's firmware "the OS
about to boot identifies as macOS version X." This is a real, documented
mechanism - not a hack - used historically to work around Macs disabling
a secondary GPU when they think a non-Apple OS is booting.

This is distinct from `_OSI`: `_OSI` is evaluated by AML bytecode *at
runtime*, while `set_os` is a discrete firmware call made once, early,
by the bootloader, before `ExitBootServices` (the point where firmware
hands control to the OS permanently). Both **rEFInd** (config option
`spoof_osx_version`) and, briefly, **Limine** (a regression introduced
in v11.3.1, reverted in v11.4.0 - see `CachyOS/distribution#415`)
implement this call. **GRUB does not** - confirmed by reading GRUB's
source and Arch's `grub` package patches; no Apple `set_os` code path
exists in GRUB at all, stock or patched.

This makes `set_os` an interesting, real lever to test - some other
Mac laptops have had their internal keyboard/trackpad *broken* by this
exact call being made when it previously wasn't (the Limine regression),
which is direct proof that this firmware handshake can change whether
this class of internal device initializes. See "Timeline of
investigation" for the result of testing it here.

### Kernel dynamic debug

Linux's `dynamic_debug` facility (`/sys/kernel/debug/dynamic_debug/control`)
lets you turn on verbose logging for specific source files in a running
kernel, without rebuilding anything - useful for getting the xHCI driver
to print its internal state transitions (port power changes, connect/
disconnect events, command completions) that are normally silent.

---

## Symptom

The internal keyboard and trackpad are completely unresponsive under
Linux - not intermittent, not slow to initialize, just never present.
Specifically:

- **Works:** in Apple's own firmware UI, and in macOS Internet Recovery
  Mode (Option+Cmd+R at boot). This is the single most important data
  point - it definitively rules out a hardware fault, a broken internal
  connector/cable, or a dead keyboard controller chip. The hardware is
  fine.
- **Works:** navigating the GRUB boot menu (all keys tested in GRUB shell)
  and the rEFInd boot menu (also confirmed functional with arrow keys).
- **Fails:** the moment a Linux kernel takes over - specifically,
  confirmed dead at the LUKS disk-encryption passphrase prompt (which
  runs extremely early in the boot process, inside the initramfs, before
  almost anything else has loaded) and everywhere afterward inside a
  fully booted Arch Linux system. It also fails in `arch-iso`.

This "works right up until the kernel takes over, then never again"
pattern is what points at something in the kernel's own USB/xHCI
bring-up, or in whatever handoff happens between firmware/bootloader and
kernel, rather than at a missing userspace driver, a misconfigured
service, or a hardware issue.

At the hardware register level: the internal keyboard/trackpad's xHCI
port (`usb1-port5`) shows **PP=1 (powered), CCS=0 (no device
detected)**, and stays that way indefinitely. Manually power-cycling the
port (toggling it via sysfs) produces a clean `portsc` transition from
powered-off to powered-on, but the Connect Status Change bit never
fires - the port's hardware genuinely does not see anything plugged in,
from Linux's point of view, even though the exact same physical hardware
works when queried by Apple's own firmware moments earlier in the same
boot sequence.

---

## Timeline of investigation

### Old install (accumulated config, investigated first)

1. **Initial hypothesis: wrong driver stack.** The install had
   `applespi` + `spi_pxa2xx_platform`/`spi_pxa2xx_pci` (DKMS package
   `macbook12-spi-driver`) loaded via `mkinitcpio.conf`'s `MODULES=`.
   This is the correct driver for SPI-wired Macs, but this model is
   USB-wired (see Background) - so `applespi` was attaching to a
   phantom ACPI SPI device (`spi-APP000D:00`) that doesn't correspond to
   real hardware on this model, and spinning in a tight failure loop
   (`SPI transfer timed out` / `Error reading from device: -110`,
   observed 84,000+ times in one boot's log). This was a real bug -
   fixed by removing the modules from `mkinitcpio.conf`, blacklisting
   them, and rebuilding the initramfs - but fixing it did **not** fix
   the keyboard. The SPI error storm was drowning out the real signal,
   not causing the problem.
2. **Misidentified the port.** Initially suspected `usb2-port3` (which
   turned out to be the internal SD card reader,`05ac:8406`) as the
   keyboard's port. Corrected by checking `connect_type=hardwired`
   across every port on both root hubs, landing on the true candidate
   port (see Background - this is the port later confirmed as `HS05`).
3. **ACPI `_OSI`/`OSYS` Darwin spoofing.** Tested booting with
   `acpi_osi=Darwin` as a kernel parameter, to see if telling the
   firmware "this is Darwin" changed hardware initialization at the
   ACPI level. **No effect.**
4. **ACPI `USBX`/`_DSM` mechanism.** Searched for this because it's a
   known way (on Hackintosh/OpenCore setups) to inject USB port power
   properties. Exhaustively grepped every DSDT/SSDT table on this Mac's
   *real* firmware and confirmed it does not exist here at all - that
   mechanism is OpenCore-injection-only, not something real Apple
   firmware ships. Dead end, not applicable.
5. **Per-port ACPI properties (`_UPC`/`_PLD`/`MUXS`).** Compared the
   ACPI properties on the ports named `HS01`-`HS05`/`SSP1`-`SSP3` under
   the root hub. A `MUXS` property (a mux-switching indicator) was
   present on `HS01`/`HS02` but absent on both `HS03` (Bluetooth) and
   `HS05` (keyboard, broken) - since the *working* port and the
   *broken* port have identical `_UPC`/`_PLD` and both lack `MUXS`, this
   ruled out mux-switching as the differentiator. At the time this
   comparison was made, `HS03`/Bluetooth was only confirmed to enumerate
   a USB device, not confirmed functional at the Bluetooth protocol
   level - see step 17, which closes that gap.
6. **A pre-existing SSDT override (`/boot/spifix.aml`).** Found a
   leftover custom GRUB entry loading a hand-patched ACPI table that
   added a GPIO interrupt to `\_SB.PCI0.SPI1`'s `_CRS`. Decompiled via
   `iasl -d` and confirmed this is a legitimate fix pattern - but for
   SPI-based Mac models, not this USB-wired one. Confirmed ineffective/
   irrelevant here; demoted this GRUB entry back to a normal boot.
7. **S3 suspend/resume.** Tested `rtcwake -m mem -s 15` on the theory
   that a full sleep/wake cycle might re-trigger whatever power sequence
   the port needs. No effect on the keyboard, and it broke `wlan0` as a
   side effect (required a reboot to recover networking).
8. **xHCI controller unbind/rebind.** Unbound and rebound the entire
   xHCI PCI device (`0000:00:14.0`) via
   `/sys/bus/pci/drivers/xhci_hcd/{unbind,bind}`. External USB devices
   re-enumerated instantly and correctly. The internal keyboard port
   was not observed to change state from this.
9. **Internet Recovery Mode test.** Rebooted into Option+Cmd+R.
   Keyboard and trackpad **both work**. This is the finding that ruled
   out hardware/connector/firmware-chip failure for good, and reframed
   this as a Linux-specific software problem.
10. **GRUB-vs-LUKS boot-stage test.** Confirmed the keyboard works to
    navigate the GRUB menu (arrow keys) and can use all keys in the
    advanced shell, but is dead by the time the LUKS passphrase prompt
    appears - pinning the failure precisely to "somewhere between GRUB
    handing off and the initramfs asking for a passphrase," i.e. early
    kernel/initramfs USB bring-up.

At this point, given how much unrelated cruft had accumulated on this
install (the SPI fix, the leftover custom GRUB entry, etc.), the decision
was made to do a fresh install from scratch with a current rolling
kernel, to rule out any interaction with old configuration and get a
clean baseline.

### Fresh install (from scratch, rolling `linux` kernel)

11. **Checked whether a stock kernel avoids the problem at all.** A
    recent, model-exact community install guide
    (`osmartormena/debian13-macbookpro12-1`) makes zero mention of any
    SPI/USB/ACPI workaround and uses a stock kernel, suggesting the
    problem might be specific to old-install cruft rather than the
    hardware/kernel combination itself. This did not hold up - see next
    point.
12. **`applespi` auto-loads via ACPI match on a completely stock
    kernel.** On the fresh install, with zero manual driver
    configuration, `applespi`/`spi_pxa2xx_platform`/`spi_pxa2xx_pci`/
    `spi_pxa2xx_core` all loaded automatically - `applespi` has since
    been mainlined into the kernel and auto-loads via ACPI hardware-ID
    matching against the same phantom `spi-APP000D:00` device. Notably,
    this time there was no timeout-spam log storm (unlike the old
    DKMS-based driver) - just a single benign-looking
    `USB interface already enabled` line. Blacklisted the same three
    modules and rebuilt the initramfs, as a precaution. This did **not**
    fix the keyboard - confirming the SPI angle was always a red
    herring/separate bug, not the root cause.
13. **Reproduced the exact same symptom on the fresh install.** Keyboard
    works at GRUB, dies at LUKS, dead inside Arch - identical to the old
    install. This ruled out "leftover cruft from the old install" as an
    explanation. The bug is specific to this hardware + Linux
    combination, not to accumulated configuration.
14. **Apple `set_os` UEFI protocol theory.** Found a verified (via
    `gh api`, not taken from a search snippet) GitHub issue,
    `CachyOS/distribution#415`, describing an almost identical symptom
    on a MacBookAir7,2: the Limine bootloader's v11.3.1 release added a
    call to Apple's `set_os` UEFI protocol (to keep a secondary GPU
    alive on dual-GPU Macs), and this broke internal keyboard/trackpad
    enumeration on "certain other Apple systems" - reverted in v11.4.0.
    This matched the "works at the bootloader/firmware level, dies once
    the kernel takes over" pattern closely enough to be worth testing
    directly, since it's a genuine pre-kernel firmware-level mechanism
    (see Background).
    - Confirmed GRUB has **no** equivalent mechanism at all (checked
      GRUB's own source and Arch's package patches - no `set_os` related
      code exists in GRUB, patched or unpatched).
    - Installed **rEFInd** (which does implement this, via config key
      `spoof_osx_version`) specifically to test this theory, without
      abandoning GRUB (both bootloaders coexist as separate EFI boot
      entries).
    - Tested `spoof_osx_version` set to `10.9`, `10.12`, and `10.15`, and
      also fully disabled (commented out) as a baseline, booting Linux
      directly through rEFInd each time (not chainloading into GRUB, to
      make sure the setting was actually in effect for the boot that
      matters). **Keyboard failed identically in every case.** This
      theory is now ruled out for this specific hardware - the
      mechanism is real and does affect input devices on some other Mac
      models, but it isn't what's blocking this Mac's keyboard.
15. **Targeted xHCI kernel dynamic-debug trace (fresh install,
    confirmed current).** Enabled verbose kernel logging for
    `xhci-hub.c`, `xhci-ring.c`, `xhci.c`, and `hub.c` via
    `/sys/kernel/debug/dynamic_debug/control`, then manually toggled the
    keyboard's port (`usb1-port5`) via its `disable` sysfs attribute to
    force a fresh power-cycle and enumeration attempt while the trace
    was running. Result: portsc cleanly transitions
    (`0x2a0` → `0x80`, i.e. power off → power on), and the log shows
    the driver explicitly clearing the port's connect-change and
    enable/disable-change bits on its own - but **no Connect Status
    Change ever fires**, and no device-attach sequence ever begins.
    This confirms, at the lowest level Linux can observe, that the xHC
    hardware itself is never signaling a connection on this port to the
    OS - it isn't that Linux detects the device and mishandles it, or
    that a driver rejects it; the hardware-level connect event never
    reaches the OS at all.
16. **Ruled out: wifi power-management changes as a contributing
    factor.** During this investigation, wifi was separately fixed by
    disabling NetworkManager's `wifi.powersave` and switching the
    backend from `wpa_supplicant` to `iwd` (unrelated wifi-connectivity
    bug, not covered in this document). Considered whether either
    change could have affected the keyboard, since both are "early
    hardware bring-up" in a loose sense. Ruled out on two independent
    grounds: (a) timing - the keyboard was already confirmed dead at the
    LUKS prompt, in the initramfs, before `systemd`/NetworkManager even
    start, on the very first boot of the fresh install, well before any
    wifi-related change was made; (b) architecture - the wifi card is a
    separate PCIe device (`0000:03:00.0`, `brcmfmac`) from the xHCI USB
    controller (`0000:00:14.0`, `xhci_hcd`) that owns the keyboard's
    port, and `wifi.powersave`/backend choice only affect 802.11
    protocol-level radio behavior and userspace supplicant software -
    neither touches PCIe power management or USB port signaling on an
    unrelated controller.
17. **Confirmed the Bluetooth port (`HS03`) is functionally working, not
    just enumerating.** Step 5 above only relied on `HS03` enumerating a
    USB device (`05ac:8290`) as the differentiator against the broken
    keyboard port - it hadn't been confirmed working at the Bluetooth
    protocol level itself. Closed this gap: `bluetoothctl show` reports
    the controller `Powered: yes` with a live GATT profile advertised,
    and a real Bluetooth keyboard (Kinesis Advantage360 Pro) was
    successfully paired, trusted, connected, and typed on directly.
    This confirms `HS03` is genuinely fully functional, not merely
    visible at the USB layer - strengthening (not undermining) the
    step 5 conclusion that ACPI per-port properties aren't what
    distinguishes the working port from the broken one. As a side
    benefit, this also gives the machine a working external Bluetooth
    keyboard.
18. **Reproduced on genuine mainline kernel `7.2.0-rc5`.** Before filing
    an upstream bug report, confirmed the issue isn't specific to
    Arch's kernel build or something already fixed upstream but not yet
    backported. Installed `linux-mainline` from the AUR (tracks
    kernel.org's mainline/rc branch, built via `makepkg`), which
    installs alongside the existing kernel as a separate boot entry
    rather than replacing it. Booted `7.2.0-rc5-1-mainline` via rEFInd's
    auto-detected entry, with the `applespi`/`spi_pxa2xx_*` blacklist
    still in effect (confirmed via `lsmod` - blacklists in
    `/etc/modprobe.d/` apply regardless of kernel version) and
    `usb1-port5` still present as `hardwired`. **Keyboard/trackpad
    failed identically** - dead at the LUKS prompt and once logged in.
    This confirms the bug is present on current mainline, not an
    Arch-specific regression or an already-fixed issue.
19. **Reopened the SPI angle - found a real, working USB/SPI mode
    switch, and a new failure mode.** While preparing to file the
    upstream bug report, found a Fedora Discourse thread describing an
    almost identical symptom on the same model, explaining that
    `applespi`'s "USB interface already enabled" log line (which this
    machine also produces) is the driver's `UIST` check finding USB mode
    already active and deliberately backing off, rather than switching
    to SPI itself. Verified this against the actual mainline
    `applespi.c` source (built earlier for step 18, so already present
    on disk) rather than trusting the forum post's technical claims at
    face value:
    - The driver's own top-of-file comment confirms MacBookPro12,1
      by name as a dual-mode model (see "How the keyboard/trackpad are
      physically connected" above, now corrected).
      `applespi_probe()` calls `UIST`, and if it returns 1 (USB active),
      returns `-ENODEV` immediately - before ever calling `SIEN`. It
      never attempts the mode switch on its own when USB is already
      active.
    - Decompiled this machine's real DSDT (via `acpidump -b` +
      `iasl -d`, after installing the `acpica` package) and found
      genuine, non-trivial `UIEN`/`UIST`/`SIEN`/`SIST` method bodies
      under `\_SB.PCI0.SPI1.SPIT`, toggling real GPIO pin state
      (`GD26`/`GP26` for USB, `GD13`/`GP13` for SPI) - not a phantom or
      placeholder device.
    - Installed `acpi_call-dkms` (official `extra` repo) to invoke ACPI
      methods directly from Linux via `/proc/acpi/call`. Confirmed
      baseline state: `UIST=1` (USB active), `SIST=0` (SPI inactive).
      Invoked `SIEN(1)` directly - state flipped cleanly to `UIST=0`,
      `SIST=1`, and the keyboard's USB port (`usb1-port5`) changed from
      its previous silent/no-state condition to a clean `not attached`
      status. This is a genuine, real hardware-level mode switch, not a
      simulated or partial one.
    - Force-loaded `applespi` and the `spi_pxa2xx_*` stack (temporarily,
      overriding the blacklist for this test only) after the switch.
      **For the first time in this entire investigation, `applespi`
      successfully bound to the SPI device and registered a real input
      device**: `input: Apple SPI Keyboard as
      .../spi_master/spi1/spi-APP000D:00/input/input20`. This did not
      happen at any point on the old install or earlier in the fresh
      install, because `applespi` was blacklisted or backing off via
      `UIST` before this test.
    - However, typing on the keyboard produced **no input**, and dmesg
      showed the same `SPI transfer timed out` / `Error reading from
      device: -110` failure loop seen at the very start of this
      investigation (see step 1) - except this time it's occurring
      after a confirmed-correct mode switch, on a driver that
      successfully bound and whose `_DSM`-provided SPI timing properties
      (`spiCSDelay`, `resetA2RUsec`, `resetRecUsec`) were read without
      any "property not found" warning (confirmed via targeted
      `dynamic_debug` tracing on `applespi.c`, `module applespi +p`) -
      i.e. the timing parameters this Mac's firmware provides are being
      read correctly, and the bus still doesn't work.
    - This reframes the bug: it is not "wrong bus for this model" (that
      was this document's own earlier mistake) and not "missing/wrong
      timing parameters" (confirmed read correctly) - it's that actual
      SPI *data transfers* fail once the bus is correctly switched on,
      for a reason not yet identified. This could be a clock-speed/
      protocol-timing mismatch not exposed via `_DSM`, a chip-select or
      interrupt-line wiring issue, or something else at the electrical
      level that would need lower-level tooling (e.g. a logic analyzer)
      to diagnose further.
    - Reverted the mode back to USB (`UIEN(1)`) and unloaded the test
      modules before ending the session; rebooted to clear the
      intermediate ACPI/GPIO state cleanly via firmware defaults rather
      than trust further manual pokes to restore it.

---

## Current best understanding

Revised as of step 19. This machine's keyboard/trackpad controller is
dual-mode (USB or SPI, switched electrically via ACPI-exposed GPIOs), and
there are now two independent, confirmed-real failure modes, not one:

1. **In USB mode** (the firmware default under Linux): the internal
   xHCI port (`usb1-port5`) never signals a connection to the OS at all
   - confirmed at the lowest level Linux can observe (`portsc`
   power-cycles cleanly, but Connect Status Change never fires; see
   step 15). Nothing tried against this - ACPI `_OSI`, `USBX`/`_DSM`,
   per-port properties, S3 suspend, xHCI unbind/rebind, the Apple
   `set_os` UEFI protocol - has had any effect.
2. **In SPI mode** (reachable by manually calling `SIEN(1)`, which the
   `applespi` driver itself never does on its own when it finds USB
   already active): the driver binds successfully and reads its ACPI-
   provided timing parameters without error, but actual SPI bus
   transfers time out (`-110`) and no keystrokes register - the same
   `SPI transfer timed out` signature seen at the very start of this
   investigation, but now confirmed to occur on a correctly-mode-switched,
   correctly-parameterized SPI bus, not a misconfigured or wrong driver.

Neither mode currently works, and the two failures look independent
rather than the same root cause wearing two faces - fixing #1 would still
leave #2 unexplored, and vice versa. Two live hypotheses remain open:

- **For USB mode:** some firmware-level hardware initialization step for
  this port happens under Apple's own EFI/firmware control (or under
  GRUB/rEFInd, which both run *under* that same firmware) and is never
  replicated by Linux's kernel - either because it has no ACPI-visible
  representation Linux could call, or because of a kernel-side xHCI
  regression specific to this port's exact signaling.
- **For SPI mode:** the bus is genuinely enabled and parameterized
  correctly per ACPI, but data transfers still fail - suggesting a
  clock-speed/protocol-timing mismatch not exposed via the `_DSM`
  properties `applespi` reads, a chip-select/interrupt-line issue, or
  some other electrical-level problem that software-only debugging
  (dynamic debug, ACPI tracing) can't fully diagnose - this would likely
  need a logic analyzer on the actual SPI lines to make further
  progress.

One caveat worth being explicit about: it's not fully settled that
MacBookPro12,1 was ever an intended target for `applespi` at all. The
driver's top-of-file comment names "MacBookPro12" as a model with USB
pins connected, but the original mainline submission's own commit
message (`038b1a05eae6`) names only MacBook8,1-and-later and
MacBookPro13,\*/14,\* as targets - no mention of MacBookPro12,\*. No
issue, PR, or commit across either `cb22/macbook12-spi-driver` or its
most active fork discusses this model by name. So "force SPI mode with a
driver patch" isn't a confirmed fix waiting to be written - it's an
open question for the maintainer, and this machine's firmware defaulting
to USB mode may be entirely intentional on Apple's part, not a bug
Linux needs to work around.

Both are upstream of anything a udev rule, kernel module option, or
driver-selection choice could fix without either new kernel code (most
likely: teaching `applespi` to actively call `SIEN(1)` on this model
instead of backing off when it sees USB active, then separately
debugging the resulting SPI timeout) or physical-layer diagnosis.

---

## Bug report (short form)

**Hardware:** MacBook Pro (Retina, 13-inch, Early 2015),
`MacBookPro12,1`, Intel chipset xHCI controller `8086:9cb1` (Wildcat
Point-LP, PCI `0000:00:14.0`); dual-mode keyboard/trackpad controller
switchable between USB and SPI via ACPI-exposed GPIOs (see below).

**Summary:** Internal keyboard and trackpad do not work under Linux in
either of the two modes this hardware supports:

- **USB mode** (the firmware default under Linux): the internal xHCI
  port (`usb1-port5`, ACPI path `\_SB_.PCI0.XHC1.RHUB.HS05`) shows
  powered (portsc PP=1) but never receives a Connect Status Change (CCS
  stays 0), confirmed via `xhci-hub.c`/`hub.c` dynamic-debug tracing
  while manually power-cycling the port. The sibling hardwired port on
  the same root hub (`usb1-port3`, `HS03`, internal Bluetooth) works
  normally and was confirmed functional at the Bluetooth protocol level
  (not just USB enumeration).
- **SPI mode** (reachable by manually invoking the ACPI `SIEN(1)`
  method via `acpi_call`, since the `applespi` driver does not do this
  automatically when it finds USB active - see below): the mode switch
  succeeds (confirmed via ACPI `UIST`/`SIST` state and a resulting
  change in the USB port's reported state), `applespi` binds to the SPI
  device successfully and registers an input device, and reads its
  ACPI-provided (`_DSM`) SPI timing properties without any
  "property not found" warning - but actual SPI data transfers time out
  (`SPI transfer timed out`, `Error reading from device: -110`) and no
  keystrokes register.

**Confirmed NOT a hardware fault:** keyboard/trackpad both work
correctly in macOS Internet Recovery Mode on the same physical machine.

**On the USB/SPI mode switch itself:** this model's controller is
dual-mode by design - confirmed via the mainline `applespi.c` driver's
own top-of-file comment ("the keyboard and touchpad controller on the
MacBookAir6, MacBookPro12, MacBook8 and newer can be driven either by
USB or SPI... the USB pins are only connected on the MacBookAir6 and 7
and the MacBookPro12") and via this machine's real, decompiled DSDT,
which defines working `UIEN`/`UIST`/`SIEN`/`SIST` ACPI methods under
`\_SB.PCI0.SPI1.SPIT` that toggle real GPIO state
(`GD26`/`GP26`/`GD13`/`GP13`). `applespi_probe()` calls `UIST` and, on
finding USB already active (as it is by default on this machine under
Linux), returns `-ENODEV` immediately without ever calling `SIEN` - it
does not attempt to switch modes itself when USB is already reported as
active.

**Reproduced on:** Arch Linux, two independent installs (kernel
`7.1.5-arch1-2` rolling release on the most recent), both GRUB and
rEFInd as bootloader. Also confirmed on genuine mainline kernel
`7.2.0-rc5` (via the AUR `linux-mainline` package), ruling out an
Arch-specific kernel regression or an already-fixed-upstream issue. The
SPI-mode transfer timeout was reproduced on `7.1.5-arch1-2` (mainline
lacked a buildable `acpi_call` module for this session due to a missing
headers package, not retested there yet).

**Ruled out (USB mode):** `acpi_osi=Darwin` boot parameter; ACPI
`USBX`/`_DSM` (confirmed absent from this machine's real DSDT/SSDT
tables); per-port `_UPC`/`_PLD`/`MUXS` ACPI property differences (none
exist between the working Bluetooth port and the broken keyboard port);
S3 suspend/resume; xHCI PCI-device unbind/rebind; Apple `set_os` UEFI
protocol spoofing via rEFInd's `spoof_osx_version` (tested `10.9`,
`10.12`, `10.15`, and disabled).

**Ruled out (SPI mode):** missing/incorrect `_DSM`-provided SPI timing
parameters (`spiCSDelay`, `resetA2RUsec`, `resetRecUsec` - confirmed read
without error via targeted `dynamic_debug` tracing); incorrect ACPI mode
switch (confirmed `UIST`/`SIST` flip cleanly and the driver successfully
binds and registers an input device post-switch).

**Reproduction steps (USB mode, the default):**
1. Install Linux (any recent kernel) on a MacBookPro12,1 with an
   encrypted (LUKS) root filesystem.
2. Boot. Observe internal keyboard/trackpad work at the firmware
   bootloader menu (GRUB or rEFInd).
3. Reach the LUKS passphrase prompt (early initramfs). Internal
   keyboard/trackpad are unresponsive. They remain unresponsive for the
   rest of the boot and in the fully running OS. An external
   USB keyboard/mouse work normally throughout.

**Reproduction steps (SPI mode, manually forced):**
1. From a running system in USB mode (as above), load `acpi_call` and
   invoke `\_SB.PCI0.SPI1.SPIT.SIEN 1` via `/proc/acpi/call`.
2. Confirm the switch via `\_SB.PCI0.SPI1.SPIT.UIST` (now 0) and
   `\_SB.PCI0.SPI1.SPIT.SIST` (now 1).
3. Load `spi_pxa2xx_pci`, `spi_pxa2xx_platform`, and `applespi`. The
   driver binds and an "Apple SPI Keyboard" input device appears in
   `dmesg`.
4. Type on the internal keyboard. No input registers. `dmesg` shows a
   continuous `SPI transfer timed out` / `Error reading from device:
   -110` loop.

**Requested help:** whether `applespi` is expected to call `SIEN(1)`
itself on models where it finds USB already active (rather than
deferring with `-ENODEV`), and separately, any pointer to what could
cause SPI bus transfers to time out on this specific chipset/model once
the mode switch and timing parameters are already confirmed correct -
e.g. a clock-speed/protocol detail not captured by the `_DSM` properties
`applespi` currently reads, or a chip-select/interrupt-line
configuration issue specific to this board.
