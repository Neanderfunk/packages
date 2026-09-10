neanderfunk-banner
===================

Replaces the stock OpenWrt `/etc/banner` and `/etc/profile` with Gluon-specific
versions (as symlinks to `banner.gluon`/`profile.gluon`, so the originals are
kept as `.openwrt` and restored automatically on removal).

The login banner shows a short ASCII graphic and points to `help`. The
profile first runs OpenWrt's own profile unchanged (PATH, `ENV=/etc/shinit`,
failsafe, `/etc/profile.d`, the read-only-overlay hint), then - in interactive
shells only - `nodestatus`.

`nodestatus` prints an 80-column overview with fixed columns, coloured on a
terminal (`NO_COLOR` disables, `FORCE_COLOR` forces colour). It shows what is
actually running, not just what is configured:

- node, image name, domain, firmware, uptime, load, free RAM and flash,
  autoupdater, contact and location
- ports with link and speed from `/sys` (DSA) or `swconfig`, mapped to their
  Gluon roles via `/etc/board.json`, WAN addresses
- VPN connected or not from `batctl if` (independent of the gateway TQ; right
  after boot it says "baut auf"), gateway with TQ and outgoing interface
- clients (local, per band, mesh-wide), SSID and offline-SSID counters
- a radio table with the live channel, width, HT mode and tx power per radio
  (from `iwinfo`), AP and mesh state, clients and mesh neighbours with TQ
- on devices without wifi (x86, ERX, ...) a port table in its place: per port
  link, traffic since boot and error counters, per role group mesh state and
  neighbours; on swconfig switches the real link per switch port.
  `NODESTATUS_NOWIFI=1` shows this layout on a wifi device for testing
- warnings, only when they apply: no gateway, VPN down (with the likely
  reason), mesh interface configured but down, radio disabled, multiple roles
  on one interface, location set but not shared, load above the core count,
  flash full or read-only, clock before the firmware build, autoupdater off,
  no contact or location

Data comes from respondd (`gluon-neighbour-info`, the same data the map gets),
`uci`, `batctl`, `iwinfo`, `ubus` and `/sys`. It only reads, never writes.

It also installs these commands (all listed by `help`):

- `nodestatus` (alias `status`) - the overview above, on demand.
  `nodestatus details` adds every mesh neighbour with TQ and signal, all
  gateways, the VPN brokers with the connected one marked, and the node's
  addresses; `nodestatus ports [-v]` prints just the port table.
- `nodeinfo` - `nodestatus details`.
- `switch0` (alias `ports`) - the port table on any device, swconfig or DSA.
- `switchstatus` - the port table with MAC, MTU, bridge, link changes since
  boot and drops per port; `-r` shows the raw swconfig output.
- `lanrole` / `wanrole` - show or set `gluon.iface_<lan|wan>.role`, checked
  like Gluon's Advanced Settings (client only alone, uplink+mesh allowed).
  Removing the last uplink or a mesh role asks first (`-y` to skip).
- `reconf` - `gluon-reconfigure` and then reboot, detached in the background
  (survives the SSH session ending); log in `/tmp/reconf.log`, no reboot if
  the reconfigure fails.
- `v4up` - fetches IPv4 via DHCP from the mesh on `br-client`. Refused if the
  uplink already has IPv4: a second default route would pull the tunnel into
  the mesh and, without another uplink there, cut the node off.
- `help` - cheat sheet.

Read-only aliases in the profile: `gwl`, `nb`, `gwtr` (batman traceroute to
the selected gateway), `wlc` (wifi clients), `myip`, `logf`, `logerr`,
`vpnlog`, `ports`.

Create a file `modules` with the following content in your `./gluon/site/`
directory and add these lines:

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_EULENFUNK_COMMIT=*/missing/*
PACKAGES_EULENFUNK_BRANCH=v2023.2.x
```

With this done you can add the package `neanderfunk-banner` to your `site.mk`
(`*/missing/*` has to be replaced by the github-commit-ID of the version you
want to use, you have to pick it manually.)


Mutually exclusive packages
---------------------------

Declares `CONFLICTS:=ffmuc-custom-banner`. That package also owns
`/etc/banner.gluon` and also replaces the login banner - it templates it from an
upgrade script rather than symlinking - so the two would clobber each other.
