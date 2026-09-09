# Neanderfunk Packages

This branch targets **Gluon 2025.1.x**. It was branched off `v2023.2.x` on
2026-09-09 and is byte-identical to it at that point; differences appear only
where 2025.1 makes them necessary.

> ## Limited scope, roughly until 2026-11: wireless-less devices only
>
> **Only the EdgeRouter X — a device without radios — is in scope for now.**
> The point of this branch is getting the ERX through the automatic migration to
> 2025.1; everything else comes later.
>
> What that means in practice:
>
> * **The wired paths are the ones that matter here**: batman interfaces,
>   bridges and their ports, gateway and IPv6 anycast, the deadman watchdog,
>   load, respondd, dropbear, the autoupdater guards.
> * **The wireless paths are untested on 2025.1.** They are known to bail out
>   cleanly on a node without radios — measured on a wifi-less node: ssid-changer,
>   wifi-blackout, check_wifi_firmware and IfNoWificlient all return within
>   0.00 s, write no log line and leave no marker. That is enough for the ERX and
>   is *not* a statement about nodes that do have radios.
> * **Do not roll this branch out to nodes with radios** until the open points in
>   `docs/2025.1-regressionstest.md` have been checked on real hardware —
>   above all the radio naming and whether `rf_regval` still exists under mt76
>   in OpenWrt 24.10. (`mt7915-backlog` is gone from this branch — see below.)
>
> **Removed on this branch:** `neanderfunk-mt7915-backlog`. OpenWrt 24.10 as
> shipped with Gluon 2025.1 carries an in-driver fix for stuck mt7915 PLE queues
> (`patches/openwrt/0012-mt7915-detect-and-purge-stuck-PLE-queues.patch`), which
> is what that package worked around. It still exists on `v2023.2.x`.
>
> For nodes in production, `v2023.2.x` remains the branch to use.

For the previous branch, see `v2023.2.x`.

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

### neanderfunk-ch13to9 ###

moves radios from ch13 to 9 during firmwareupdate, even if "keep-wifichannels" is set. 
This is done for compatblity issues with certain android(tm) devices, refusing to work on ch13 in EU region. 

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

### neanderfunk-ssid-changer

Changes the SSID to an Offline-SSID so clients don't connect to an offline WiFi,
configurable in config mode. See [](neanderfunk-ssid-changer/README.md)

### neanderfunk-txpowerfix

Fixes txpower on some wifi nodes since OpenWrt chaos calmer by setting the 
country code to 00/BO so it can be set to higher values than the incorrectly
configured german code allows. See [](neanderfunk-txpowerfix/README.md)


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
