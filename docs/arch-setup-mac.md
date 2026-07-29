# Arch Linux Manual Installation Command Summary

Companion to the
[learnlinux.tv 2026 Arch install guide](https://www.learnlinux.tv/arch-linux-installation-guide-2026-update/),
adjusted for this Mac's hardware (LUKS + Btrfs instead of LVM + ext4, no
GNOME/display packages, Mac-specific input driver notes). Revisit this
top-to-bottom on every fresh install rather than relying on memory - it's
infrequent enough to forget the order.

## Pre-Installation (in the live ISO)

Confirm you booted in UEFI mode - if this directory is empty, the later
GRUB EFI install will fail or silently do the wrong thing.

```bash
ls /sys/firmware/efi/efivars
```

Connect to wifi (skip if on Ethernet - check with `ip addr show` first).

```bash
iwctl
```

```bash
station wlan0 scan
```

```bash
station wlan0 get-networks
```

```bash
station wlan0 connect <SSID>
```

```bash
exit
```

If `iwctl` shows no `wlan0` device at all, or `rfkill list` shows the
wifi soft-blocked, that's a driver/firmware issue, not a config issue -
diagnose before continuing rather than fighting `iwctl`.

```bash
rfkill list
```

Verify the connection.

```bash
ping -c 3 archlinux.org
```

Sync the system clock - matters for TLS/package signature checks during
`pacstrap`.

```bash
timedatectl set-ntp true
```

---

## Partitioning and Filesystem Preparation

View current partitions - confirm the device name (`/dev/sda` on this Mac
under the archiso; NVMe disks would be `/dev/nvme0n1` instead).

```bash
lsblk
```

Create the GPT partition layout with an EFI partition and encrypted Linux
partition.

```bash
cfdisk /dev/sda
```

- Create a new `1G` partition and set the type to EFI System
- Create a partition for remaining space that is Linux filesystem
- Then write the partitions and quit the program

Format the EFI System Partition as FAT32.

```bash
mkfs.fat -F32 /dev/sda1
```

Create the LUKS encryption container on the Linux partition.

```bash
cryptsetup luksFormat /dev/sda2
```

Open the encrypted partition as cryptroot.

```bash
cryptsetup open /dev/sda2 cryptroot
```

Format the unlocked container as Btrfs.

```bash
mkfs.btrfs /dev/mapper/cryptroot
```

---

## Btrfs Subvolume Creation

Separate subvolumes let you snapshot `@` (root) without dragging `@home`,
`@var` (noisy log/cache churn), or `@snapshots` itself into every snapshot.

Mount the Btrfs filesystem temporarily to create subvolumes.

```bash
mount /dev/mapper/cryptroot /mnt
```

Create the root subvolume.

```bash
btrfs subvolume create /mnt/@
```

Create the home subvolume.

```bash
btrfs subvolume create /mnt/@home
```

Create the variable data subvolume.

```bash
btrfs subvolume create /mnt/@var
```

Create the log subvolume.

```bash
btrfs subvolume create /mnt/@log
```

Create the snapshots subvolume.

```bash
btrfs subvolume create /mnt/@snapshots
```

Unmount the temporary Btrfs mount.

```bash
umount /mnt
```

---

## Mounting the Installation Targets

Mount the root Btrfs subvolume.

```bash
mount -o subvol=@,compress=zstd,noatime /dev/mapper/cryptroot /mnt
```

`compress=zstd` enables transparent Btrfs compression (good default -
cheap CPU cost, meaningful space savings). `noatime` skips updating a
file's last-read timestamp on every access, which avoids extra writes on
every read - safe unless something you rely on reads that timestamp
(most tools use mtime, not atime).

Create mount points for additional filesystems.

```bash
mkdir -p /mnt/{boot,home,var,.snapshots}
```

Mount the home subvolume.

```bash
mount -o subvol=@home,compress=zstd,noatime /dev/mapper/cryptroot /mnt/home
```

Mount the var subvolume.

```bash
mount -o subvol=@var,compress=zstd,noatime /dev/mapper/cryptroot /mnt/var
```

