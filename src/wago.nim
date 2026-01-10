import std/enumerate
import std/sets
import std/json
import std/sequtils
import std/strformat
import std/terminal

import types
import term
import addonHelp

proc setDownloadUrlWago*(addon: Addon, json: JsonNode) {.gcsafe.} =
  for data in json["props"]["releases"]["data"]:
    if data["supported_" & addon.gameVersion & "_patches"].len > 0:
      addon.downloadUrl = data["download_link"].getStr()
      return
  addon.setAddonState(Failed, &"JSON Error: No release matches current verion of {addon.gameVersion}.", 
    &"JSON Error: {addon.getName()}: no release matches current version of {addon.gameVersion}.")

proc getVersionName(version: string): string =
  case version
  of "retail": result = "Retail"
  of "cata": result = "Cataclysm"
  of "wotlk": result = "WotLK"
  of "bc": result = "Burning Crusade"
  of "classic": result = "Classic"
  of "mop": result = "Mists of Pandaria"
  else: result = "Unknown"

proc userSelectGameVersion(addon: Addon, options: seq[string]): string {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      let versionName = getVersionName(option)
      if selected == i + 1:
        t.write(16, addon.line + i + 1, false, bgWhite, fgBlack, &"{i + 1}: {versionName}", resetStyle)
      else:
        t.write(16, addon.line + i + 1, false, bgBlack, fgWhite, &"{i + 1}: {versionName}", resetStyle)
    let newSelected = handleSelection(options.len, selected)
    if newSelected == selected:
      t.clear(addon.line .. addon.line + options.len)
      return options[selected - 1]
    elif newSelected != -1:
      selected = newSelected

proc chooseDownloadUrlWago*(addon: Addon, json: JsonNode) {.gcsafe.} =
  var gameVersions: OrderedSet[string]
  for data in json["props"]["releases"]["data"]:
    let patches = ["retail", "cata", "wotlk", "bc", "classic", "mop"]
    for patch in patches:
      if data["supported_" & patch & "_patches"].len > 0:
        gameVersions.incl(patch)
  if gameVersions.len == 1:
    addon.gameVersion = gameVersions.toSeq()[0]
  else:
    addon.gameVersion = addon.userSelectGameVersion(gameVersions.toSeq())
  setDownloadUrlWago(addon, json)