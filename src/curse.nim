import std/enumerate
import std/sets
import std/httpclient
import std/[json, jsonutils]
import std/options
import std/os
import std/sequtils
import std/[strformat, strutils]
import std/terminal
import std/times

import config
import types
import term
import logger

import addonBase

proc toJsonHook*(a: AddonCurse): JsonNode =
  result = newJObject()
  result["curseId"] = %a.curseId
  result["name"] = %a.name
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["version"] = %a.version
  result["gameVersion"] = %a.gameVersion
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc setName*(addon: AddonCurse, json: JsonNode, name: string = "none") {.gcsafe.} =
  if addon.state == Failed: return
  addon.name = json["fileName"].getStr().split('-')[0]
  if addon.name.endsWith(".zip"):
    addon.name = json["fileName"].getStr().split('_')[0]
  if addon.name.endsWith(".zip"):
    addon.name = json["fileName"].getStr().split('.')[0]

proc getName*(addon: AddonCurse): string =
  if addon.overrideName.isSome:
    return addon.overrideName.get
  if addon.name.isEmptyOrWhitespace:
    return "Curse:" & addon.curseId
  return addon.name

proc setVersion*(addon: AddonCurse, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  try:
    addon.version = json["displayName"].getStr()
    if addon.version.endsWith(".zip"):
      addon.version = json["dateModified"].getStr()  
  except KeyError:
    addon.version = json["dateModified"].getStr()

proc getLatestUrl*(addon: AddonCurse): string {.gcsafe.} =
  &"https://www.curseforge.com/api/v1/mods/{addon.curseId}/files"
  
proc setDownloadUrl*(addon: AddonCurse, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  let id = $json["id"].getInt()
  addon.downloadUrl = &"https://www.curseforge.com/api/v1/mods/{addon.curseId}/files/{id}/download"
  
proc download*(addon: AddonCurse, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  var headers = newHttpHeaders()
  let client = newHttpClient(headers = headers)
  var response: Response
  var retryCount = 0
  while true:
    try:
      response = client.get(addon.downloadUrl)
    except Exception as e:
      if retryCount > 4:
        addon.setAddonState(Failed, &"Error while trying to download: {addon.getLatestUrl()}",
          &"{addon.getName()}: download failed for {addon.getLatestUrl()}", e)
        return
      retryCount += 1
      sleep(100)
      continue
    if response.status.contains("200"):
      break
    if retryCount > 4:
      addon.setAddonState(Failed, &"Bad response downloading {response.status}: {addon.getLatestUrl()}",
        &"{addon.getName()}: download failed. Response code {response.status} from {addon.getLatestUrl()}")
      return
    retryCount += 1
    sleep(100)
  addon.filename = addon.config.tempDir / json["fileName"].getStr()
  var file: File
  try:
    file = open(addon.filename, fmWrite)
  except Exception as e:
    addon.setAddonState(Failed, &"Problem opening file {addon.filename}", &"{addon.getName()}: download failed, error opening file {addon.filename}", e)
    return
  try:
    system.write(file, response.body)
  except Exception as e:
    addon.setAddonState(Failed, &"Problem encountered while downloading.", &"{addon.getName()}: download failed, error writing {addon.filename}", e)
  file.close()

proc userSelectGameVersionCurse(addon: AddonCurse, options: seq[string]): string {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      var version: string
      if option == "Retail":
        version = &"Retail ({RETAIL_VERSION})"
      else:
        let optionSplit = option.split(".")
        let majorVersion = parseInt(optionSplit[0])
        let minorVersion = parseInt(optionSplit[1])
        case majorVersion
        of 12:
          case minorVersion
          of 0..2: version = "Midnight"
          else: version = "Midnight Classic"
        of 11:
          case minorVersion
          of 0..2: version = "The War Within"
          else: version = "TWW Classic"
        of 10:
          case minorVersion
          of 0..2: version = "Dragonflight"
          else: version = "Dragonflight Classic"
        of 9:
          case minorVersion
          of 0..2: version = "Shadowlands"
          else: version = "Shadowlands Classic"
        of 8:
          case minorVersion
          of 0..3: version = "Battle for Azeroth"
          else: version = "BfA Classic"
        of 7:
          case minorVersion
          of 0..3: version = "Legion"
          else: version = "Legion Classic"
        of 6:
          case minorVersion
          of 0..2: version = "Warlords of Draenor"
          else: version = "WoD Classic"
        of 5:
          case minorVersion
          of 0..4: version = "Mists of Pandaria"
          else: version = "MoP Classic"
        of 4:
          case minorVersion
          of 0..3: version = "Cataclysm"
          else: version = "Cataclysm Classic"
        of 3:
          case minorVersion
          of 0..3: version = "Wrath of the Lich King"
          else: version = "WotLK Classic"
        of 2:
          case minorVersion
          of 0..4: version = "The Burning Crusade"
          else: version = "TBC Classic"
        of 1:
          case minorVersion
          of 0..12: version = "Vanilla"
          else: version = "Classic"
        else: discard
      if selected == i + 1:
        t.write(16, addon.line + i + 1, false, bgWhite, fgBlack, &"{i + 1}: {version}", resetStyle)
      else:
        t.write(16, addon.line + i + 1, false, bgBlack, fgWhite, &"{i + 1}: {version}", resetStyle)
    let newSelected = handleSelection(options.len, selected)
    if newSelected == selected:
      t.clear(addon.line .. addon.line + options.len)
      return options[selected - 1]
    elif newSelected != -1:
      selected = newSelected

proc extractJson*(addon: AddonCurse): JsonNode =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  try:
    json = parseJson(response.body)
  except Exception as e:
    addon.setAddonState(Failed, "JSON parsing error.", &"{addon.getName()}: JSON parsing error", e)
  if json["data"].len == 0:
    addon.setAddonState(Failed, "Addon not found.", "Addon not found.")
    return
  var gameVersionsSet: OrderedSet[string]
  for data in json["data"]:
    var tmp: seq[string]
    tmp.fromJson(data["gameVersions"])
    for item in tmp:
      gameVersionsSet.incl(item.rsplit(".", maxSplit = 1)[0])
  var gameVersions = gameVersionsSet.toSeq()
  gameVersions.insert("Retail", 0)
  var selectedVersion = addon.userSelectGameVersionCurse(gameVersions)
  addon.gameVersion = selectedVersion
  for data in json["data"]:
    var tmp: seq[string]
    tmp.fromJson(data["gameVersions"])
    if selectedVersion == "Retail":
      if tmp.anyIt(it.split(".")[0] == RETAIL_VERSION):
        return data
    else:
      if tmp.anyIt(it.rsplit(".", maxSplit = 1)[0] == selectedVersion):
        return data