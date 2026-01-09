import std/json
import std/options
import std/strformat
import std/times

import types

proc newAddon*(owner, name, branch: string): AddonGithubRepo =
  result = new(AddonGithubRepo)
  result.owner = owner
  result.name = name
  result.branch = branch

proc toJsonHook*(a: AddonGithubRepo): JsonNode =
  result = newJObject()
  result["owner"] = %a.owner
  result["name"] = %a.name
  result["branch"] = %a.branch
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["version"] = %a.version
  result["gameVersion"] = %a.gameVersion
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc setName*(addon: AddonGithubRepo, json: JsonNode, name: string = "none") {.gcsafe.} =
  discard

proc getName*(addon: AddonGithubRepo): string =
  if addon.overrideName.isSome:
    return addon.overrideName.get
  return addon.name

proc setVersion*(addon: AddonGithubRepo, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  addon.version = json["sha"].getStr()
  
proc getLatestUrl*(addon: AddonGithubRepo): string {.gcsafe.} =
  &"https://api.github.com/repos/{addon.owner}/{addon.name}/commits/{addon.branch}"

proc setDownloadUrl*(addon: AddonGithubRepo, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.downloadUrl = &"https://www.github.com/{addon.owner}/{addon.name}/archive/refs/heads/{addon.branch}.zip"