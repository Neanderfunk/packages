-- setup_mode.autoexit (alles optional; ohne den Block: an, 86400 s)
need_boolean(in_site({'setup_mode', 'autoexit', 'enabled'}), false)
need_number_range(in_site({'setup_mode', 'autoexit', 'timeout'}), 600, 604800, false)
