# Install Paper Pro Reader 0.6.0-rc1

This release candidate uses KOReader's native `remarkable-aarch64` `tar.xz`
archive and the current manual Paper Pro AppLoad path. Physical validation is
pending; keep the rollback copy until RC1 is qualified.

## Prerequisites

The current upstream Paper Pro manual method requires:

1. reMarkable developer/SSH access and the root password shown on-device.
2. [Xovi](https://github.com/asivery/rm-xovi), installed with its included
   installer for your firmware.
3. `qt-resource-rebuilder` from the Xovi repository.
4. [rm-appload](https://github.com/asivery/rm-appload).
5. `qtfb-shim.so` and `qtfb-shim-32bit.so` placed in `/home/root/shims/` as
   directed by rm-appload/Xovi.
6. Xovi's hashtable rebuilt with `xovi/rebuild_hashtable`, and Xovi started
   with `xovi/start` after each reboot unless its project-supported service is
   configured.

Do not install Toltec or the old rm2fb/systemd launcher for Paper Pro RC1.
The authoritative upstream procedure is the
[KOReader reMarkable installation wiki](https://github.com/koreader/koreader/wiki/Installation-on-reMarkable#manual-installation-on-remarkable-paper-pro-move--pure).

## Download and verify

Download the GitHub Actions artifact named:

```text
paper-pro-reader-remarkable-aarch64-<full-commit-sha>
```

It contains the native `tar.xz`, `.sha256`, release manifest, and contents
listing. On macOS/Linux, in the download directory:

```sh
shasum -a 256 -c paper-pro-reader-remarkable-aarch64-0.6.0-rc1-*.tar.xz.sha256
```

The result must say `OK` and match the checksum in the Stage A handoff.

## Find the device address

Use the Paper Pro address shown in Settings > About > GPLv3 compliance, or the
USB-network address if configured. Replace `<PAPER_PRO_IP>` below. Test access:

```sh
ssh root@<PAPER_PRO_IP>
```

## Back up an existing installation

Exit Paper Pro Reader first. If `/home/root/xovi/exthome/appload/koreader`
exists:

```sh
ssh root@<PAPER_PRO_IP> 'cd /home/root/xovi/exthome/appload && tar -cJf /home/root/paper-pro-reader-before-rc1.tar.xz koreader'
scp root@<PAPER_PRO_IP>:/home/root/paper-pro-reader-before-rc1.tar.xz .
```

This includes settings, sidecars stored inside KOReader, dictionaries,
vocabulary, ink, AI queue/history, and diagnostics. Back up books separately
using the normal reMarkable workflow.

## First installation

```sh
scp paper-pro-reader-remarkable-aarch64-0.6.0-rc1-*.tar.xz root@<PAPER_PRO_IP>:/home/root/
ssh root@<PAPER_PRO_IP>
cd /home/root
tar -xJf paper-pro-reader-remarkable-aarch64-0.6.0-rc1-*.tar.xz
mkdir -p /home/root/xovi/exthome/appload
mv /home/root/koreader /home/root/xovi/exthome/appload/
exit
```

Open the reMarkable sidebar, choose **AppLoad**, then **KOReader**.

## Exit safely

In KOReader, swipe down from the top, open the top-right menu, choose **Exit**,
then confirm **Exit**. AppLoad returns to the normal reMarkable interface.

## Upgrade to another RC

Exit the app and make a fresh backup. Then extract the new native archive from
the AppLoad parent directory so packaged files are replaced while unbundled
user data remains:

```sh
scp paper-pro-reader-remarkable-aarch64-<next-rc>-*.tar.xz root@<PAPER_PRO_IP>:/home/root/
ssh root@<PAPER_PRO_IP>
cd /home/root/xovi/exthome/appload
tar -xJf /home/root/paper-pro-reader-remarkable-aarch64-<next-rc>-*.tar.xz
exit
```

Do not delete `settings.reader.lua`, `settings/`, `data/dict/`, document
sidecars, or the `paperpro-*.json` stores.

## Roll back

Exit the app, then:

```sh
ssh root@<PAPER_PRO_IP>
cd /home/root/xovi/exthome/appload
mv koreader koreader-rc-failed
cd /home/root
tar -xJf paper-pro-reader-before-rc1.tar.xz -C /home/root/xovi/exthome/appload
exit
```

Keep `koreader-rc-failed` until the restored build launches and data is
confirmed. This is recoverable and avoids immediate deletion.

## Uninstall

Exit the app and remove it from AppLoad without deleting it immediately:

```sh
ssh root@<PAPER_PRO_IP>
mv /home/root/xovi/exthome/appload/koreader /home/root/paper-pro-reader-uninstalled
exit
```

Confirm the stock UI and other AppLoad applications work. Delete the moved
directory later only after deciding its local data is no longer needed. Xovi,
rm-appload, and QTFB are shared prerequisites; remove them only with their own
project instructions, not as part of Paper Pro Reader uninstall.
