# neanderfunk-hotfix

Micrond jobs that detect and work around conditions a node otherwise would not
recover from on its own. Everything here is about the health of *this box*.
Questions about the network around it - is there still a batman gateway, are
the mesh neighbours gone, did an interface drop out of its bridge - belong to
neanderfunk-linkcheck and are deliberately not duplicated here.

### Safety checks

Before any check may act:

- an autoupdater run in progress: exit. Detected from the markers this package's
  own `/usr/lib/autoupdater/*.d` hooks leave behind, plus the lock the
  autoupdater really holds (`/var/lock/autoupdater.lock`, kept across the
  sysupgrade) and the `autoupdater`/`sysupgrade` processes. A hung run is
  handled by the watchdog's `autoupdater_stale_min`, not by a check of its own.

- uptime below `hotfix.settings.reboot_uptime_min` (default 60 minutes): exit.
  A node must have a chance to come up and find its neighbours before anything
  reboots it again.

### What it looks at

- batman-adv deadly-wounded situations (ksoftirqd / memory allocation errors)
- atheros driver deadly-wounded situations (memory allocation errors)
- too many l2tp tunneldigger instances (restarting without reaping the old
  ones, otherwise hours of slow death)
- AP interfaces the running hostapd does not actually serve
- hostapd failing its DFS check
- an AP that had wifi clients and then lost all of them for a long time
- br-client without an address from the site's own (ULA) `prefix6` - the node
  is meshing, but cannot show its status page or fetch updates
- respondd or dropbear gone: something very strange happened to the system
- ethernet TX hung after a transmit timeout (mtk_soc_eth: filogic, MT7621,
  MT7622, mt76x8, mt7620; by default only logged)
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

`uci show hotfix` lists the available check names. They are created by
`/lib/gluon/upgrade/500-neanderfunk-hotfix`, not shipped in
`/etc/config/hotfix`: that file is a conffile and survives the sysupgrade, so a
section added to it would never reach a node that already exists, and one
removed from it would never disappear there. Measured in the field on
`26090710bro`: nodes still carried `stale_lock` and had no `wifi_firmware`, and
`uci set hotfix.wifi_firmware.disabled='1'` failed with rc=1 because uci will
not set an option in a section that is not there - the documented off switch for
the newest check did not work. The list of checks therefore lives in the upgrade
script and nowhere else.

The name is also part of the reason logged before a wifi restart or a reboot,
e.g.

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
    check_uptime_min  = 5,                  -- optional, minutes, default 5
    reboot_uptime_min = 60,                 -- optional, minutes, default 60
    eth_tx_stall_dry_run = 0,               -- optional, let eth_tx_stall reboot (default: only log)
    load_per_cpu = 2,                       -- optional, load threshold per core (integer, default 2)
    disabled_checks = { 'load', 'tunneldigger' },  -- optional
  },
