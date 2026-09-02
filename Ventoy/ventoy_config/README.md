# Ventoy Configuration Files
These files reside on the first partition of the USB drive (`/dev/sdb1`):

* `ventoy.json`: Defines ISO persistence bindings (`rescuezilla-persistence.dat`) and menu aliases. Path on USB: `/ventoy/ventoy.json`.
* `ventoy_grub.cfg`: Defines the custom `F6` boot menu entries to directly load `Ubuntu-USB-Ventoy` (`/dev/sdb3`) and internal Windows (`/dev/sda`). Path on USB: `/ventoy/ventoy_grub.cfg`.