Mount the log subvolume (needs its own explicit mount - the `mkdir -p`
above only created the empty directory, not a mount point).

```bash
mkdir /mnt/var/log
mount -o subvol=@log,compress=zstd,noatime /dev/mapper/cryptroot /mnt/var/log
```

Mount the snapshots subvolume.

```bash
mount -o subvol=@snapshots,compress=zstd,noatime /dev/mapper/cryptroot /mnt/.snapshots
```

Mount the EFI partition directly as /boot.

```bash
mount /dev/sda1 /mnt/boot
```

Verify all mounted filesystems before proceeding - catch a missed mount
now, not after `pacstrap` has already written files into the wrong place.

```bash
findmnt -R /mnt
```

---

## Installing the Base System

Install the Arch base system and essential packages. `openssh` is
included so you can immediately reach the machine remotely after first
boot, before any desktop environment or further config exists.

```bash
pacstrap -K /mnt base linux linux-headers linux-firmware btrfs-progs networkmanager openssh sudo vim git intel-ucode cryptsetup grub efibootmgr bluez bluez-utils acpid
```

| Package | Purpose |
|---|---|
| base | Minimal set of packages needed for a functional Arch system (coreutils, bash, systemd, pacman, etc). |
| linux | The Linux kernel (rolling release, tracks upstream closely). |
| linux-headers | Kernel headers, needed to build external kernel modules (DKMS packages, etc). |
| linux-firmware | Firmware blobs for hardware devices, including this Mac's Broadcom wifi chip. |
| btrfs-progs | Userspace tools to create and manage Btrfs filesystems and subvolumes. |
| networkmanager | Manages wired and wireless network connections after installation (includes wpa_supplicant as a dependency). |
| openssh | SSH client and server - the server lets you reach the machine remotely right after first boot. |
| sudo | Grants the primary user elevated privileges without logging in as root. |
| vim | Text editor, used throughout this guide to edit config files. |
| git | Version control, needed for cloning dotfiles/config repos post-install. |
| intel-ucode | Microcode updates for this Mac's Intel CPU, loaded early by the bootloader. |
| cryptsetup | Userspace tools to create and unlock the LUKS encrypted partition. |
| grub | Bootloader used to boot the encrypted, Btrfs-subvolumed system. |
| efibootmgr | Manages UEFI boot entries, used by grub-install. |
| bluez, bluez-utils | Bluetooth protocol stack and CLI utilities. |
| acpid | Handles ACPI events (lid close, power button, etc) on this laptop. |

Generate the filesystem table.

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Enter the installed system environment.

```bash
arch-chroot /mnt
```

---

## System Configuration

Refresh the package signing keyring first, before anything else in this
section - `archlinux-keyring` ships as a `base` dependency, but the
version baked into `pacstrap` can be stale enough that installing an
older/archived package later (e.g. a downgrade from
archive.archlinux.org) fails with `invalid or corrupted package (PGP
signature)` even though the download itself is fine.

```bash
pacman -Sy archlinux-keyring
```

Set the timezone. List valid `<Region>/<City>` values with
`ls /usr/share/zoneinfo/` (regions) and `ls /usr/share/zoneinfo/<Region>`
(cities) - e.g. `America/New_York` or `Europe/London`. If unsure, cross-check
against `timedatectl list-timezones`.

```bash
ln -sf /usr/share/zoneinfo/<Region>/<City> /etc/localtime
```

Sync the hardware clock to it.

```bash
hwclock --systohc
```

Uncomment your locale (e.g. `en_US.UTF-8 UTF-8`) then generate it -
skipping this leaves the system in the bare `C` locale.

```bash
vim /etc/locale.gen
```

```bash
locale-gen
```

Persist the chosen locale.

