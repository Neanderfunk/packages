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
  Gluon roles via `/etc/board.json`, WAN addresses. Ports split off into
  further `gluon` interface sections (e.g. `iface_client`) or into own mesh
  ports in `network` (`proto gluon_wired`, `gluon_preserve 1`, as set up by
  the workshop guide "LAN-Ports trennen") get rows of their own; a port with a
  role in more than one section is warned about.
- VPN connected or not from `batctl if` (independent of the gateway TQ; right
  after boot it says "baut auf"), gateway with TQ and outgoing interface
- clients (local, per band, mesh-wide), SSID and offline-SSID counters
- a radio table with the live channel, width, HT mode and tx power per radio
  (from `iwinfo`), AP and mesh state, clients and mesh neighbours with TQ
- a warning when a radio's channel differs from the firmware (site.conf /
  domain, as Gluon's `200-wireless` would set it) while `preserve_channels`
  is off - the next update would reset it
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
  Removing the last uplink or a mesh role asks first (`-y` to skip). Without
  arguments it lists every role section including own mesh ports; it refuses
  (also with `-y`) to give ports a role they already have elsewhere.
- `reconf` - `gluon-reconfigure` and then reboot, detached in the background
  (survives the SSH session ending); log in `/tmp/reconf.log`, no reboot if
  the reconfigure fails.
- `v4up` - fetches IPv4 via DHCP from the mesh on `br-client`. Refused if the
  uplink already has IPv4: a second default route would pull the tunnel into
  the mesh and, without another uplink there, cut the node off.
- `flash <url|directory-url|file> [sysupgrade options]` - downloads a
  firmware image to `/tmp` (an `https://` URL is fetched as `http://`, not
  every node has TLS), shows size, free RAM and sha256, checks it with
  `sysupgrade -T` and only then runs `sysupgrade`. A URL without a file name
  (e.g. `.../sysupgrade/`) makes it look for this device's image itself: in
  the autoupdater manifests there (configured branch first), whose sha256 the
  download must then match, else in the server's directory listing, by the
  Gluon image name (`platform_info`). Options after the URL are passed on, in
  front of the file as sysupgrade expects, e.g. `flash <url> -n` to drop the
  configuration. With little RAM (MemAvailable below 32 MB before the
  download, or below 16 MB with the image in `/tmp`) it goes the
  autoupdater's way: first the services in `/usr/lib/autoupdater/download.d`
  are stopped (respondd, uhttpd, cron, micrond ...), at the end
  `upgrade.d` (wifi down, network stopped, bat0 removed) and sysupgrade run
  detached from the session - "wifi down" cuts an SSH session over wifi or
  mesh. Without that, stage2 starves on 64 MB devices (Archer C25: the wifi
  drivers keep their RX buffers until the watchdog resets, nothing flashed).
  Log in `/tmp/flash.log` and syslog (`logread -e flash`); if sysupgrade
  returns, `abort.d` brings network and services back. `FLASH_HOOKS=1`
  forces this path, `FLASH_HOOKS=0` disables it. In interactive shells plain
  `sysupgrade <url>` does the same (see below); `flash` is for
  `ssh node flash <url>`.
- `help` - cheat sheet.

Read-only aliases in the profile: `gwl`, `nb`, `gwtr` (batman traceroute to
the selected gateway), `wlc` (wifi clients), `myip`, `logf`, `logerr`,
`vpnlog`, `ports`.

`uci` guard (interactive shells only): a bare `uci commit`, `uci commit
wireless` or `uci commit autoupdater` is refused while runtime-only changes
are pending - the ssid-changer's Offline-SSID (with OWE switched off), with
ap-timer enabled client APs switched off, and during a nodeplacer firmware
move the autoupdater branch it overrides. Committed like that they would
stick. `uci commit <package>` always works; `command uci commit`
forces it. Scripts are not affected.

`sysupgrade` wrapper (interactive shells only): when the image argument is an
`http://` or `https://` URL (file or directory) or an existing file, the call
goes to `flash` (checks, and the autoupdater's service stops when RAM is
low), with the image first and all options behind it - so options may also
follow the image, which the real sysupgrade silently ignores. The value of
`-f`, `-b` and `-r` is not taken for the image. Anything else (`-b`, `-l`,
`-h`, no argument) runs the original unchanged, and so do scripts and the
autoupdater (`/sbin/sysupgrade`). `command sysupgrade <image>` bypasses the
wrapper.

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
