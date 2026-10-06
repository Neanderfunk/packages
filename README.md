# Neanderfunk Packages

This branch targets **Gluon 2025.1.x**. It was branched off `v2023.2.x` on
2026-09-09 and is byte-identical to it at that point; differences appear only
where 2025.1 makes them necessary.

> ## Status: in testing, not in production
>
> **Nodes in the field run Gluon 2023.2 and use `v2023.2.x`.** This branch is
> what the 2025.1 test builds are made from since 2026-09-27, running on test
> nodes only. Most test builds cover four targets (ath79-generic,
> mediatek-filogic, ramips-mt7621, x86-64), one covered all 20.
>
> * **EdgeRouter X, Xiaomi AX6S and Linksys E8450 (UBI) get images, but no
>   autoupdater manifest entry** (compat level 2.0), so none of them updates
>   itself from 2023.2 until their migration is sorted out.
> * **`neanderfunk-erx-migrate` is gone from this branch**: it belongs to the
>   intermediate Gluon 2023.2 image of the EdgeRouter X migration.
> * **`neanderfunk-mt7915-backlog` is gone as well.** Our images replace
>   Gluon's own `patches/openwrt/0012-mt7915-detect-and-purge-stuck-PLE-queues.patch`
>   (a Gluon patch, not part of OpenWrt 24.10) with the six mt7915
>   power-save/AQL patches from Gluon main (#3673), see gluon-patches-hardware
>   `kernel/mt7915-ps-aql` (adb6e5377cff0c198750ab96849febf54a82ff29). Whether
>   these, together with the mt7915 recovery fixes and mt76 `e5fef138`
>   (inactivity polling) in 2025.1, keep the backlog pattern away is derived,
>   not measured; the field evaluation is open. The package still exists on
>   `v2023.2.x`.
> * Points that can only be settled on running hardware are listed in
>   `docs/2025.1-regressionstest.md` ("Was der Prüfer NICHT abdeckt").

For the previous branch, see `v2023.2.x`.

How Gluon's `gluon-reconfigure` works, and what upgrade scripts in this feed
rely on: [docs/gluon-reconfigure.md](docs/gluon-reconfigure.md).

Which devices in the field drive their LAN ports via DSA and which via swconfig,
and whether Gluon 2025.1 changes that:
[docs/feldgeraete-dsa-swconfig.md](docs/feldgeraete-dsa-swconfig.md).

## Using this feed

Add the feed to your site's `modules` file (next to `site.conf`):

```
GLUON_SITE_FEEDS="neanderfunk"
PACKAGES_NEANDERFUNK_REPO=https://github.com/Neanderfunk/packages.git
PACKAGES_NEANDERFUNK_BRANCH=v2023.2.x
PACKAGES_NEANDERFUNK_COMMIT=<commit>
```

Replace `<commit>` with a commit of the `v2023.2.x` branch (Gluon 2023.2;
for a Gluon 2025.1 test build use `v2025.1.x` in both lines). If your site
already uses other feeds, append `neanderfunk` to the existing
`GLUON_SITE_FEEDS` instead of replacing it - in particular do not reuse the
name `community`, that is the feed of freifunk-gluon/community-packages. Then
add the packages you want to `site.mk` or `image-customization.lua`.

Several packages are forks of a community or ffac package and declare
`CONFLICTS` with the original; take the original out of your package list.
`neanderfunk-config-mode-theme` replaces Gluon's theme, so the site has to
drop it with `'-gluon-config-mode-theme'`. Which site.conf keys a package
reads, and whether it needs any, is in its own README.

How Gluon's `gluon-reconfigure` works, and what upgrade scripts in this feed
rely on: [docs/gluon-reconfigure.md](docs/gluon-reconfigure.md).

Which devices in the field drive their LAN ports via DSA and which via swconfig,
and whether Gluon 2025.1 changes that:
[docs/feldgeraete-dsa-swconfig.md](docs/feldgeraete-dsa-swconfig.md).

Flash and RAM of the devices in the field, grouped by how soon a Gluon
release may drop them: [docs/feldgeraete-flash-ram.md](docs/feldgeraete-flash-ram.md).

Calling `sysupgrade` from a script: exec it and do nothing afterwards. It
returns as soon as it has handed over to procd, seconds before stage2 reads
the image, so any cleanup after it breaks the upgrade:
[docs/sysupgrade-aus-skripten.md](docs/sysupgrade-aus-skripten.md).

### neanderfunk-config-mode-theme ###

replaces gluon-config-mode-theme: config mode layout and stylesheet,
responsive down to phone width, dark mode following the browser, Freifunk
colours, system fonts only. Covers every page of the config mode. The site
has to drop Gluon's theme (`'-gluon-config-mode-theme'`). See
[](neanderfunk-config-mode-theme/README.md).

### neanderfunk-setup-mode ###

the whole config mode on one page: the wizard on top, every form of
"Advanced settings" below as a collapsed group, one "Save & restart". All
forms valid or nothing is written, only changed forms are written, the wizard
last. The forms stay Gluon's and the packages' own. Needs
neanderfunk-config-mode-theme. See [](neanderfunk-setup-mode/README.md).

### neanderfunk-respondd ###

respondd module in C that adds `neanderfunk` to nodeinfo (CPU model, flash
size, BIOS, preserve_channels) and statistics (live channel, HT mode, SSID,
tx power per radio; offline-SSID counters; link, speed, duplex and a
damaged-cable hint per ethernet port) - the values the status page shows on
top of Gluon's respondd. See [](neanderfunk-respondd/README.md).

### neanderfunk-wifi-blackout ###

detects a wifi blackout - the radios are up, but not a single station is
associated anywhere on the node, neither client nor mesh peer, and none has been
for hours - and restarts the wifi, rebooting if that does not help. It is the
only check here without the "arm once the healthy state was seen" rule, which is
what makes it the one that catches a radio broken from the moment it came up.
Not restricted to any chipset. Was `neanderfunk-ath9kblackout`; see
[](neanderfunk-wifi-blackout/README.md) for why the name and three defects had
to go.

### neanderfunk-button-bind

lets the node owner bind the router's wifi button to a function (wifi on/off,
nothing, wifi reset, or a night mode that keeps the LEDs dark) from config mode.
Ported from ffffm-button-bind, see [](neanderfunk-button-bind/README.md)

