neanderfunk-mt7915-backlog
=============  
ported from ffac-mt7915-backlog

source: https://github.com/ffac/gluon-packages/blob/ffac-mt7915-backlog/ffac-mt7915-backlog/files/lib/gluon/mt7915/restart-wifi-if-backlog-filled.sh
(© 2024 Felix Baumann, Florian Maurer, FFAC - MIT, see LICENSE)

This package restarts wifi if an mt7915 radio's txq backlog grows past 50
packets. It's meant as a hotfix for the mcu timeout issue:
https://github.com/freifunk-gluon/gluon/issues/3154

Differences to the original
---------------------------

* **Only mt7915 radios are looked at.** The build gate is by target
  (`ramips_mt7621`, `mediatek_filogic`, `mediatek_mt7622`) plus `kmod-mt7915e`,
  but an mt7621 board need not carry an mt7915 radio: a Xiaomi Mi Router 4A
  Gigabit is `ramips/mt7621` with `mt7603e` and `mt76x2e`, and the original
  polled those too. Each phy's driver is read from
  `/sys/class/ieee80211/phyN/device/driver` instead.
* **A cool-down between restarts** (default 30 minutes). The original restarted
  wifi on every run that saw a high backlog, so a backlog that did not clear
  meant a restart every two minutes, each one throwing the clients off.
* **The backlog value is validated** before it is compared, so an absent or
  multi-line reading is skipped rather than turning into a shell error.
* **Two uptime thresholds**, as in neanderfunk-hotfix and -linkcheck: below
  `check_uptime_min` (5 min) nothing runs, below `reboot_uptime_min` (60 min) a
  high backlog is reported but wifi is not restarted.

Configuration
-------------

```
uci set mt7915backlog.settings.disabled='1'      # switch the check off
uci set mt7915backlog.settings.threshold='80'    # packets, default 50
uci set mt7915backlog.settings.cooldown_min='60' # default 30
uci commit mt7915backlog
```

The log tag is `neanderfunk-mt7915-backlog`, so `logread -f | grep backlog`
shows what it decided and why.

Create a file `modules` with the following content in your `./gluon/site/`
directory and add these lines: 

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_COMMUNITY_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_COMMUNITY_COMMIT=*/missing/*
PACKAGES_COMMUNITY_BRANCH=v2023.2.x
```

Now you can add the package `neanderfunk-mt7915-backlog` to your site.mk
(`*/missing/*` has to be replaced by the github-commit-ID of the version you
want to use, you have to pick it manually.)

Further info on the issue this tries to prevent from happening:
When the backlog queue fill up, the device does not respond over wlan reliably.
Sometimes, the backlog is cleared after a few minutes,
but in busy environments this takes far too long and gets the system into an unresponsive state.
Pings are not responend, traffic is stalled.

I experienced these issues on various Zyxel NWA 55 AXE as well as on an Acer Vero W6M in busy environments.
This happens on 5GHz as well as on 2.4GHz ifaces, depending on where the higher load is.
Other devices with mt7915 like COVR-X1860 and DAP-X1860 are not affected on openwrt-24.10

Also see https://github.com/openwrt/mt76/issues/1009
