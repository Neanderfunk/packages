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
- warnings, only when they apply: no gateway, VPN down (with the likely
  reason), mesh interface configured but down, radio disabled, multiple roles
  on one interface, location set but not shared, load above the core count,
  flash full or read-only, clock before the firmware build, autoupdater off,
  no contact or location

Data comes from respondd (`gluon-neighbour-info`, the same data the map gets),
`uci`, `batctl`, `iwinfo`, `ubus` and `/sys`. It only reads, never writes.

It also installs a few standalone helper commands:

- `nodestatus` (alias `status`) - the overview above, on demand.
- `nodeinfo` - the same status summary in more detail, plus fastd/tunneldigger
  key info, batman neighbour counts and node location.
- `help` - a cheat sheet of useful commands (autoupdater, batctl, iw, ...).
- `switch0` / `switchstatus` - short/verbose ethernet switch port status.
- `v4up` - forces a DHCP request on the client bridge if no IPv4 default
  route is reachable via the mesh VPN.

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
