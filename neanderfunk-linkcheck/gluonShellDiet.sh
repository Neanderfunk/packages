#!/bin/sh

# Removes all comment lines starting with a hash '#' from the files given as
# arguments. The shebang (#!) is kept.
#
# Takes more than one file since 2026-09-07: the Makefiles pass a glob, so a
# newly added script is stripped without anyone having to remember to add it to
# a list. One argument still works exactly as before.

sed -i '/^\s*\#[^!].*/d; /^\s*\#$/d' "$@"
