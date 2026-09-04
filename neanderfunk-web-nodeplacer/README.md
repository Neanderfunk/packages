# neanderfunk-web-nodeplacer

Adds a tab "Nodeplacer" to the config-mode "Advanced settings" page
(the same page that holds "Automatic updates", "Remote access", and so
on). It shows a single checkbox that lets the node owner allow or forbid
automatic domain moves, i.e. it toggles `nodeplacer.settings.disable`.

Split out from `neanderfunk-nodeplacer` itself so that the core package
stays free of a `gluon-web-admin` dependency; install this only where the
config-mode web UI is wanted.

## Files

| Path | Purpose |
|---|---|
| `luasrc/lib/gluon/config-mode/controller/admin/nodeplacer.lua` | registers the tab under "admin" (weight 85, right after "Automatic updates" at 80) |
| `luasrc/lib/gluon/config-mode/model/admin/nodeplacer.lua` | the form itself |

## License

BSD-2-Clause.
