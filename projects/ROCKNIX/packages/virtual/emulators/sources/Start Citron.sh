#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Opens the Citron (Nintendo Switch) GUI so you can install firmware, manage
# prod.keys/title.keys and change settings. A mouse + keyboard is recommended.
# Calling start_citron.sh with no ROM argument launches the GUI; it also wires
# up the keys/NAND/SD folders under /storage/roms/bios/citron.
source /etc/profile
/usr/bin/start_citron.sh