```bash
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

Set the hostname.

```bash
echo "<hostname>" > /etc/hostname
```

Add the matching entry so the hostname resolves locally.

```bash
echo "127.0.1.1 <hostname>.localdomain <hostname>" >> /etc/hosts
```

Set the root password.

```bash
passwd
```

Create the primary user account.

```bash
useradd -m -g users -G wheel <username>
```

`wheel` dates back to 1970s TOPS-20/BSD Unix, where only users in this
group could `su` to root at all - the name reputedly comes from "big
wheel," 70s slang for someone important. Today on Arch (and most
distros) it has no special kernel/system meaning by itself - it's just a
conventional group name that `visudo`'s default `%wheel ALL=(ALL:ALL)
ALL` rule (uncommented below) grants sudo access to. Adding a user to
`wheel` is what actually matters; the group's old absolute-gatekeeping
role is now just convention carried forward.

Set the user password.

```bash
passwd <username>
```

Edit sudo permissions - uncomment `%wheel ALL=(ALL:ALL) ALL`.

```bash
EDITOR=vim visudo
```

Enable networking at boot.

```bash
systemctl enable NetworkManager
```

Enable SSH so you can reach the machine remotely after reboot.

```bash
systemctl enable sshd
```

Enable time synchronization.

```bash
systemctl enable systemd-timesyncd
```

---

## Initramfs Configuration

Edit mkinitcpio configuration.

```bash
vim /etc/mkinitcpio.conf
```

Configure systemd-based LUKS unlocking by setting the hooks.

```bash
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

Rebuild initramfs images.

```bash
mkinitcpio -P
```

---

## GRUB Bootloader Configuration

Get the LUKS partition's UUID - do not reuse a UUID from a previous
install, it's regenerated by every `luksFormat`.

```bash
blkid -s UUID -o value /dev/sda2
```

Edit GRUB kernel parameters.

```bash
vim /etc/default/grub
```

Add the LUKS and Btrfs root parameters to `GRUB_CMDLINE_LINUX` (not
`GRUB_CMDLINE_LINUX_DEFAULT`), using the UUID from above.

>`GRUB_CMDLINE_LINUX_DEFAULT` only applies to the normal boot entry -
>`GRUB_CMDLINE_LINUX` applies to every generated entry, including recovery
>mode. These parameters unlock and locate the root filesystem, so every
>entry needs them or recovery mode won't boot.

```bash
rd.luks.name=<UUID>=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
```

Install GRUB for UEFI with the EFI partition mounted at /boot.

```bash
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub_uefi --recheck
```

Also install to the removable/fallback EFI path
(`EFI/Boot/BOOTX64.EFI`) with `--removable`. Apple firmware doesn't always reliably retain
NVRAM boot entries added by `grub-install`/`efibootmgr` across reboots or
firmware updates - the fallback path is picked up by the firmware even if
the NVRAM entry gets dropped.

```bash
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub_uefi --recheck --removable
```

Generate the GRUB configuration file.

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Final Hardware Packages

Bluetooth and ACPI (`bluez`, `bluez-utils`, `acpid`) were already
installed by `pacstrap` above - this just enables them now that services
can be managed inside the chroot.

Enable Bluetooth support.

```bash
systemctl enable bluetooth
```

Enable laptop ACPI event handling.

```bash
systemctl enable acpid
```

ACPI events are hardware/firmware signals for things like closing the
lid, pressing the power/sleep buttons, or a thermal trip point being hit
- the kernel receives them, but `acpid` is the userspace daemon that lets
you actually react to them (e.g. suspend on lid-close, run a script on
power-button-press) via `/etc/acpi/events/` rules. Most desktop
environments now handle these directly through `systemd-logind` /
`UPower` without needing `acpid` at all - it mainly matters here for a
bare setup with no DE, or for custom handling logind doesn't cover.

---

## Keyboard and Trackpad Drivers (model-specific - check before installing)

Confirm whether this Mac's internal keyboard/trackpad are wired via the SPI
bus or plain internal USB before installing any input driver - installing
the wrong one causes a silent conflict, not just a no-op.

```bash
cat /sys/class/dmi/id/product_name
```

