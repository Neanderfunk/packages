neanderfunk-wifi-blackout
=========================

Forked from <https://git.ffho.net/FreifunkHochstift/ffho-packages> →
`ffho-ath9k-blackout-workaround` (GPL, Karsten Böddeker), which came to us via
`eulenfunk-ath9kblackout`. Renamed because the name was wrong: the failure is
not ath9k-specific, see below.

What it detects
---------------

The radios are up and look healthy from the driver's side, but **not a single
station is associated anywhere on the node** — no client, no mesh peer — and
none has been for hours. Nothing recovers by itself, because nothing in the
system considers this an error.

The node is judged as a whole, not per radio: any interface with a station makes
it healthy. Per radio, a 5 GHz radio without clients would be a permanent false
positive — plenty of clients are 2.4 GHz only.

Why it exists next to the other checks
--------------------------------------

Every other check in this feed arms only once it has seen the healthy state at
least once since boot: `no_wifi_clients` after the first client,
`mesh_neighbours` and `bsses` after two neighbours or networks. That "no island"
rule is deliberate and keeps a legitimately lonely node from escalating — but it
makes all of them **blind to a radio that is broken from the moment it comes
up**, because the healthy state never happens and they never arm.

That case is real, and it is why this check has no arming rule. The price is
that a node which genuinely has no users and no neighbours gets restarted every
few hours; the long `blackoutwait` is what keeps that tolerable.

It is not gated on any chipset. The previous version restricted itself to ath9k
and would have missed the Aruba AP-303 (ipq40xx) this was actually observed on.

What it does
------------

1. Every `stepsize` minutes, ask every enabled wifi interface for its associated
   stations. Any station anywhere → the node is healthy, timestamp refreshed.
2. No station anywhere for longer than `blackoutwait` → restart the wifi.
3. Still nothing after another round → reboot. In the field only a reboot has
   helped in some of these cases.

`resetwait` is the minimum gap between two of those actions, and the clock is
also reset whenever a radio comes up, so a freshly configured radio is never
judged before it had a chance.

site.conf
---------

All optional; the values in brackets are the built-in defaults.

```lua
  wifi_blackout = {
    blackoutwait = 171,  -- [171] minutes without any station before acting
    resetwait    = 281,  -- [281] minutes minimum between two actions
    stepsize     = 10,   -- [10]  minutes between checks (cron period)
  },
```

The old `ath9kblackout = { ... }` block is still read at runtime, so a site that
has not been migrated keeps working unchanged.

Per node
--------

```
uci set wifiblackout.settings.disabled='1'             # off
uci set wifiblackout.settings.restarts_before_reboot='2'  # default 1
uci set wifiblackout.settings.check_uptime_min='10'    # default 5
uci commit wifiblackout
```

The log tag is `neanderfunk-wifi-blackout` and every action names the reason, so
`logread -f` shows what it decided.

History
-------

The package did nothing at all, on any node, for years. Three defects, each
confirmed on real hardware:

* it selected radios by `hwmode == '11g'`, but OpenWrt 21.02 replaced `hwmode`
  with `band`, so no interface ever qualified;
* the ifup hotplug handler declared `local` at file scope, which busybox ash
  rejects outright, so `/tmp/ath9kblackout.reset` was never written;
* the fallback that would have created that marker tested for
  `/etc/config/wireles` — a typo — so the script exited on every single run.

The last two masked the first: had only the typo been fixed, every node would
have restarted its wifi every few hours regardless of chipset.
