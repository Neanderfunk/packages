neanderfunk-linkcheck
==================================

this script looks for wifi and lan mesh neighbours. 
goal is to detect crashed/flapping drivers on wifi and eth, even on hw level.
After loss of all neighbors on an interface (where there have been 2 or more in the past), the box is rechecking 3 times (every 5 minutes) and if an interface stays "an island" without not at least one neighbour (where 2 or had been seen since last boot): the box is reboot. 

How triggering an interface works:
If at least 2 meshneibours are found once (after boot) on a link, the script is set into trigger mode for this interface.

(take a look in /tmp/linkcheck.$linktype.$interface for current status.)

when in trigger mode the absence of neighbours in the wifimesh will alert the node. and if the absence is still present the next interval (5 minutes) and the next interval still, the node is rebootet. 
on batctl-o table the "island detection" will be only triggered if the respective link is up. 
in other words: if the lan-link (eth wan/lan) is down ("really disconnected cable"), the reset will not perform. it only detects for "link up, but no partners visible in the link".

example:  (wifi turned off "on purpose")

    Fri Mar 11 11:25:07 2016 user.notice gluon-linkcheck: batadv.br-wan:4 batadv.ibss0:0 ibss0.neighbours:2 ibss0.wadhoc:13
    Fri Mar 11 11:30:07 2016 user.notice gluon-linkcheck: batadv.br-wan:4 batadv.ibss0:0 ibss0.neighbours:2 ibss0.wadhoc:13
    Fri Mar 11 11:35:07 2016 user.notice gluon-linkcheck: batadv.br-wan:4 batadv.ibss0:0 ibss0.neighbours:2 ibss0.wadhoc:11
    Fri Mar 11 11:40:05 2016 user.notice gluon-linkcheck: lost neighbours ibss0.neighbours.
    Fri Mar 11 11:40:05 2016 user.notice gluon-linkcheck: lost neighbours ibss0.wadhoc.
    Fri Mar 11 11:40:05 2016 user.notice gluon-linkcheck: batadv.br-wan:4 ibss0.neighbours:0 ibss0.wadhoc:0
    Fri Mar 11 11:45:06 2016 user.notice gluon-linkcheck: still no neighbours ibss0.neighbours, wifi restart
    Fri Mar 11 11:45:06 2016 user.notice gluon-linkcheck: still no neighbours ibss0.wadhoc, wifi restart
    Fri Mar 11 11:45:06 2016 user.notice gluon-linkcheck: batadv.br-wan:4 ibss0.neighbours:0 ibss0.wadhoc:0
    Fri Mar 11 11:50:05 2016 user.notice gluon-linkcheck: 2nd time no neighbours ibss0.neighbours, rebooting!
    packet_write_wait: Connection to fda0:747e:ab29:9375:6666:b3ff:fede:a7e4 port 22: Broken pipe


Create a file "modules" with the following content in your ./gluon/site/ directory:

GLUON_SITE_FEEDS="eulenfunk"<br>
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git<br>
PACKAGES_EULENFUNK_COMMIT=*/missing/*<br>
PACKAGES_EULENFUNK_BRANCH=chaos-calmer<br>

With this done you can add the package *neanderfunk-linkcheck* to your site.mk/image-customization.lua


Configuration
=============

Every single check can be switched off per node, and the reboot hold-off after
a boot is adjustable. Both are UCI settings, and both can be preset for the
whole community from the `site.conf`.

Switching a check off on one node:

```
uci set linkcheck.<check>.disabled='1'
uci commit linkcheck
```

`uci show linkcheck` lists the available check names. The name is also part of the
reason logged before a wifi restart or a reboot, e.g.

```
neanderfunk-linkcheck: [bsses] ...
```

so if you watch a node over SSH with `logread -f` and see it reboot, the syslog
line tells you directly which key to set if you consider that check a false
positive on your node.

Reboot hold-off after a boot (minutes, default 60 when unset). No check may
reboot the node before this:

```
uci set linkcheck.settings.reboot_uptime_min='90'
uci commit linkcheck
```

site.conf
---------

Both can be preset community-wide. `/lib/gluon/upgrade/500-neanderfunk-linkcheck`
seeds them on every `gluon-reconfigure`, but never overwrites a value already
set on the node - so a local `uci set` always wins over the site default:

```lua
  linkcheck = {
    reboot_uptime_min = 60,                 -- optional, minutes, default 60
    disabled_checks = { 'bsses' },  -- optional
  },
```

Checks
------

| check | what it does | reaction |
| --- | --- | --- |
| `batadv_neighbours` | direct batman neighbours per batman interface | wifi restart, reboot |
| `bsses` | networks visible in an `iw scan` per radio (a radio seeing none at all is a strong "radio is dead" signal) | wifi restart, reboot |
| `batinterfaces` | a batman interface that was present has disappeared | wifi restart, reboot |
| `batman_originators` | originators reachable via a batman interface (wifi mesh links are excluded on purpose) | wifi restart, reboot |
| `bridges` | a bridge that was present has disappeared | wifi restart, reboot |
| `bridge_ports` | a port that was part of a bridge dropped out of it | wifi restart, reboot |
| `mesh_neighbours` | a wifi mesh radio that had >=2 neighbours now has none | wifi restart, reboot |
| `no_gateway` | no batman gateway in range for 4 runs (`gateway.sh`) | reboot |
| `ipv6_anycast` | the IPv6 anycast address unreachable for 4 runs (`gateway.sh`) | reboot |

The first seven follow the same rule: a check only arms once it has seen at least
2 of whatever it counts during this runtime, and only then does losing all of
them escalate. A node that is legitimately alone therefore never escalates, and
because the markers live in `/tmp`, an outage costs at most one reboot - after
it the node is not armed again until it has really seen neighbours again.

`no_gateway` and `ipv6_anycast` run from a second cron entry (`gateway.sh`,
every 8 minutes) and arm the same way: only a node that has seen a gateway, or
reached the anycast address, at least once since boot can reboot over losing it.
Four consecutive failures - roughly half an hour - are needed. Both used to live
in neanderfunk-hotfix; they ask whether the network still works, not whether
this node is healthy, so they belong here.

