# neanderfunk-nodeplacer

Moves individual Gluon nodes to another domain of the same community,
controlled by a signed manifest on the community's servers.

Nodes fetch `<mirror>/nodeplacer.manifest` once per hour. The manifest uses
the framing of the autoupdater manifest (header, body, `---`, signatures)
and is signed with the same tools and keys (`contrib/sign.sh`, `ecdsasign`).

The package carries the community prefix; the program, its config and the
manifest are simply called `nodeplacer`.
A node that finds its own node id in the verified body switches:

* `domain`: multi-domain firmware, target domain contained in the image.
  Uses `gluon-switch-domain <target>` (reboot). **Untested**: multi-domain
  support is deferred until after the first release; only `firmware` is
  used in practice for now.
* `firmware`: installs the target domain's image via the regular autoupdater
  (`autoupdater -f --force-version -b <branch> <mirror...>`). Branch name,
  signing keys (`pubkey=`) and signature threshold (`good_signatures=`) of
  the target domain are independent of each other; each one that is left
  out keeps this node's own value. Overrides live in the UCI delta and are
  gone after the reboot.

Whoever can sign the manifest can point a node at almost any firmware, so
the signature under `nodeplacer.manifest` is the only trust anchor of this
mechanism.

Nothing is written to flash for an attempt; state lives in `/tmp`. Attempts
are limited to 3 per 7 days per target (rolling window).

## site.conf

```lua
nodeplacer = {
  mirrors = {
    'http://firmware.example.org/nodeplacer',
    'http://[2001:db8::1]/nodeplacer',
  },
  -- Optional overrides, normally left out: without them the control file
  -- is verified with the keys and the threshold of the autoupdater branch
  -- this node runs, so whoever may release a firmware may also move it.
  -- pubkeys = { '<hex>', '<hex>' },
  -- good_signatures = 2,
  -- optional, default 0; node owners may set nodeplacer.settings.disable=1
  -- disable = 0,
},
```

## Manifest

```
FORMAT=1
DATE=2026-09-04 12:00:00+02:00
EXPIRES=2026-10-02 12:00:00+02:00
# comments are allowed and signed
80afcacfc55c domain target=ffnef21dias
80afcacfc55d firmware branch=stable mirror=http://firmware.example.org/firmware/stable/21_dias/sysupgrade mirror=http://[2001:db8::1]/firmware/stable/21_dias/sysupgrade
80afcacfc55e firmware mirror=http://fw.other-community.example/stable/sysupgrade good_signatures=2 pubkey=<hex> pubkey=<hex> pubkey=<hex>
---
<signature>
<signature>
```

Full format description: `docs/MANIFEST-FORMAT.md` next to this file (in the
feed) or in https://github.com/Adorfer/neanderfunk-nodeplacer-dev.

## Installing on a node with opkg

`opkg install neanderfunk-nodeplacer_*.ipk` works, but the postinst runs `check_site.lua`
against the node's `site.json`; if that has no `nodeplacer` block, opkg
reports postinst status 1. The files are installed anyway. In an image
build the check runs at build time.

## Files

| Path | Purpose |
|---|---|
| `/usr/sbin/nodeplacer` | Lua, policy: preconditions, parse, plausibility, state, action |
| `/usr/sbin/nodeplacer-fetch` | C, derived from the autoupdater: download, signature and header check, prints the verified body |
| `/usr/lib/lua/nodeplacer/manifest.lua` | body parser and date parser |
| `/usr/lib/lua/nodeplacer/state.lua` | attempt counter in `/tmp/nodeplacer.state` |
| `/lib/gluon/upgrade/510-nodeplacer` | writes `/etc/config/nodeplacer` from site.conf, installs the cron job |
| `/usr/lib/micron.d/nodeplacer` | hourly run at a random minute |
| `/usr/lib/respondd/neanderfunk-nodeplacer.so` | `nodeinfo.software.nodeplacer`: enabled, target, attempts, last manifest date |

## Exit codes of nodeplacer-fetch

| Code | Meaning |
|---|---|
| 0 | verified, body on stdout |
| 1 | configuration error |
| 2 | no manifest on any mirror (the normal case) |
| 3 | manifest found but rejected (signatures, FORMAT, DATE/EXPIRES, expired); no further mirror is tried |

## Debugging on a node

```
nodeplacer-fetch            # prints the verified body or an error
nodeplacer                  # one policy run, logs to syslog
cat /tmp/nodeplacer.state   # attempts
uci set nodeplacer.settings.disable=1 && uci commit nodeplacer   # owner opt-out
```

## Scope

Same community only. Moving nodes into a domain of another community
requires a procedure agreed between both communities (registration in the
target domain, a migration firmware that copes with the leftover UCI
configuration, timing). See `docs/DESIGN.md` section 15.

## License

BSD-2-Clause. `src/uclient.c`, `src/hexutil.c`, `src/util.c` and
`src/manifest.c` are derived from the Gluon autoupdater
(https://github.com/freifunk-gluon/packages, `admin/autoupdater`).
