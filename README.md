# Eulenfunk Packages

This branch works for gluon 2020.1.x.

Branch `v2021.1.x` (Neanderfunk, since 2026-10-04): based on `v2020.1.x`
`cd24c70` (what the 2021.1 "sackgasse" build pins), plus
`neanderfunk-legacy-migrate` for pulling 2015.1/2016.x nodes onto 2021.1.

### eulenfunk-ch13to9 ###

moves radios from ch13 to 9 during firmwareupdate, even if "keep-wifichannels" is set. 
This is done for compatblity issues with certain android(tm) devices, refusing to work on ch13 in EU region. 

### eulenfunk-hotfix

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

### eulenfunk-migrate-upgradebranch ###

moving upgradebranch from experimental to stable systematically
and removing l2tp from branches

### neanderfunk-banner

Core of neanderfunk-banner from v2025.1.x for 19.07/swconfig: nodestatus
overview at login, nodeinfo, switch0/switchstatus, reconf, v4up, vpn,
routername, kontakt, help. See neanderfunk-banner/README.md.

### gluon-linkcheck

WIFI-Neighborcheck. check if interfaces with previously 2 and more neighbors have lost all neigbors for longer, see [](gluon-linkcheck/README.md)

### gluon-ssid-changer

Changes the SSID to an Offline-SSID so clients don't connect to an offline WiFi.

This is a direct copy of https://github.com/Freifunk-Nord/gluon-ssid-changer 
branch 2018.1.x 

### gluon-txpowerfix

Fixes txpower on some wifi nodes since OpenWrt chaos calmer by setting the 
country code to 00/BO so it can be set to higher values than the incorrectly
configured german code allows. See [](gluon-txpowerfix/README.md)


### gluon-weeklyreboot

weekly reboot sheduled on thursday morning. See [](gluon-weeklyreboot/README.md)

### gluon-wificheck

WIFI-Neighborcheck. restarts wifi no wifi mesh neighbours are seen after
initially there were at lease two neighbours. See [](gluon-wificheck/README.md)

### neanderfunk-legacy-migrate

Migrates configs of old Gluon versions (2015.1 to 2020.x) on the jump to 2021.1.
See neanderfunk-legacy-migrate/README.md.
