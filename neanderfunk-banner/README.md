neanderfunk-banner
===================

Replaces the stock OpenWrt `/etc/banner` and `/etc/profile` with Gluon-specific
versions (as symlinks to `banner.gluon`/`profile.gluon`, so the originals are
kept as `.openwrt` and restored automatically on removal).

The login banner shows a short ASCII graphic and points to `help`. The
profile prints a one-line status summary on every shell login: uptime,
firmware/autoupdater branch, gateway/VPN state, wifi radio status, switch
port status and public IPv4/IPv6 if reachable - handy for a quick glance
without having to run several commands by hand.

It also installs a few standalone helper commands:

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
