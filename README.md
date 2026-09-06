# Neanderfunk Packages

This branch works for gluon 2023.2.x.

### neanderfunk-ath9kblackout ###

looks for dying ath9-wifichips and reintializes wifi (in a reliable way even for DFS-aware gluon)

### neanderfunk-button-bind

lets the node owner bind the router's wifi button to a function (wifi on/off,
nothing, wifi reset, or a night mode that keeps the LEDs dark) from config mode.
Ported from ffffm-button-bind, see [](neanderfunk-button-bind/README.md)

### neanderfunk-ch13to9 ###

moves radios from ch13 to 9 during firmwareupdate, even if "keep-wifichannels" is set. 
This is done for compatblity issues with certain android(tm) devices, refusing to work on ch13 in EU region. 

### neanderfunk-hotfix

Hotfix-collection-VFN: Reboot if no Wifi clients or if no Gateway connection, 
looking for 
- disappeared batman-gw (failing batman transglobal tables) 
- disappeared:ac1/64 anycast (failing iv6<>batman binding)
- divers kernel/malloc issues if device is on the way down to freeze
- frozen wifi driver 
- ap with disappeared clients for long time
- dfs-scan pannics 
- hostapd with non matching pid-files, rendered disfunctional
- illogical high number of tunneldigger clients active at the same time

### neanderfunk-migrate-updatebranch ###

moving upgradebranch from experimental to stable systematically
and removing l2tp from branches

### neanderfunk-banner

Banner file replacement, Some nice messages on login and more aliases set.

### neanderfunk-linkcheck

WIFI-Neighborcheck. check if interfaces with previously 2 and more neighbors have lost all neigbors for longer, see [](neanderfunk-linkcheck/README.md)

### neanderfunk-ssid-changer

Changes the SSID to an Offline-SSID so clients don't connect to an offline WiFi,
configurable in config mode. See [](neanderfunk-ssid-changer/README.md)

### neanderfunk-txpowerfix

Fixes txpower on some wifi nodes since OpenWrt chaos calmer by setting the 
country code to 00/BO so it can be set to higher values than the incorrectly
configured german code allows. See [](neanderfunk-txpowerfix/README.md)


### neanderfunk-weeklyreboot

weekly reboot sheduled on thursday morning. See [](neanderfunk-weeklyreboot/README.md)

### neanderfunk-wificheck

WIFI-Neighborcheck. restarts wifi no wifi mesh neighbours are seen after
initially there were at lease two neighbours. See [](neanderfunk-wificheck/README.md)

### neanderfunk-mt7915-backlog ###

restarts wifi if the mt7915e driver shows the known backlog-fill failure
symptom, see [](neanderfunk-mt7915-backlog/README.md)

### neanderfunk-nodeplacer ###

moves individual nodes to another domain of the same community, controlled by a
signed manifest on the community's firmware servers (same signing tools and keys
as the autoupdater manifest). A node that finds its own node id listed either
switches domain locally (multi-domain firmware) or installs the target domain's
firmware through the regular autoupdater. Documentation in
neanderfunk-nodeplacer/docs/; development happens in
https://github.com/Adorfer/neanderfunk-nodeplacer-dev, the directory here is
generated and must not be edited.
