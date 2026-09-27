How the node whisperer works
============================

How a Gluon node sends status data to phones that are **not** associated with
it, and how the app picks it up. Checked against the source of this fork, the
daemon and the app (2026-09-13), not written from memory.

- This package: [`neanderfunk-node-whisperer`](https://github.com/Neanderfunk/packages/tree/v2023.2.x/neanderfunk-node-whisperer)
  (fork of [`ffda-node-whisperer`](https://github.com/freifunk-gluon/community-packages/tree/v2023.2.x/ffda-node-whisperer)
  from the Gluon community packages; why we forked is in [README.md](README.md))
- Daemon source: [blocktrron/node-whisperer](https://github.com/blocktrron/node-whisperer)
  (David Bauer, Matthias Schiffer; GPL-2.0-or-later), pinned to `8f1e5560`
  (2024-11-09)
- App: [freifunk-darmstadt/NodeMonitor](https://github.com/freifunk-darmstadt/NodeMonitor)
  (Android, Kotlin)

Sender: the node
----------------

1. **Collect data** every 30 s (`UPDATE_INTERVAL` in `daemon.c`), the first
   time 5 s after start. Each source becomes a type-length-data record:

   | Type | Source |
   |---|---|
   | 0 | hostname |
   | 1 | node_id |
   | 2 | uptime |
   | 3 | site code |
   | 4 | domain (usually absent for us, see patch 0001) |
   | 5 | system load |
   | 6 | firmware version |
   | 20 | batman-adv: byte 0 = VPN uplink yes/no, byte 1 = TQ of the selected gateway (patch 0002; before, it carried the TQ of the VPN neighbour) |

   Which sources are active comes from `site.conf`
   (`node_whisperer.information`), stored in uci as
   `neanderfunk-node-whisperer.settings.information`.

2. **Wrap it in a vendor specific information element** (IEEE 802.11
   "Vendor Specific", element ID 221 = `0xDD`):

   ```
   DD <len> 00 20 91 04 <type> <len> <data> <type> <len> <data> ...
   │        └──┬───┘ │
   │          OUI   OUI type
   element ID 221
   ```

   At most 255 bytes in total (an element has a one-byte length).

3. **Hand it to hostapd** via ubus `hostapd.<iface> set_vendor_elements`, as a
   hex string, on every client AP - for us the `client_radio*` interfaces from
   `/etc/config/wireless`, found by the package's upgrade script. hostapd
   appends vendor elements to **every beacon and probe response** of that
   SSID (same as the `vendor_elements` option documented in
   [hostapd.conf](https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf):
   "into the end of the Beacon and Probe Response frames").

The air interface
-----------------

Beacons are management frames: the AP sends them about every 100 ms,
**unencrypted, to everyone** (broadcast). Every device looking for networks
receives them anyway - that is how it learns SSID, channel and security mode.
No association is needed, and the node sends nothing extra: the data rides
along in the beacon. On an active scan the AP answers with a probe response,
which carries the element as well.

To look at it without the app, from a Linux machine with wifi:

```sh
sudo iw dev wlan0 scan | grep -A2 -i "OUI 00:20:91"
```

`iw` prints unknown vendor elements as `Vendor specific: OUI 00:20:91, data:
04 ...`; after the `04` come the type-length-data records above.

Receiver: the app (Android only)
--------------------------------

- The app starts wifi scans (`WifiManager.startScan()`) and waits for
  `SCAN_RESULTS_AVAILABLE_ACTION` (`services/WifiScanService.kt`).
- Since **Android 11 (API 30)** every `ScanResult` returns the raw information
  elements of the network via
  [`getInformationElements()`](https://developer.android.com/reference/android/net/wifi/ScanResult#getInformationElements()).
  That is why NodeMonitor requires `minSdk = 30`.
- The app keeps elements with `id == 221` whose first four bytes are
  `00 20 91 04` and parses the rest into records (`models/WifiScanResult.kt`).
  More than one such element per network is discarded.
- Android requires **`ACCESS_FINE_LOCATION`** and location services switched
  on for this, because wifi scans reveal the location. The app asks for the
  permission at start.

Limits and side effects
-----------------------

- **Android throttles scans** for apps (see
  [Wi-Fi scanning overview](https://developer.android.com/develop/connectivity/wifi/wifi-scan)).
  The display is not live; the node data is up to 30 s old anyway. How often
  NodeMonitor actually scans was not checked.
- **iOS**, as far as we know, has no public API for the information elements
  of scan results, so an iOS version of the app would not be possible this
  way. Not checked.
- **Public:** anyone in radio range can read hostname, node_id, uptime, load
  and firmware. That is about what the map shows anyway.
- **Airtime:** every beacon grows by the element (a few dozen bytes), per SSID
  and band about ten times a second. Measurable on 2.4 GHz with a low basic
  rate, but small.
- Two daemons (`ffda-node-whisperer` and this fork) on one node would both
  write to the same interfaces; the package therefore declares `CONFLICTS`.
