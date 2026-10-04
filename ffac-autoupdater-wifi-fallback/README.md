# ffac-autoupdater-wifi-fallback

**Neanderfunk feed, branch v2021.1.x (Sackgasse, OpenWrt 19.07):** copy of
freifunk-gluon/community-packages 1493e17 (BSD-2-Clause, see LICENSE). Only change:
no dependency on gluon-state-check (not in Gluon 2021.1); its has_default_gw4
check (batman gateways listed, or gw_mode server) is done inline. Tested on a
TL-WR841N v9: Lua modules present, scan via radio name, update hosts, gateway
check, respondd module (built with the 19.07 SDK) loads. The fallback itself
(-f) was not run on the test node, it would flash.

If a node has no connection to the mesh, neither via wlan-mesh nor via
mesh-vpn, it ist not possible to update this node via `autoupdater`. Therefor
the *wifi-fallback* was developed. It checks hourly whether the node is part of
a fully operative mesh or not. Else the node connects to a visible "Freifunknetz"
and tries downloads an update as wlan-client via executing `autoupdater -f`.

This is compatible with gluon/openwrt versions >= v2022.x

## /etc/config/autoupdater-wifi-fallback

**autoupdater-wifi-fallback.settings.enabled:**
- `0` disables the fallback mode
- `1` enables the fallback mode

### example
```
config autoupdater-wifi-fallback 'settings'
	option enabled '1'
```

## Credits

This includes gluon-state-check from tecff to be mesh protocol independent.
As well as using upstream wpa-supplicant-mini to support new version.
It was formerly created by ffho as `ffho-autoupdater-wifi-fallback`
