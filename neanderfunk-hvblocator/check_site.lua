-- Nur in der Domain-Datei (in_domain): Die Domain, in der geortet wird,
-- bringt die URLs mit. Jede andere Domain hat den Schluessel nicht, dort tut
-- das Paket nichts. Nach einer Verschiebung ist die Ortung damit aus.
need_string_array_match(in_domain({'neanderfunk_hvblocator', 'urls'}), '^https?://[%w%.%-]+', false)
