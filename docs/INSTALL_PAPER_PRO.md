# Install Paper Pro Reader 0.6.0-rc5

This release candidate uses KOReader's native `remarkable-aarch64` `tar.xz`
archive and the current manual Paper Pro AppLoad path. Physical validation is
pending; keep the rollback copy until RC5 Write Mode is physically qualified.

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

Do not install Toltec or the old rm2fb/systemd launcher for Paper Pro RC5.
The authoritative upstream procedure is the
[KOReader reMarkable installation wiki](https://github.com/koreader/koreader/wiki/Installation-on-reMarkable#manual-installation-on-remarkable-paper-pro-move--pure).

## Download and verify

From the successful **paper-pro-release-candidate** workflow run, download both
artifacts:

```text
paper-pro-reader-remarkable-aarch64-<full-commit-sha>
paper-pro-reader-remarkable-aarch64-<full-commit-sha>-metadata
```

The first is the directly installable native `tar.xz`. The metadata artifact
contains its `.sha256`, release manifest, and contents listing. Extract the
metadata download beside the `tar.xz`, then on macOS/Linux run:

```sh
shasum -a 256 -c paper-pro-reader-remarkable-aarch64-0.6.0-rc5-*.tar.xz.sha256
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
ssh root@<PAPER_PRO_IP> 'cd /home/root/xovi/exthome/appload && tar -cJf /home/root/paper-pro-reader-before-rc5.tar.xz koreader'
scp root@<PAPER_PRO_IP>:/home/root/paper-pro-reader-before-rc5.tar.xz .
```

This includes settings, sidecars stored inside KOReader, dictionaries,
vocabulary, ink, AI queue/history, and diagnostics. Back up books separately
using the normal reMarkable workflow.

## First installation

```sh
scp paper-pro-reader-remarkable-aarch64-0.6.0-rc5-*.tar.xz root@<PAPER_PRO_IP>:/home/root/
ssh root@<PAPER_PRO_IP>
cd /home/root
tar -xJf paper-pro-reader-remarkable-aarch64-0.6.0-rc5-*.tar.xz
mkdir -p /home/root/xovi/exthome/appload
mv /home/root/koreader /home/root/xovi/exthome/appload/
exit
```

Open the reMarkable sidebar, choose **AppLoad**, then **KOReader**.

## Exit safely

In KOReader, swipe down from the top, open the top-right menu, choose **Exit**,
then confirm **Exit**. AppLoad returns to the normal reMarkable interface.

## Upgrade RC4 to RC5

Return to the stock UI with `/home/root/xovi/stock`, then back up the installed
RC4 directory before changing it:

```sh
ssh root@<PAPER_PRO_IP> 'cd /home/root/xovi/exthome/appload && tar -cJf /home/root/paper-pro-reader-rc4-before-rc5.tar.xz koreader'
scp root@<PAPER_PRO_IP>:/home/root/paper-pro-reader-rc4-before-rc5.tar.xz .
scp paper-pro-reader-remarkable-aarch64-0.6.0-rc5-*.tar.xz root@<PAPER_PRO_IP>:/home/root/
ssh root@<PAPER_PRO_IP>
cd /home/root/xovi/exthome/appload
tar -xJf /home/root/paper-pro-reader-remarkable-aarch64-0.6.0-rc5-*.tar.xz
exit
```

This replaces packaged files without deleting `settings.reader.lua`,
`settings/`, `data/dict/`, document sidecars, or the `paperpro-*.json` stores.
Do not rebuild Xovi merely for this application upgrade; the first RC5 retest
must keep the same working launcher environment so the code change is isolated.

## Xovi ReferenceError note

The non-fatal ReferenceError reported during RC1 is tracked separately from
the product input fix. A similar AppLoad error on OS 3.27 was attributed by the
AppLoad maintainer to an old `qt-resource-rebuilder` and resolved after updating
that extension. If the error recurs or AppLoad cannot launch RC5, record its
exact text and installed Xovi/AppLoad/qt-resource-rebuilder versions before
changing them. Then update `qt-resource-rebuilder` through its project-supported
installer, rebuild the Xovi hashtable, and retry. Do not change the launcher
stack before the first RC5 Write Mode test when RC5 launches normally.

## Roll back

Exit the app, then:

```sh
ssh root@<PAPER_PRO_IP>
cd /home/root/xovi/exthome/appload
mv koreader koreader-rc5-failed
cd /home/root
tar -xJf paper-pro-reader-rc4-before-rc5.tar.xz -C /home/root/xovi/exthome/appload
exit
```

Keep `koreader-rc5-failed` until the restored build launches and data is
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
