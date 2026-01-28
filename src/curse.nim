import std/enumerate
import std/json
import std/jsonutils
import std/sequtils
import std/strformat
import std/strutils
import std/terminal

import types
import term
import addonHelp

when not defined(release):
  import logger
  debugLog("curse.nim")

proc nameCurse*(addon: Addon, json: JsonNode): string {.gcsafe.} =
  let name = json["fileName"].getStr().replace(addon.version, "").strip(chars = {' ', '_', '-', '.'})
  result = name.split('-')[0]
  if result.endsWith(".zip"):
    result = name.split('_')[0]
  if result.endsWith(".zip"):
    result = name.split('.')[0]

proc versionCurse*(addon: Addon, json: JsonNode): string {.gcsafe.} =
  try:
    result = json["displayName"].getStr()
    result = result.replace(addon.nameCurse(json), "").replace(".zip", "")
    result = result.strip(chars = {' ', '_', '-', '.'})
  except KeyError:
    result = json["dateModified"].getStr()

proc getVersionName(majorVersion, minorVersion: int): string =
  case majorVersion
  of 12: # Midnight
    case minorVersion
    of 0..2: result = "Retail"
    else: result = "Midnight Classic"
  of 11: # The War Within
    case minorVersion
    of 0..2: result = "Retail"
    else: result = "TWW Classic"
  of 10: # Dragonflight
    case minorVersion
    of 0..2: result = "Retail"
    else: result = "Dragonflight Classic"
  of 9: # Shadowlands
    case minorVersion
    of 0..2: result = "Retail"
    else: result = "Shadowlands Classic"
  of 8: # Battle for Azeroth
    case minorVersion
    of 0..3: result = "Retail"
    else: result = "BfA Classic"
  of 7: # Legion
    case minorVersion
    of 0..3: result = "Retail"
    else: result = "Legion Classic"
  of 6: # Warlords of Draenor
    case minorVersion
    of 0..2: result = "Retail"
    else: result = "WoD Classic"
  of 5: # Mists of Pandaria
    case minorVersion
    of 0..4: result = "Retail"
    else: result = "MoP Classic"
  of 4: # Cataclysm
    case minorVersion
    of 0..3: result = "Retail"
    else: result = "Cataclysm Classic"
  of 3: # Wrath of the Lich King
    case minorVersion
    of 0..3: result = "Retail"
    else: result = "WotlK Classic"
  of 2: # The Burning Crusade
    case minorVersion
    of 0..4: result = "Retail"
    else: result = "TBC Classic"
  of 1: # Vanilla
    case minorVersion
    of 0..12: result = "Retail"
    else: result = "Classic (Vanilla 1.15)"
  else:
    result = "Unknown"

proc getVersionName(version: string): string =
  let v = version.split(".")
  let majorVersion = parseInt(v[0])
  let minorVersion = parseInt(v[1])
  getVersionName(majorVersion, minorVersion)

proc extractJsonCurse*(addon: Addon, json: JsonNode): JsonNode {.gcsafe.} =
  var gameVersions: seq[string]
  for data in json["data"]:
    gameVersions.fromJson(data["gameVersions"])
    for version in gameVersions:
      if getVersionName(version) == addon.gameVersion:
        return data
  addon.setAddonState(Failed, &"JSON Error: No game version matches current verion of {addon.gameVersion}.")
  return

proc userSelectGameVersion(addon: Addon, options: seq[string]): string {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      if selected == i + 1:
        t.write(16, addon.line + i + 1, bgWhite, fgBlack, &"{i + 1}: {option}", resetStyle)
      else:
        t.write(16, addon.line + i + 1, bgBlack, fgWhite, &"{i + 1}: {option}", resetStyle)
    let newSelected = handleSelection(options.len, selected)
    if newSelected == selected:
      t.clear(addon.line .. addon.line + options.len)
      return options[selected - 1]
    elif newSelected != -1:
      selected = newSelected

proc chooseJsonCurse*(addon: Addon, json: JsonNode): JsonNode {.gcsafe.} =
  if json["data"].len == 0:
    addon.setAddonState(Failed, "Addon not found in JSON.")
    return
  var gameVersions: seq[string]
  # json["data"] is only so big so if the last update that contains a game version was too long ago we cannot get it
  for data in json["data"]:
    var versions: seq[string]
    versions.fromJson(data["gameVersions"])
    for v in versions:
      gameVersions.addUnique(getVersionName(v))
  if gameVersions.len == 1:
    addon.gameVersion = gameVersions[0]
  else:
    for ver in ["TBC Classic", "Classic (Vanilla 1.15)", "MoP Classic", "Retail"]:
      let idx = gameVersions.find(ver)
      if idx != -1:
        let val = gameVersions[idx]
        gameVersions.delete(idx)
        gameVersions.insert(val, 0)
    addon.gameVersion = addon.userSelectGameVersion(gameVersions)
  for data in json["data"]:
    var tmp: seq[string]
    tmp.fromJson(data["gameVersions"])
    if tmp.anyIt(getVersionName(it) == addon.gameVersion):
      return data
