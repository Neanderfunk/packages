neanderfunk-migrate-updatebranch
=================================

One-shot upgrade script (`lib/gluon/upgrade/910-neanderfunk-migrate-updatebranch`,
runs once during sysupgrade like any other Gluon upgrade script) that cleans up
autoupdater branches which no longer exist in current site configs.

If a node's `autoupdater.settings.branch` is still set to one of the outdated
branches `experimental`, `broken`, `experimentall2tp`, `stablel2tp` or `beta`,
it is switched back to `stable`. The corresponding UCI `autoupdater.<branch>`
sections for those outdated branches are then deleted, regardless of which
branch the node ends up on - they'd otherwise stick around as orphaned config
forever, since the autoupdater itself never removes them.

This only matters for nodes upgrading from a firmware old enough to still
carry one of those branch settings; on a clean/current install there's
nothing to migrate.

Add the feed to your site's `modules` file (next to `site.conf`):

```
GLUON_SITE_FEEDS="neanderfunk"
PACKAGES_NEANDERFUNK_REPO=https://github.com/Neanderfunk/packages.git
PACKAGES_NEANDERFUNK_BRANCH=v2023.2.x
PACKAGES_NEANDERFUNK_COMMIT=<commit>
```

Then add `neanderfunk-migrate-updatebranch` to your `site.mk` or `image-customization.lua`. Replace
`<commit>` with a commit of the `v2023.2.x` branch. If your site already uses
other feeds, append `neanderfunk` to the existing `GLUON_SITE_FEEDS` instead
of replacing it. See also [Using this feed](../README.md#using-this-feed).