MacBook8,1/9,1 (12" 2015) and Touch Bar-era MacBook Pros (2016+) wire the
keyboard/trackpad over SPI and need the third-party `applespi` driver
(DKMS package `macbook12-spi-driver`, plus `spi_pxa2xx_platform` and
`spi_pxa2xx_pci`/`intel_lpss_pci` loaded early in
`mkinitcpio.conf`'s `MODULES=(...)`).

MacBookPro11,x and MacBookPro12,1 (2015 13"/15" Pro, no Touch Bar) wire the
keyboard/trackpad as a plain internal USB HID device instead - no extra
driver needed, and none should be installed manually. However, `applespi`
is now mainlined and auto-loads on a completely stock kernel with zero
manual config, because this Mac's ACPI tables expose a phantom SPI
controller (`spi-APP000D:00`) that matches `applespi`'s hardware ID even
though the keyboard isn't actually wired to it. Confirmed via `lsmod`/
`journalctl` on a fresh install in mid-2026: `applespi`,
`spi_pxa2xx_platform`, `spi_pxa2xx_pci`, and `spi_pxa2xx_core` all loaded
automatically, with no timeout spam in the log (unlike the older DKMS
driver, which spun in a tight `SPI transfer timed out` /
`Error reading from device: -110` loop and starved the real USB port).
Check for this after a fresh install regardless of whether you installed
anything SPI-related yourself:

```bash
journalctl -k -b | grep -E 'applespi|SPI transfer timed out|unable to enumerate'
```

```bash
lsmod | grep -E 'applespi|spi_pxa2xx'
```

If any of those modules are loaded, blacklist them so they can't attach to
the phantom SPI device, then rebuild the initramfs:

```bash
echo -e "blacklist applespi\nblacklist spi_pxa2xx_platform\nblacklist spi_pxa2xx_pci" > /etc/modprobe.d/blacklist-applespi.conf
```

```bash
mkinitcpio -P
```

Leave `spi_intel`/`spi_intel_platform` alone if you see them too - those
belong to the unrelated onboard SPI-NOR flash chip, not the keyboard.

If keyboard/trackpad still don't work after blacklisting and a reboot,
that's a deeper kernel/USB bring-up issue, not a driver issue - confirmed
on MacBookPro12,1 in mid-2026: it works in Internet Recovery Mode and at
the GRUB menu, but the internal xHCI port never enumerates the device once
Linux's kernel takes over. Cross-check against a recent, model-exact
community install guide (e.g. search GitHub for `<model>` install guides)
before assuming a fix exists - this may just be a live upstream kernel bug
with no known workaround yet.

---

## Leaving the Installer

Exit the chroot environment.

```bash
exit
```

Unmount all installed filesystems.

```bash
umount -R /mnt
```

Reboot into the new Arch installation.

```bash
reboot
```

---

## Connecting to Wifi (after reboot)

NetworkManager is enabled and running now (from the System Configuration
step above), so this replaces `iwctl` - `iwctl` only exists on the live
ISO's `iwd`-based setup, not on the installed system.

List available networks.

```bash
nmcli device wifi list
```

Connect, using the SSID from the list above.

```bash
nmcli device wifi connect <SSID> --ask
```

`--ask` prompts for the password interactively instead of putting it on
the command line (and in shell history). Verify the connection.

```bash
ping -c 3 archlinux.org
```

If `nmcli device wifi list` shows no networks, prefer the interactive
`nmtui` menu over troubleshooting `nmcli` flags directly - it's easier to
read the connection state and retry from.

```bash
nmtui
```

If the connection associates (`nmcli device status` briefly shows
`config`/`need-auth`) but then repeatedly disconnects and retries before
eventually failing with "Insufficient privileges" or a 90s timeout -
even with the correct password - this is a known `brcmfmac` issue on this
Mac's Broadcom BCM43602 chip: the card's power-management mode causes it
to drop out and miss the AP's WPA handshake frames. Check
`journalctl -u NetworkManager --since "10 min ago"` for a repeating
`associated -> disconnected` / "association took too long" pattern to
confirm this before assuming the password is wrong. Disable wifi
powersave to fix it.

```bash
printf "[connection]\nwifi.powersave = 2\n" | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
```

```bash
sudo systemctl restart NetworkManager
```

Then retry the `nmcli device wifi connect` command above.

If that still doesn't fix it and `journalctl -u NetworkManager` /
`journalctl -u wpa_supplicant` shows a clean association followed by
`Authentication ... timed out` and `CTRL-EVENT-DISCONNECTED ...
reason=3 locally_generated=1`, repeating - this is a known regression in
`wpa_supplicant` 2.11 affecting Broadcom wifi (`brcmfmac`/`wl` drivers),
not specific to this Mac. Confirmed via the Arch Linux bug thread
(bbs.archlinux.org/viewtopic.php?id=298025) with the identical log
signature.

Downgrading to `wpa_supplicant` 2:2.10-8 (the thread's workaround) is a
dead end on a fresh install - that build's signing key
(`heftig@archlinux.org`, fingerprint
`06687A1D9D4FAB08B50FD92B3B94A80E50A477C7`) has since been disabled in
Arch's keyring (confirmed via `pacman-key --finger`), and pacman
deliberately refuses disabled keys regardless of local signing - don't
work around this with `--no-verify`. Switch NetworkManager to the `iwd`
backend instead, which sidesteps `wpa_supplicant` entirely and is
confirmed working on this Mac's Broadcom BCM43602 chip.

```bash
sudo pacman -S iwd
```

```bash
sudo mkdir -p /etc/NetworkManager/conf.d
printf "[device]\nwifi.backend=iwd\n" | sudo tee /etc/NetworkManager/conf.d/wifi-backend.conf
```

```bash
sudo systemctl enable --now iwd
```

```bash
sudo systemctl restart NetworkManager
```

Then retry the `nmcli device wifi connect` command again. `wpa_supplicant`
itself can stay installed (NetworkManager just won't use it for wifi
anymore) or be removed if nothing else on the system depends on it.

```bash
sudo pacman -R wpa_supplicant
```

Once the machine has network access (wifi above, or Ethernet), copy your
local machine's SSH key over so future logins don't need a password. Run
this from your local machine, not on the Arch box - `ssh-copy-id` is a
client-side tool.

```bash
ssh-copy-id <user>@<arch-ip>
```

---

## Pairing Bluetooth Devices (after reboot)

Bluetooth is enabled and running now (from the Final Hardware Packages
step above). `bluetoothctl` works either as a one-shot command per
action, or as an interactive shell - most keyboards/mice need the
interactive form because pairing requires displaying or exchanging a
passkey, which the one-shot form can't show you.

### Without the agent (works for simple devices, no passkey prompt)

Scan for nearby devices - `--timeout` stops the scan automatically
instead of needing a separate `scan off`.

```bash
bluetoothctl --timeout 15 scan on
```

List what was found, and note the target device's MAC address
(`XX:XX:XX:XX:XX:XX`).

```bash
bluetoothctl devices
```

Pair, trust, and connect.

```bash
bluetoothctl pair <MAC>
```

```bash
bluetoothctl trust <MAC>
```

```bash
bluetoothctl connect <MAC>
```

If `pair` fails with `org.bluez.Error.AuthenticationFailed` - common for
keyboards, which need a passkey typed on the device itself rather than a
plain tap-to-pair - use the interactive form with the agent enabled
instead.

### With the agent (needed for passkey-based devices like keyboards)

Enter the interactive shell.

```bash
bluetoothctl
```

Inside that shell (prompt changes to `[bluetooth]#`), enable the pairing
agent and make it the default - this is what lets a passkey prompt
appear instead of pairing silently failing.

```
agent on
default-agent
```

Pair, using the MAC address from `devices` above.

```
pair <MAC>
```

Watch for a passkey displayed on screen (type it on the target device
and press Enter there), or a yes/no confirmation prompt (answer `yes`
here in the terminal).

Once paired, still inside the same interactive shell:

```
trust <MAC>
connect <MAC>
```

Exit the interactive shell when done.

```
exit
```

Verify the connection - look for `Connected: yes`.

```bash
bluetoothctl info <MAC>
```