```

Two uptime thresholds
---------------------

They do different jobs and are set separately:

| below | what happens |
| --- | --- |
| `check_uptime_min` (default 5 min) | nothing runs at all. Right after a boot the network is usually still coming up, and "no gateway" or "anycast not answering" then is not a fault - reporting it would only cause needless alarm. |
| `reboot_uptime_min` (default 60 min) | the checks run and **report what they find**, but take no action: no reboot, no wifi restart, no network reinit. The log line says so explicitly, naming the key that withheld it. |
| above both | normal operation. |

Strikes keep counting while action is withheld, so a problem that is still
there when the node passes `reboot_uptime_min` is acted on straight away rather
than starting its count over.

Checks that do not wait
-----------------------

`reboot_uptime_min` withholds action for everything except `kernel_bug` and the
`watchdog`, on evidence rather than taste:

* **`kernel_bug`** - "Kernel bug detected" is a `BUG()`/oops.
  [gluon#680](https://github.com/freifunk-gluon/gluon/issues/680) reports that
  afterwards *"any invocation of ip, ifconfig, brctl, batctl etc will result in
  a stuck system"*: no self-recovery, and no remedy short of a reboot. On top of
  that, the other checks here shell out to exactly those tools, so a node in
  this state may not even manage to report anything. Waiting an hour buys
  nothing and costs an hour of a dead node.
* **`watchdog`** - a deadman switch with an hour of grace is not a deadman
  switch. It never used the hold-off.

The others keep it deliberately:

* **`ath_malloc`, `ksoftirqd_malloc`** - can be a transient OOM *while booting*
  on small devices; the OpenWrt forum on `ath: skbuff alloc of size ... failed`
  notes it "could be OOM during peak mem consumption while booting, but it may
  look ok later on". Acting at once would reboot-loop a 32 MiB node at every
  boot. Both also recur - the Freifunk forum reports page allocation failures
  every 5 to 10 seconds - so nothing is lost by waiting, and the node limps
  rather than dying outright.
* **`load`** - right after a boot the load is legitimately high, and the 15
  minute average is not meaningful before the node has been up a while.

`load` reads the 15 minute average (field 3 of `/proc/loadavg`) and compares
it with `hotfix.load.per_cpu` (default 2) times the cores, counted fork-free
from `/sys/devices/system/cpu/online`. A reboot needs two healthcheck runs in a
row above that. Until 14.09.2026 it was a fixed "above 2" regardless of the
cores, on the first hit, and the message spoke of the 5 minute average: that
rebooted a dual-core MT7981 (Schulstr7 AP01) in a load test with nine wget
loops and uhttpd - legitimate user-space load, 1 minute load 1.5-3.1.
Single-core devices keep the threshold 2, now with the confirmation. Per node:

```
uci set hotfix.load.per_cpu='3'
uci commit hotfix
```

Changeable per node in either direction:

```
uci set hotfix.load.immediate='1'        # act at once
uci set hotfix.kernel_bug.immediate='0'  # make it wait like the rest
uci commit hotfix
```

Below `check_uptime_min` nothing runs at all, not even the immediate checks.

Checks
------

| check | what it does | reaction |
| --- | --- | --- |
| `kernel_bug` | "Kernel bug" in dmesg (gluon issue #680) | reboot |
| `ath_malloc` | ath driver allocation failures in dmesg | reboot |
| `ksoftirqd_malloc` | kernel page allocation failures in dmesg | reboot |
| `hostapd_pids` | AP interfaces the running hostapd does not serve, see below | wifi restart |
| `dfs_failcheck` | hostapd failing its DFS check | wifi restart |
| `tunneldigger` | too many tunneldigger watchdogs/instances | reboot |
| `br_client_ipv6` | br-client without an address from the site prefix | reboot |
| `load` | 15 minute load average above `hotfix.load.per_cpu` x cores (default 2 x cores) in two runs in a row (~7 min) | reboot |
| `respondd` | respondd not running | reboot |
| `dropbear` | dropbear not running | reboot |
| `no_wifi_clients` | clients were seen and then all disappeared | wifi restart |
| `wifi_firmware` | mt76 wifi firmware crashed, see below | reboot |
| `ath10k_rxhang` | ath10k rx ring corrupted, or a firmware restart loop, 5 GHz stuck | reboot |
| `eth_tx_stall` | ethernet TX hung after a transmit timeout, see below | reboot, by default only logged |
| `logremote` | remote syslog socket with a stale or no source address, see below | restart of the logread instance |
| `watchdog` | deadman switch for micrond itself, see below | reboot |

hostapd not serving an AP interface (`hostapd_pids`)
----------------------------------------------------

`check_hostapd.sh` takes every `wifi-iface` section with `mode='ap'` that is not
disabled, and asks three questions per interface:

1. does the running hostapd know this BSS at all - `ubus call hostapd.<ifname>
   get_status` must answer, and answer `ENABLED`;
2. is its radio stuck in "down and pending" (`wifi status`);
3. is the interface in Master mode but without a channel (`iwinfo`).

Three consecutive failures of any of them restart wifi. `ACS`, `HT_SCAN`, `DFS`
and `COUNTRY_UPDATE` are transient states and count as neither pass nor fail, so
a DFS measurement - which may take ten minutes - can never accumulate strikes.

An interface is skipped entirely, before any of the three questions, when there
is nothing to serve:

| situation | what happens |
| --- | --- |
| the node has no wifi at all | `uci show wireless` fails, the loop body never runs. Measured on an EdgeRouter X: 0.06 s, no markers, no log line |
| the `wifi-iface` section is `disabled` | skipped - this is how Gluon switches a client or mesh interface off |
| the `wifi-device` is `disabled` | skipped |
| netifd reports the radio as `disabled` | skipped |
| netifd does not know the radio at all | skipped |

The last three matter: a radio that is off has no BSS, so question 1 would call
that a fault and restart wifi every 30 minutes - which does not bring a disabled
radio back. A radio netifd knows nothing about is not a hostapd problem either;
`bsses` and `mesh_neighbours` in neanderfunk-linkcheck are the checks for that.

The distinction is deliberately not "does the BSS exist" but "does the BSS exist
*although its radio is up*". Verified on a node against a fabricated config: an
AP interface pointing at an unknown radio stays silent, an AP interface on the
running radio whose BSS hostapd does not know strikes and restarts.

The name is historical and the check used to do something else entirely: it read
`-B` (config file, and from it the phy) and `-P` (pid file) off each hostapd
command line and compared the pid file against the running process. That has
been dead since OpenWrt 21.02, which replaced the per-phy hostapd processes with
a single global one:

```
/usr/sbin/hostapd -s -g /var/run/hostapd/global
```

It has no `-B` and no `-P`, so the `ps | grep hostapd | grep .pid` that fed the
script found nothing - measured on a node running `26090710bro`: zero matches.
The script was never called, and neither were questions 2 and 3 above. The uci
key keeps the name `hostapd_pids` on purpose: renaming it would silently
re-enable the check on any node where somebody had set
`hotfix.hostapd_pids.disabled='1'`.

The check deliberately does **not** use `/var/run/hostapd/<ifname>` as its
signal. On all three nodes examined, that directory holds only the second
radio's socket plus `global` - `client0` has no socket there while its ubus
object answers perfectly well.

A wifi restart from this check has a cool-down, 30 minutes by default. Without
it, a section whose radio never comes up at all - broken hardware, a phy that
fails to probe - would restart wifi roughly three times an hour forever, each
time throwing the clients off both radios without fixing anything.

```
uci set hotfix.settings.hostapd_cooldown_min='60'
uci commit hotfix
```

Crashed wifi firmware (`wifi_firmware`)
---------------------------------------

`/sys/kernel/debug/ieee80211/phy*/mt76/rf_regval` is a register window into the
running wifi firmware. While that firmware lives, reading it yields a value;
once it has crashed the file is still there but the read fails. "Present but
unreadable" is therefore a fairly direct crash detector, and there is no remedy
short of a reboot - the firmware is loaded when the module probes, so
`wifi down; wifi up` does not reload it.

Runs on its own `*/3` schedule rather than inside `healthcheck.sh` (`*/7`),
because a node whose wifi firmware is dead is deaf to clients and waiting out
two 7 minute periods would cost a quarter of an hour.

Ported from `ffac-mt7915-hotfix` in community-packages, which this replaces.
What changed:

* The original expanded `phy*` **twice**, independently - once in `ls`, once in
  `cat`. On a device where one phy has the file and another does not, the `ls`
  succeeds while the `cat` fails, and the node reboots over a file that was
  never there. Here every phy is looked at on its own.
* Uptime thresholds. The original had none, so it could reboot two minutes into
  a boot while the firmware was still coming up.
* Two consecutive failed reads before acting, so one bad read is not enough.
* A working autoupdater guard (see below).
* Switchable per node like every other check.

Deliberately **not** immediate: on a node that has been up for days - the normal
case - the reboot follows about six minutes after the firmware dies. Only inside
the first hour after a boot is it held back, and that is exactly where a
genuinely broken chip would otherwise reboot-loop every few minutes. Held back,
the worst case is one reboot per hour, with the finding in the log throughout.
`uci set hotfix.wifi_firmware.immediate='1'` overrides that per node.

Despite the original's name this is not mt7915-specific - the debugfs path is
mt76-generic. On chips that do not export `rf_regval` (a Xiaomi 4A Gigabit with
`mt7603e`/`mt76x2e`) nothing matches and the check does nothing. Worth knowing,
because on that device the original's `cat` fails too: only its `ls` guard kept
it from rebooting the node every two minutes.

Ethernet TX hung after a transmit timeout (`eth_tx_stall`)
---------------------------------------------------------

For `mtk_soc_eth` (MT7981/MT7986), after
[openwrt/openwrt#17505](https://github.com/openwrt/openwrt/issues/17505): first
`NETDEV WATCHDOG: eth0 (mtk_soc_eth): transmit queue 0 timed out`, then
`warm reset failed`, after which both GMACs stay dead. Reported to us for a Cudy
TR3000 whose 2.5G WAN (RTL8221B over 2500base-x) dies and does not come back.
**Not yet confirmed on our own nodes** - the dmesg of a hung node is still
outstanding.

What the kernel does (5.15 with the backports `729-19` to `729-21`):

* `dev_watchdog()` finds a TX queue stopped for longer than `watchdog_timeo`
  (5 s for this driver), counts `/sys/class/net/<dev>/queues/tx-N/tx_timeout`
  up and calls the driver - every 5 s for as long as the queue stays stuck. The
  WARN appears only once per boot, the counter keeps rising.
* `mtk_tx_timeout()` only schedules a reset when `mtk_hw_reset_check()` finds
  error bits in the frame engine's interrupt status. Otherwise it returns
  silently, and the queue may simply stay stuck.
* A reset that fails logs `warm reset failed`.

The check, every minute:

| situation | reaction |
| --- | --- |
| no netdev of a listed driver, or all `tx_timeout` counters 0 and no episode running | ends after a few globs and reads, no process started, no uci |
| the `tx_timeout` sum of a netdev rose | log once, watch that netdev |
| watched, `tx_packets` did not move **and the timeouts kept rising** | one strike (a stuck queue is re-reported by the kernel every 5 s); `warm reset failed` in the dmesg makes it two |
| watched, `tx_packets` did not move, no new timeouts, but `warm reset failed` | strikes too - a dead GMAC need not have carrier any more |
| `hotfix.eth_tx_stall.strikes` reached (default 3, i.e. about 3 minutes) | reboot - **only if switched on**, see below; otherwise "dry run, would reboot", reason with netdev, counters, BQL inflight, carrier and the last two matching dmesg lines |
| watched, `tx_packets` moves and no new timeouts | "recovered" logged, episode over, no action |
| watched, `tx_packets` stands but no new timeouts | episode closed, no action: the reset worked and the port is just quiet, or the cable is out |
| timeouts while `tx_packets` still moves | logged once, never acted on (one queue stuck while others send) |

Without carrier the kernel watchdog does not fire at all, so a pulled cable
never starts an episode in the first place.

**Port reset before the reboot** (adorfer, 14.09.2026). When the strikes are
reached, the check first runs `ethtool -r <dev>` (restart autoneg), as if the
cable had been pulled and plugged back in - on the Cudy TR3000 with its
RTL8221B only that ever helped, a reboot with the cable in often did not:

| step | what | in dry run |
| --- | --- | --- |
| 1 | `ethtool -r`, if `ethtool` is installed and `hotfix.eth_tx_stall.soft_reset` is not `0`; logged to the syslog only | runs as well - harmless and informative |
| - | TX comes back | "recovered after ethtool -r", done |
| - | `ethtool -r` fails (fixed link, driver without nway_reset) | straight on to step 2 in the same run |
| 2 | strikes reached again within the hour | reboot | "would reboot ..., ethtool -r did not help" |

One port reset per port counts for 60 minutes, so a port that goes quiet after
the reset cannot keep the check from escalating. Without `ethtool` (it is only
in the images of the RTL8221B devices, firmware 8b8041b) step 2 follows
directly, as before. There is deliberately no `ip link down/up` as a
substitute: it would cut across netifd and `br-wan`.

**Second trigger, only for RTL8221B uplinks** (Cudy TR3000, WR3000H, M3000):
a GMAC whose `phydev` is bound to an RTL8221B driver (compared fork-free with
`[ -ef ]`) and which is a port of `br-wan`. Carrier up but `rx_packets` does
not move for `hotfix.eth_tx_stall.rx_strikes` runs (default 5, i.e. about 5
minutes): that is the "booted with the cable already in, SerDes mode wrong"
case, which need not produce a single TX timeout. An uplink receives something
every few seconds (ARP, router advertisements, VPN keepalives); five minutes of
nothing with link up is not idle. Reaction: only `ethtool -r`, **never a
reboot**, from the same once-per-hour budget per port. RX moving again is
logged as recovered. On these devices the check therefore always runs its full
path (with uci), elsewhere the process-free exit stays.

```
uci set hotfix.eth_tx_stall.soft_reset='0'   # no port reset
uci set hotfix.eth_tx_stall.rx_strikes='10'  # RTL8221B trigger after 10 min
uci commit hotfix
```

Not tested on a real RTL8221B - there is none among our test devices; the
logic was played back with a fake sysfs including a bound RTL8221B driver.

**Only logs by default.** The reaction is unproven: no hung node has been
seen yet, the tests ran on played-back counters. Switching it on:

```
uci set hotfix.eth_tx_stall.dry_run='0'
uci commit hotfix
```

or for the whole community in the `site.conf` (seeded by
`500-neanderfunk-hotfix` if the node has no value of its own):

```lua
  hotfix = {
    eth_tx_stall_dry_run = 0,
  },
