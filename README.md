# Neanderfunk Packages

This branch works for gluon 2023.2.x.

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

### neanderfunk-ssid-changer

Changes the SSID to an Offline-SSID so clients don't connect to an offline WiFi,
configurable in config mode. See [](neanderfunk-ssid-changer/README.md)

### neanderfunk-txpowerfix

Sets a regulatory country (DE/JP/TW/US) matching the configured channels and
the widest HT mode per radio. No longer pins txpower and removes existing pins
(keep them with `gluon.wireless.preserve_txpower=1`). Config only, no wifi
restart. See [](neanderfunk-txpowerfix/README.md)


### neanderfunk-weeklyreboot

weekly reboot sheduled on thursday morning. See [](neanderfunk-weeklyreboot/README.md)

### neanderfunk-mt7915-backlog ###

restarts wifi if an mt7915 radio's txq backlog fills up, the known mcu-timeout
symptom. Looks at the driver of each radio rather than trusting the build
target, so an mt7621 board with different wifi is left alone, and holds a
cool-down so a backlog that does not clear cannot restart wifi every two
minutes. See [](neanderfunk-mt7915-backlog/README.md)

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
