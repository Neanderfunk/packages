-- Optional. Gluon selbst liest diesen Schluessel nicht; dieses Paket nimmt ihn
-- als Default fuer gluon.wireless.preserve_channels. Zahl oder Boolean, weil
-- in den bestehenden site.conf "preserve_channels = 1" steht.
need_one_of({'wifi24', 'preserve_channels'}, {true, false, 1, 0}, false)
