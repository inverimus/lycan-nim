import std/enumerate
import std/sets
import std/json
import std/sequtils
import std/strutils
import std/strformat
import std/terminal

import types
import term
import addonHelp

when not defined(release):
  import logger

proc versionWago*(addon: Addon, json: JsonNode): string {.gcsafe.} =
  for data in json["props"]["releases"]["data"]:
    if data["supported_" & addon.gameVersion & "_patches"].len > 0:
      result = data["label"].getStr()
      break
  result = result.replace(json["props"]["addon"]["display_name"].getStr(), "")
  result = result.strip(chars = {' ', '_', '-', '.'})

proc setDownloadUrlWago*(addon: Addon, json: JsonNode) {.gcsafe.} =
  for data in json["props"]["releases"]["data"]:
    if data["supported_" & addon.gameVersion & "_patches"].len > 0:
      addon.downloadUrl = data["download_link"].getStr()
      return
  addon.setAddonState(Failed, &"JSON Error: No release matches current verion of {addon.gameVersion}.")

proc getVersionName(version: string): string =
  case version
  of "retail":  result = "Retail"
  of "cata":    result = "Cataclysm Classic"
  of "wotlk":   result = "WotLK Classic"
  of "bc":      result = "TBC Classic"
  of "classic": result = "Classic (Vanilla 1.15)"
  of "mop":     result = "MoP Classic"
  else:         result = "Unknown"

proc userSelectGameVersion(addon: Addon, options: seq[string]): string {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      let versionName = getVersionName(option)
      if selected == i + 1:
        t.write(16, addon.line + i + 1, bgWhite, fgBlack, &"{i + 1}: {versionName}", resetStyle)
      else:
        t.write(16, addon.line + i + 1, bgBlack, fgWhite, &"{i + 1}: {versionName}", resetStyle)
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