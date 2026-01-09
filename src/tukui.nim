import std/httpclient
import std/json
import std/options
import std/os
import std/[strformat, strutils]
import std/times

import config
import types
import logger

import addonBase

proc newAddon*(slug: string): AddonTukui =
  result = new(AddonTukui)
  result.slug = slug

proc toJsonHook*(a: AddonTukui): JsonNode =
  result = newJObject()
  result["slug"] = %a.slug
  result["name"] = %a.name
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["version"] = %a.version
  result["gameVersion"] = %a.gameVersion
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc setName*(addon: AddonTukui, json: JsonNode, name: string = "none") {.gcsafe.} =
  if addon.state == Failed: return
  addon.name = json["name"].getStr()

proc getName*(addon: AddonTukui): string =
  if addon.overrideName.isSome:
    return addon.overrideName.get
  return addon.name

proc setVersion*(addon: AddonTukui, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.version = json["version"].getStr()
  
proc getLatestUrl(addon: AddonTukui): string {.gcsafe.} =
  "https://api.tukui.org/v1/addons/"

proc setDownloadUrl*(addon: AddonTukui, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.downloadUrl = json["url"].getStr()
  
proc extractJson*(addon: AddonTukui): JsonNode =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  try:
    json = parseJson(response.body)
  except Exception as e:
    addon.setAddonState(Failed, "JSON parsing error.", &"{addon.getName()}: JSON parsing error", e)
  for node in json:
    if node["slug"].getStr() == addon.slug:
      return node
  addon.setAddonState(Failed, "JSON Error: Addon not found.", &"{addon.getName()}: JSON error, addon not found.")