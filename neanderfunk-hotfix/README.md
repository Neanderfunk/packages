# neanderfunk-hotfix

Micrond jobs that detect and work around conditions a node otherwise would not
recover from on its own. Everything here is about the health of *this box*.
Questions about the network around it - is there still a batman gateway, are
the mesh neighbours gone, did an interface drop out of its bridge - belong to
neanderfunk-linkcheck and are deliberately not duplicated here.

### Safety checks

Before any check may act:

- an autoupdater run in progress (`/tmp/autoupdate.lock`): exit. A lock older
  than 60 minutes is a hung autoupdater and gets a reboot of its own
  (`stale_lock`).
- uptime below `hotfix.settings.reboot_uptime_min` (default 60 minutes): exit.
  A node must have a chance to come up and find its neighbours before anything
  reboots it again.

### What it looks at

- batman-adv deadly-wounded situations (ksoftirqd / memory allocation errors)
- atheros driver deadly-wounded situations (memory allocation errors)
- too many l2tp tunneldigger instances (restarting without reaping the old
  ones, otherwise hours of slow death)
- hostapd processes whose pid files no longer match, rendering them useless
- hostapd failing its DFS check
- an AP that had wifi clients and then lost all of them for a long time
- br-client without an address from the site's own (ULA) `prefix6` - the node
  is meshing, but cannot show its status page or fetch updates
- respondd or dropbear gone: something very strange happened to the system
- micrond itself dying, caught by a deadman watchdog (see below)

Manual installation
===================

If you don't have this package in your firmware, you can still install it
manually on a node:

```
ROUTER_IP='your:node::ip6'
LOGIN="root@[$ROUTER_IP]"
git clone https://github.com/Neanderfunk/packages/ -b v2023.2.x
cd neanderfunk-hotfix/
scp -r files/* $LOGIN:/
ssh $ROUTER_IP "/etc/init.d/micrond reload;"
```


Configuration
=============

Every single check can be switched off per node, and the reboot hold-off after
a boot is adjustable. Both are UCI settings, and both can be preset for the
whole community from the `site.conf`.

Switching a check off on one node:

```
uci set hotfix.<check>.disabled='1'
uci commit hotfix
```

`uci show hotfix` lists the available check names. The name is also part of the
reason logged before a wifi restart or a reboot, e.g.

```
neanderfunk-healthcheck: [load] ...
```

so if you watch a node over SSH with `logread -f` and see it reboot, the syslog
line tells you directly which key to set if you consider that check a false
positive on your node.

Reboot hold-off after a boot (minutes, default 60 when unset). No check may
reboot the node before this:

```
uci set hotfix.settings.reboot_uptime_min='90'
uci commit hotfix
```

site.conf
---------

Both can be preset community-wide. `/lib/gluon/upgrade/500-neanderfunk-hotfix`
seeds them on every `gluon-reconfigure`, but never overwrites a value already
set on the node - so a local `uci set` always wins over the site default:

```lua
  hotfix = {
    reboot_uptime_min = 60,                 -- optional, minutes, default 60
    disabled_checks = { 'load', 'tunneldigger' },  -- optional
  },
```

Checks
------

| check | what it does | reaction |
| --- | --- | --- |
| `stale_lock` | autoupdate.lock older than 60 min | reboot |
| `kernel_bug` | "Kernel bug" in dmesg (gluon issue #680) | reboot |
| `ath_malloc` | ath driver allocation failures in dmesg | reboot |
| `ksoftirqd_malloc` | kernel page allocation failures in dmesg | reboot |
| `hostapd_pids` | hostapd pid files not matching the running processes | wifi restart |
| `dfs_failcheck` | hostapd failing its DFS check | wifi restart |
| `tunneldigger` | too many tunneldigger watchdogs/instances | reboot |
| `br_client_ipv6` | br-client without an address from the site prefix | reboot |
| `load` | 5 minute load average above 2 | reboot |
| `respondd` | respondd not running | reboot |
| `dropbear` | dropbear not running | reboot |
| `no_wifi_clients` | clients were seen and then all disappeared | wifi restart |
| `watchdog` | deadman switch for micrond itself, see below | reboot |

Watchdog (micrond deadman switch)
---------------------------------

Every other check here runs from micrond. If micrond itself dies - crash, OOM
kill, or stopped and never restarted - nothing on the node would ever notice or
reboot it again. `watchdog.sh` closes that hole:

micrond starts it every `watchdog_interval_min` minutes (default 5). Each new
instance relieves its predecessor by killing it. An instance that is *not*
relieved within 3x that interval concludes there is no micrond starting jobs any
more, and reboots.

The value is clamped to the period micrond actually uses, which the script reads
out of its own cron entry in `/usr/lib/micron.d/hotfix`. Setting it *lower* than
that would create a deadline no relief could ever meet, and the watchdog would
reboot a perfectly healthy node every few minutes; raising it is honoured.

Everything after its sleep is deliberately fork-free, because the situation it
exists for includes running out of memory, where starting `logger`, `date` or
`/sbin/reboot` may simply fail: `echo`, `read` and `kill` are ash builtins, the
reason goes to `/dev/kmsg` (which still shows up in `logread`) and the reboot
goes through `/proc/sysrq-trigger` - `s` to sync, `b` to reboot immediately.
`/sbin/reboot -f` is only a fallback for kernels without sysrq.

The autoupdater legitimately stops micrond while it downloads and flashes, and
that must not be mistaken for a dead micrond. Three hooks installed by this
package leave markers behind:

| hook | marker | meaning |
| --- | --- | --- |
| `download.d/20neanderfunk-hotfix` | `/tmp/hotfix.autoupdater-running` (uptime at start) | an update is running |
| `upgrade.d/20neanderfunk-hotfix` | `/tmp/hotfix.autoupdater-flashing` | sysupgrade is about to write the flash |
| `abort.d/20neanderfunk-hotfix` | removes both | the update was aborted |

While `autoupdater-flashing` exists the watchdog **never** reboots - interrupting
a flash write bricks the node. While an update is merely running it reboots only
once that run exceeds `autoupdater_stale_min` minutes (default 300), on the
assumption that the updater is then stuck rather than working.

```
uci set hotfix.settings.watchdog_interval_min='5'
uci set hotfix.settings.autoupdater_stale_min='300'
uci commit hotfix
```
