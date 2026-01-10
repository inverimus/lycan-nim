import std/enumerate
import std/sets
import std/[json, jsonutils]
import std/sequtils
import std/[strformat, strutils]
import std/terminal

import types
import term
import addonHelp

proc nameCurse*(addon: Addon, json: JsonNode): string {.gcsafe.} =
  result = json["fileName"].getStr().split('-')[0]
  if result.endsWith(".zip"):
    result = json["fileName"].getStr().split('_')[0]
  if result.endsWith(".zip"):
    result = json["fileName"].getStr().split('.')[0]

proc versionCurse*(addon: Addon, json: JsonNode): string {.gcsafe.} =
  try:
    result = json["displayName"].getStr()
    if result.endsWith(".zip"):
      result = json["dateModified"].getStr()
  except KeyError:
    result = json["dateModified"].getStr()

proc extractJsonCurse*(addon: Addon, json: JsonNode): JsonNode {.gcsafe.} =
  if addon.gameVersion == "Retail":
    return json["data"][0]
  var gameVersions: seq[string]
  for data in json["data"]:
    gameVersions.fromJson(data["gameVersions"])
    for version in gameVersions:  
      if version.rsplit(".", maxSplit = 1)[0] == addon.gameVersion:
        return data
  addon.setAddonState(Failed, &"JSON Error: No game version matches current verion of {addon.gameVersion}.", 
    &"JSON Error: {addon.getName()}: no game version matches current version of {addon.gameVersion}.")
  return

proc getVersionName(majorVersion, minorVersion: int): string =
  case majorVersion
  of 12:
    case minorVersion
    of 0..2: result = "Midnight"
    else: result = "Midnight Classic"
  of 11:
    case minorVersion
    of 0..2: result = "The War Within"
    else: result = "TWW Classic"
  of 10:
    case minorVersion
    of 0..2: result = "Dragonflight"
    else: result = "Dragonflight Classic"
  of 9:
    case minorVersion
    of 0..2: result = "Shadowlands"
    else: result = "Shadowlands Classic"
  of 8:
    case minorVersion
    of 0..3: result = "Battle for Azeroth"
    else: result = "BfA Classic"
  of 7:
    case minorVersion
    of 0..3: result = "Legion"
    else: result = "Legion Classic"
  of 6:
    case minorVersion
    of 0..2: result = "Warlords of Draenor"
    else: result = "WoD Classic"
  of 5:
    case minorVersion
    of 0..4: result = "Mists of Pandaria"
    else: result = "MoP Classic"
  of 4:
    case minorVersion
    of 0..3: result = "Cataclysm"
    else: result = "Cataclysm Classic"
  of 3:
    case minorVersion
    of 0..3: result = "Wrath of the Lich King"
    else: result = "WotLK Classic"
  of 2:
    case minorVersion
    of 0..4: result = "The Burning Crusade"
    else: result = "TBC Classic"
  of 1:
    case minorVersion
    of 0..12: result = "Vanilla"
    else: result = "Classic"
  else: 
    result = "Unknown"

proc userSelectGameVersion(addon: Addon, options: seq[string]): string {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      var versionName: string
      if option == "Retail":
        versionName = &"Retail"
      else:
        let optionSplit = option.split(".")
        let majorVersion = parseInt(optionSplit[0])
        let minorVersion = parseInt(optionSplit[1])
        versionName = getVersionName(majorVersion, minorVersion)
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

proc chooseJsonCurse*(addon: Addon, json: JsonNode): JsonNode {.gcsafe.} =
  if json["data"].len == 0:
    addon.setAddonState(Failed, "Addon not found.", "Addon not found.")
    return
  var gameVersionsSet: OrderedSet[string]
  for data in json["data"]:
    var tmp: seq[string]
    tmp.fromJson(data["gameVersions"])
    for item in tmp:
      let s = item.split(".")
      let major = s[0]
      let minor = s[1]
      if not gameVersionsSet.anyIt(it.split(".")[0] == major):
        gameVersionsSet.incl(&"{major}.{minor}")
  var gameVersions = gameVersionsSet.toSeq()
  gameVersions.insert("Retail", 0)
  var selectedVersion: string
  if gameVersions.len == 1:
    selectedVersion = gameVersions[0]
  else:
    selectedVersion = addon.userSelectGameVersion(gameVersions)
  addon.gameVersion = selectedVersion
  if selectedVersion == "Retail":
    return json["data"][0]
  for data in json["data"]:
    var tmp: seq[string]
    tmp.fromJson(data["gameVersions"])
    if tmp.anyIt(it.rsplit(".", maxSplit = 1)[0] == selectedVersion):
      return data