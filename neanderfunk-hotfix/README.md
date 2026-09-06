# neanderfunk-hotfix

This package will add a cronjob that fixes some problems that rarely occur, but are easy to work around. 

### Safety checks:
To be sure, that the script is not disturbing the start and update process:
- if autoupdater is running, `exit`
- if the router started less than 5 minutes ago, `exit`

### Workarounds
- check if we have lost any neighbours, `iw dev $DEV scan`
- if dropbear is not running, reboot (probably ram was full, so more services might've crashed)
- reboot if there was a kernel (batman) error

### Healthcheck
- (don't do anything the first 50 minutes after router is started, uptimecheck)
- batman-adv eadly wounded situation (ksoftirqd/mem alloc error) -> reboot
- atherosdriver deadly wounded situations (mem alloc errors) -> reboot
- too many l2tp tunneldigger instances running (3+, means: restarting without killing old zombies, otherwiese hours of slow death)
- br-client interface not initialized with any valid IPv6 (router is just meshing, but will not be able so show statuspage or get updates)
- respondd died or dropbear not running: If this happens, something very strange happended to the system. -> reboot
- iw on wifi hangs (does not terminate, this is a servere atheros bug) -> detect and reboot.
- iw scan with lowpri, to force the wifi to wake up (just in case of strange powermanagement behavoir)
- check for radio neigbors and report them to log, to have some stats in the logread, in case no map with history/grafana etc in reach

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
    disabled_checks = { 'load', 'ipv6_anycast' },  -- optional
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
| `bridge_ports` | a port that was part of a bridge dropped out of it | reboot |
| `mesh_neighbours` | a mesh radio that had >=2 neighbours now has none | scan, wifi restart, reboot |
| `no_gateway` | no batman gateway in range | reboot |
| `ipv6_anycast` | the IPv6 anycast address is unreachable | reboot |
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
| `download.d/20neanderfunk-hotfix` | `/tmp/autoupdater-running` (uptime at start) | an update is running |
| `upgrade.d/20neanderfunk-hotfix` | `/tmp/autoupdater-flashing` | sysupgrade is about to write the flash |
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
