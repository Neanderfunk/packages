-- SPDX-License-Identifier: BSD-2-Clause
-- SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk

package 'neanderfunk-web-nodeplacer'

-- "Automatic updates" (gluon-web-autoupdater) sits at weight 80 on the
-- same "admin" ("Advanced settings") page; nodeplacer is closely related,
-- so it follows right after it.
entry({"admin", "nodeplacer"}, model("admin/nodeplacer"), _("Nodeplacer"), 85)
