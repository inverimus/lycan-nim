import std/json
import std/options
import std/[strformat, strutils]
import std/times

import types

proc newAddon*(owner, name: string): AddonGitlab =
  result = new(AddonGitlab)
  result.owner = owner
  result.name = name

proc toJsonHook*(a: AddonGitlab): JsonNode =
  result = newJObject()
  result["owner"] = %a.owner
  result["name"] = %a.name
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["version"] = %a.version
  result["gameVersion"] = %a.gameVersion
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc setName*(addon: AddonGitlab, json: JsonNode, name: string = "none") {.gcsafe.} =
  discard

proc getName*(addon: AddonGitlab): string =
  if addon.overrideName.isSome:
    return addon.overrideName.get
  return addon.name

proc setVersion*(addon: AddonGitlab, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  let v = json[0]["tag_name"].getStr()
  addon.version = if not v.isEmptyOrWhitespace: v else: json[0]["name"].getStr()

proc getLatestUrl*(addon: AddonGitlab): string {.gcsafe.} =
  &"https://gitlab.com/api/v4/projects/{addon.owner}%2F{addon.name}/releases"

proc setDownloadUrl*(addon: AddonGitlab, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return  
  for source in json[0]["assets"]["sources"]:
    if source["format"].getStr() == "zip":
      addon.downloadUrl = source["url"].getStr()