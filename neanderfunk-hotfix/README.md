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
    check_uptime_min  = 5,                  -- optional, minutes, default 5
    reboot_uptime_min = 60,                 -- optional, minutes, default 60
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
* **`load`** - right after a boot the load is legitimately high, and the 5
  minute average is not meaningful before the node has been up 5 minutes.

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
| `hostapd_pids` | hostapd pid files not matching the running processes | wifi restart |
| `dfs_failcheck` | hostapd failing its DFS check | wifi restart |
| `tunneldigger` | too many tunneldigger watchdogs/instances | reboot |
| `br_client_ipv6` | br-client without an address from the site prefix | reboot |
| `load` | 5 minute load average above 2 | reboot |
| `respondd` | respondd not running | reboot |
| `dropbear` | dropbear not running | reboot |
| `no_wifi_clients` | clients were seen and then all disappeared | wifi restart |
| `wifi_firmware` | mt76 wifi firmware crashed, see below | reboot |
| `watchdog` | deadman switch for micrond itself, see below | reboot |

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