### neanderfunk-hotfix

Local health of the node itself - everything that is wrong on this box rather
than out in the network. Looks for
- kernel/malloc issues on the way down to a freeze
- a frozen wifi driver, dfs-scan panics
- hostapd with non-matching pid files, rendered dysfunctional
- an AP whose clients have all been gone for a long time
- an illogical number of tunneldigger instances
- br-client without an address from the site's own (ULA) prefix
- respondd or dropbear not running
- a deadman watchdog for micrond itself
Every check can be switched off individually and the reboot hold-off after a
boot is configurable. See [](neanderfunk-hotfix/README.md).
Questions about the network around the node - missing gateway, anycast,
neighbours, bridge ports - live in neanderfunk-linkcheck instead.

### neanderfunk-migrate-updatebranch ###

moving upgradebranch from experimental to stable systematically
and removing l2tp from branches

### neanderfunk-banner

Banner file replacement, Some nice messages on login and more aliases set.

### neanderfunk-linkcheck

Everything about the network around the node: an interface that had 2 or more
neighbours and has lost all of them, a batman interface or a bridge that has
disappeared, a port that dropped out of its bridge, no batman gateway in range,
and the IPv6 anycast address gone unreachable. Escalates from a wifi restart to
a reboot; each check is individually switchable.
See [](neanderfunk-linkcheck/README.md)

### neanderfunk-port-roles

One role per network port instead of per port group: Gluon's multi-port
interface sections (all LAN ports in `gluon.iface_lan`) are split into one
section per port, on DSA switches and separate network interfaces. Plus a
choice how LAN ports with the mesh role are joined - bridged, isolated, or one
bridge and batman-adv interface per port for switches that cannot isolate in
hardware (`auto` picks), and tagged VLANs per port with their own roles. "Ports"
page in the config mode. DSA ports and separate NICs only, not swconfig. Gluon
2025.1 only. See [](neanderfunk-port-roles/README.md)

### neanderfunk-preserve-wifichannel

Makes `wifi24.preserve_channels` from the site.conf the default for Gluon's uci
option `gluon.wireless.preserve_channels` - Gluon itself never read the site
key. Sets it where it is missing (on fresh installs once the config mode wizard
is done), leaves an existing 0 or 1 alone, and applies the site's channels once
after a site or domain switch, the 5 GHz channels once after an outdoor switch.
See [](neanderfunk-preserve-wifichannel/README.md)

### neanderfunk-ssid-changer

Changes the SSID to an Offline-SSID so clients don't connect to an offline WiFi,
configurable in config mode. See [](neanderfunk-ssid-changer/README.md)

### neanderfunk-txpowerfix

Sets a regulatory country (DE/JP/TW/US) matching the configured channels and
the widest HT mode per radio. No longer pins txpower and removes existing pins
once per node (keep them with `gluon.wireless.preserve_txpower=1`). Config only, no wifi
restart. See [](neanderfunk-txpowerfix/README.md)


### neanderfunk-weeklyreboot

weekly reboot sheduled on thursday morning. See [](neanderfunk-weeklyreboot/README.md)


### neanderfunk-node-whisperer ###

kodiert Statusinformationen in die Beacons der Client-WLANs, auslesbar mit der
App NodeMonitor. Fork von `ffda-node-whisperer` mit zwei lokalen Korrekturen:
eine fehlende Domain wird auf Single-Domain-Firmware nicht mehr alle 30 Sekunden
als Fehler ins Syslog geschrieben, und das Byte, das die App als "Gateway"
anzeigt, traegt jetzt den TQ des tatsaechlich gewaehlten Batman-Gateways statt
des TQ eines mesh-vpn-Nachbarn - ein Knoten, der ueber WLAN oder LAN mesht,
galt sonst als "Gateway nicht erreichbar". Drahtformat und App bleiben
unveraendert. Upstream ist gepinnt, unsere Aenderungen liegen als Patches
daneben; siehe [](neanderfunk-node-whisperer/README.md) samt Backport-Anleitung.

### neanderfunk-nodeplacer ###

moves individual nodes to another domain of the same community, controlled by a
signed manifest on the community's firmware servers (same signing tools and keys
as the autoupdater manifest). A node that finds its own node id listed either
switches domain locally (multi-domain firmware) or installs the target domain's
firmware through the regular autoupdater. Documentation in
neanderfunk-nodeplacer/docs/; development happens in
https://github.com/Adorfer/neanderfunk-nodeplacer-dev, the directory here is
generated and must not be edited.
