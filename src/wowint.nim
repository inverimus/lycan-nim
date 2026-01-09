import std/sets
import std/httpclient
import std/json
import std/options
import std/os
import std/[strformat, strutils]
import std/times

import types

proc `==`*(a, b: Addon): bool {.inline.} =
  a.project.toLower() == b.project.toLower()

proc newAddon*(projectId: string): AddonWowint =
  result = new(AddonWowint)
  result.projectId = projectId

proc toJsonHook*(a: AddonWowint): JsonNode =
  result = newJObject()
  result["projectId"] = %a.projectId
  result["name"] = %a.name
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["version"] = %a.version
  result["gameVersion"] = %a.gameVersion
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc setName*(addon: AddonWowint, json: JsonNode, name: string = "none") {.gcsafe.} =
  if addon.state == Failed: return
  addon.name = json[0]["UIName"].getStr()

proc getName*(addon: AddonWowint): string =
  if addon.overrideName.isSome:
    return addon.overrideName.get
  if addon.name.isEmptyOrWhitespace:
    return "Wowint:" & addon.projectId
  return addon.name

proc setVersion*(addon: AddonWowint, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  addon.version = json[0]["UIVersion"].getStr()

proc getLatestUrl*(addon: AddonWowint): string {.gcsafe.} =
  &"https://api.mmoui.com/v3/game/WOW/filedetails/{addon.projectId}.json"

proc setDownloadUrl*(addon: AddonWowint, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.downloadUrl = json[0]["UIDownload"].getStr()