# Package

version       = "0.1.0"
author        = "Michael Green"
description   = "A very simple World of Warcraft addon manager"
license       = "GPLv3+"
srcDir        = "src"
namedBin      = {"hearthsync":"hs"}.toTable


# Dependencies

requires "nim >= 2.2.6"
requires "zippy >= 0.10.6"
