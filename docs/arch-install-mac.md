# Arch Linux Manual Installation Command Summary

## Partitioning and Filesystem Preparation

Create the GPT partition layout with an EFI partition and encrypted Linux partition.
`cfdisk /dev/sda`

Format the EFI System Partition as FAT32.
`mkfs.fat -F32 /dev/sda1`

Create the LUKS encryption container on the Linux partition.
`cryptsetup luksFormat /dev/sda2`

Open the encrypted partition as cryptroot.
`cryptsetup open /dev/sda2 cryptroot`

Format the unlocked container as Btrfs.
`mkfs.btrfs /dev/mapper/cryptroot`

---

## Btrfs Subvolume Creation

Mount the Btrfs filesystem temporarily to create subvolumes.
`mount /dev/mapper/cryptroot /mnt`

Create the root subvolume.
`btrfs subvolume create /mnt/@`

Create the home subvolume.
`btrfs subvolume create /mnt/@home`

Create the variable data subvolume.
`btrfs subvolume create /mnt/@var`

Create the log subvolume.
`btrfs subvolume create /mnt/@log`

Create the snapshots subvolume.
`btrfs subvolume create /mnt/@snapshots`

Unmount the temporary Btrfs mount.
`umount /mnt`

---

## Mounting the Installation Targets

Mount the root Btrfs subvolume.
`mount -o subvol=@,compress=zstd,noatime /dev/mapper/cryptroot /mnt`

Create mount points for additional filesystems.
`mkdir -p /mnt/{efi,home,var/log,.snapshots}`

Mount the home subvolume.
`mount -o subvol=@home,compress=zstd,noatime /dev/mapper/cryptroot /mnt/home`

Mount the var subvolume.
`mount -o subvol=@var,compress=zstd,noatime /dev/mapper/cryptroot /mnt/var`

Create the log mount point after discovering it was missing.
`mkdir -p /mnt/var/log`

Mount the log subvolume.
`mount -o subvol=@log,compress=zstd,noatime /dev/mapper/cryptroot /mnt/var/log`

Mount the snapshots subvolume.
`mount -o subvol=@snapshots,compress=zstd,noatime /dev/mapper/cryptroot /mnt/.snapshots`

Mount the EFI partition directly as /boot.
`mkdir -p /mnt/boot`
`mount /dev/sda1 /mnt/boot`

Verify all mounted filesystems.
`findmnt -R /mnt`

---

## Installing the Base System

Install the Arch base system and essential packages.
`pacstrap -K /mnt base linux linux-headers linux-firmware btrfs-progs networkmanager sudo vim git intel-ucode cryptsetup grub efibootmgr bluez bluez-utils acpid`

Generate the filesystem table.
`genfstab -U /mnt >> /mnt/etc/fstab`

Enter the installed system environment.
`arch-chroot /mnt`

---

## System Configuration

Set the root password.
`passwd`

Create the primary user account.
`useradd -m -g users -G wheel <username>`

Set the user password.
`passwd <username>`

Edit sudo permissions.
`EDITOR=vim visudo`

Enable networking at boot.
`systemctl enable NetworkManager`

Enable time synchronization.
`systemctl enable systemd-timesyncd`

---

## Initramfs Configuration

Edit mkinitcpio configuration.
`nano /etc/mkinitcpio.conf`

Configure systemd-based LUKS unlocking by setting the hooks.
`HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)`

Rebuild initramfs images.
`mkinitcpio -P`

---

## GRUB Bootloader Configuration

Edit GRUB kernel parameters.
`nano /etc/default/grub`

Add the LUKS and Btrfs root parameters.
`rd.luks.name=d7256491-26d6-4be4-9aa3-cb387d6edeca=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw`

Install GRUB for UEFI with the EFI partition mounted at /boot.
`grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub_uefi --recheck`

Generate the GRUB configuration file.
`grub-mkconfig -o /boot/grub/grub.cfg`

---

## Final Hardware Packages

Install Bluetooth and laptop event support.
`pacman -S bluez bluez-utils acpid`

Enable Bluetooth support.
`systemctl enable bluetooth`

Enable laptop ACPI event handling.
`systemctl enable acpid`

---

## Keyboard and Trackpad Drivers (model-specific - check before installing)

Confirm whether this Mac's internal keyboard/trackpad are wired via the SPI
bus or plain internal USB before installing any input driver - installing
the wrong one causes a silent conflict, not just a no-op.
`cat /sys/class/dmi/id/product_name`

MacBook8,1/9,1 (12" 2015) and Touch Bar-era MacBook Pros (2016+) wire the
keyboard/trackpad over SPI and need the third-party `applespi` driver
(DKMS package `macbook12-spi-driver`, plus `spi_pxa2xx_platform` and
`spi_pxa2xx_pci`/`intel_lpss_pci` loaded early in
`mkinitcpio.conf`'s `MODULES=(...)`).

MacBookPro11,x and MacBookPro12,1 (2015 13"/15" Pro, no Touch Bar) wire the
keyboard/trackpad as a plain internal USB HID device instead - no extra
driver needed. Installing `applespi`/`spi_pxa2xx_platform`/`spi_pxa2xx_pci`
on these models anyway makes `applespi` attach to a phantom ACPI SPI
device that times out continuously (`SPI transfer timed out` /
`Error reading from device: -110` in a tight loop), which in turn power-
cycles and starves the real internal USB port so the keyboard/trackpad
never enumerate. If keyboard/trackpad don't work after install, check for
this failure mode before assuming a missing driver, and remove the SPI
modules/DKMS package if it's the wrong generation of hardware.
`journalctl -k -b | grep -E 'applespi|SPI transfer timed out|unable to enumerate'`

---

## Leaving the Installer

Exit the chroot environment.
`exit`

Unmount all installed filesystems.
`umount -R /mnt`

Reboot into the new Arch installation.
`reboot`

