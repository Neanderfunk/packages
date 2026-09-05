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

Create a file `modules` with the following content in your `./gluon/site/`
directory and add these lines:

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_EULENFUNK_COMMIT=*/missing/*
PACKAGES_EULENFUNK_BRANCH=v2023.2.x
```

With this done you can add the package `neanderfunk-migrate-updatebranch` to
your `site.mk` (`*/missing/*` has to be replaced by the github-commit-ID of
the version you want to use, you have to pick it manually.)