```

**Scope.** Only the netdevs the driver itself registers are looked at - the
GMACs, found as `/sys/bus/*/drivers/<driver>/*/net/*` - not the DSA ports
behind them. On a Cudy WR3000S that is `eth0` alone (16 TX queues), with
`lan1`-`lan4` on the switch. `mtk_soc_eth` is the driver name not only on
filogic (MT7981/MT7986) but also on MT7621, MT7622 and, from OpenWrt's own
ramips driver, mt76x8 and mt7620: on 14.09.2026 263 of 1112 online nodes,
among them the 64 MB mt76x8 devices (19 Netgear R6120, Archer C50 v3, Cudy
WR1000). That is why a node without any timeout since boot starts no process
for this check. The analysis of the reset path above is for the mediatek
driver; the ramips one is only covered by the generic logic. Further drivers
are added with

```
uci add_list hotfix.eth_tx_stall.driver='<driver>'
uci commit hotfix
```

The list is read straight from `/etc/config/hotfix` without starting `uci`,
because the entry runs every minute on every node and most of them do not
have this driver; a driver added without `uci commit` is therefore not seen.

The reboot goes through `now_reboot()` like every other check: held back below
`reboot_uptime_min`, never while the autoupdater runs, and written to the
shared reboot log. Whether a warm reboot helps at all is open: the TR3000's
operator reports the WAN staying dead across warm reboots. Then the check
cannot cure it, and the hold-off limits it to one reboot per hour - on a node
that may still be meshing over wifi. One more reason for the dry-run default.

Testing without rebooting anything: the environment variables
`HOTFIX_DRYRUN=1`/`=0`, `HOTFIX_SYSFS=<fake sysfs root>`,
`HOTFIX_DMESG=<file>`, `HOTFIX_STATE=<state prefix>` and
`HOTFIX_ETHTOOL=<command>` play the counters back
from `/tmp`. Tested that way on 14.09.2026 on a Cudy WR3000S v1 (MT7981,
26091317bro), with `now_reboot` also removed from the copy under test:
arming, three strikes with rising counters, a quiet port after a successful
reset (no action), recovery, timeouts while TX moves, `warm reset failed`
without carrier, counters going backwards, dry run by default and switched
on; against the real sysfs with all counters 0: no process started, no state
file written. `eth0` found and all `queues/tx-*/tx_timeout` readable also on
MT7621 (COVR-X1860, Xiaomi 4A Gigabit). The port reset (14.09.2026, same way,
`ethtool` replaced by `echo` and `false`): reset at the third strike,
recovery after it, reboot stage when it did not help, a failing `ethtool`
going straight to the reboot stage, no `ethtool` at all; the RTL8221B trigger
after five minutes without RX, no reaction without carrier, no second reset
within the hour.

Remote syslog socket (`logremote`)
----------------------------------

With `system.@system[0].log_ip` set, `logread -r` connects its UDP socket once,
when it starts - and at boot that is too early. Either the `connect()` fails
silently and logread keeps running without ever sending, or it succeeds with the
source address that existed at that moment, usually only the domain's ULA,
before the public prefix arrives by router advertisement. Packets from a ULA to
a public address are dropped by the supernode. Seen on 15.09.2026 on all 13
Schulstr7 devices and on a MERCUSYS MR90X after their firmware update: nothing
arrived, `logread` claimed "connected". The same happens when the public prefix
changes later (supernode takeover). The procd instance `logremote` has no
respawn.

Every healthcheck run (`*/7`) compares the source address of logread's socket
(`netstat -anup`) with the one the kernel would pick now (`ip route get
<log_ip>`). If they differ, or there is no socket, only the `logremote`
instance is restarted: the logread process is killed and `/etc/init.d/log
start` brings it back - no reboot, `logd` and its buffer stay. Without a route
to `log_ip` (no uplink) it does nothing, and a host name instead of an address
is left alone. Nodes without `log_ip`, nearly the whole fleet, start no process
for this: `/etc/config/system` is read with `read`.

ath10k hangs (`ath10k_rxhang`)
------------------------------

Two failure modes of the ath10k (qca988x/qca9887, the 5 GHz radio on e.g. the
Archer C7 and C25). Both leave 5 GHz dead with no self-recovery, both appeared
under wifi load with `vm.min_free_kbytes=2048` and never with 8192 (C25,
15./16.09.2026).

**`rxring`** - `ath10k_pci ...: rx ring became corrupted: -5`. The ath10k
refills its RX DMA ring buffers in interrupt context with `GFP_ATOMIC`. If the
atomic reserve is too small under load, the ring goes corrupt and the chip
hangs. A `wifi` restart did not bring it back (the interface vanished), only a
reboot did; reproduced three times. **One line is enough to trigger** - the
ring does not repair itself.

**`fwloop`** - `ath10k_pci ...: failed to send pdev bss chan info request,
restarting hardware` followed by `already restarting`, repeating every ~9
seconds. The chip firmware crashes and the driver's restart never completes.
Here the check **counts**: a single `restarting hardware` can be a one-off the
driver recovers from, so it takes `hotfix.settings.ath10k_restart_min`
occurrences (default 3) in the ring buffer before this counts as a loop.

The reboot message names which one it was (`rxring:` or `fwloop:`), so an
evaluation of `reboot.log` later does not just read "ath10k".

The `wifi_firmware` check only covers mt76 (`rf_regval`); ath10k had none.
Like the other dmesg checks: after the reboot the ring buffer is empty, so
there is no loop, and `reboot_uptime_min` applies so a device that throws the
error right at boot does not reboot-loop. On devices without ath10k neither
pattern ever matches - mt76 lines mentioning "restarting hardware" do not,
because both patterns require `ath10k` on the same line.

Limit of the check: during the `fwloop` on 16.09. the node later became
unreachable entirely - serial console silent, no network. The hardware watchdog
(procd holds `/dev/watchdog`, 30 s timeout, fed every 5 s) did **not** fire, so
it was not a kernel freeze: procd kept running and feeding while console,
network and wifi were dead. micrond no longer got its turn either, so in that
end state the check can do nothing - it has to catch the restart loop while the
system is still alive.

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

These markers are what `now_reboot()` in `common.sh` consults, so **every** check
of this package is held off while an update runs, and none of them can reboot
during a flash write - not even one called with `-f`.

On top of the markers, `autoupdater_busy()` also takes the lock the autoupdater
really uses (`/var/lock/autoupdater.lock`, `flock(LOCK_EX|LOCK_NB)`, held across
the sysupgrade) and looks for the `autoupdater` and `sysupgrade` processes, so
the guard still holds if the hooks ever fail to run.

The file this used to check instead, `/tmp/autoupdate.lock`, is written by
nobody. It appears in the entire Gluon history (5187 commits, tags back to
v2014.1) and in the package feed (892 commits) exactly zero times: it was never
a Gluon mechanism. It originates in `eulenfunk/packages` commit `e783d3a` of
2016-05-06, four months *before* Gluon gained an autoupdater lock at all
(`1acb4b1`, 2016-09-08). A day after the check, that feed also gained a hook
that really did write the file (`19d53ae`,
`files/usr/lib/autoupdater/upgrade.d/00lockfile`) - but the hook was lost when
two packages were merged in 2017 (`535b9e3`, finally `52685ec`) while the checks
stayed, and was copied onwards into several community feeds in that state. Every
reference to it has been removed here, including the `stale_lock` check that
existed solely to notice a leftover copy of it. The whole story is in
`docs/autoupdate-lock-nachlese.md`.

While `autoupdater-flashing` exists the watchdog **never** reboots - interrupting
a flash write bricks the node. While an update is merely running it reboots only
once that run exceeds `autoupdater_stale_min` minutes (default 300), on the
assumption that the updater is then stuck rather than working.

```
uci set hotfix.settings.watchdog_interval_min='5'
uci set hotfix.settings.autoupdater_stale_min='300'
uci commit hotfix
```
