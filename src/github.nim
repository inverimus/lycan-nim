import std/enumerate
import std/httpclient
import std/json
import std/options
import std/os
import std/sequtils
import std/[strformat, strutils]
import std/sugar
import std/terminal
import std/times

import types
import term
import logger
import addonBase

proc toJsonHook*(a: AddonGithub): JsonNode =
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

proc setName*(addon: AddonGithub, json: JsonNode, name: string = "none") {.gcsafe.} =
  discard

proc getName*(addon: AddonGithub): string =
  if addon.overrideName.isSome:
    return addon.overrideName.get
  return addon.name

proc setVersion*(addon: AddonGithub, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  let v = json["tag_name"].getStr()
  addon.version = if not v.isEmptyOrWhitespace: v else: json["name"].getStr()

proc getLatestUrl*(addon: AddonGithub): string {.gcsafe.} =
  &"https://api.github.com/repos/{addon.owner}/{addon.name}/releases/latest"
  
proc userSelectDownloadGithub(addon: AddonGithub, options: seq[string]): int {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      if selected == i + 1:
        t.write(16, addon.line + i + 1, false, bgWhite, fgBlack, &"{i + 1}: {option}", resetStyle)
      else:
        t.write(16, addon.line + i + 1, false, bgBlack, fgWhite, &"{i + 1}: {option}", resetStyle)
    let newSelected = handleSelection(options.len, selected)
    if newSelected == selected:
      t.clear(addon.line .. addon.line + options.len)
      return selected
    elif newSelected != -1:
      selected = newSelected

proc findCommonPrefix(strings: seq[string]): string =
  var shortest = strings[0]
  for s in strings[1..^1]:
    if s.len < shortest.len:
      shortest = s
  for i in 1 .. shortest.len:
    let prefix = shortest[0 .. i]
    if strings.any(s => not s.startsWith(prefix)):
      return prefix[0 .. i - 1]

proc findCommonSuffix(strings: seq[string]): string =
  var longest = strings[0]
  for s in strings[1..^1]:
    if s.len > longest.len:
      longest = s
  for i in 2 .. longest.len:
    let suffix = longest[^i .. ^1]
    if strings.any(s => not s.endsWith(suffix)):
      return suffix[^(i - 1) .. ^1]

proc extractVersionFromDifferences(names: seq[string], selectedIndex: int): string =
  let commonPrefix = findCommonPrefix(names)
  let commonSuffix = findCommonSuffix(names)
  
  let selected = names[selectedIndex]
  let version = selected[commonPrefix.len .. selected.len - commonSuffix.len - 1]
  result = version.strip(chars = {'-', '.', '_', ' '})

proc setDownloadUrl*(addon: AddonGithub, json: JsonNode) =
  if addon.state == Failed: return
  let assets = json["assets"]
  var options: seq[string]
  for asset in assets:
    if asset["content_type"].getStr() != "application/zip":
      continue
    let name = asset["name"].getStr()
    options.add(name)
  case options.len
  of 0:
    addon.gameVersion = "zipball"
    addon.downloadUrl = json["zipball_url"].getStr()
    return
  of 1:
    addon.downloadUrl = assets[0]["browser_download_url"].getStr()
    return
  else:
    let i = addon.userSelectDownloadGithub(options)
    addon.gameVersion = extractVersionFromDifferences(options, i)
    addon.downloadUrl = assets[i]["browser_download_url"].getStr()

proc getLatest*(addon: AddonGithub): Response {.gcsafe.} =
  addon.setAddonState(Checking, &"Checking: {addon.getName()} getting latest version information")
  let url = addon.getLatestUrl()
  var headers = newHttpHeaders()
  if not addon.config.githubToken.isEmptyOrWhitespace:
    headers["Authorization"] = &"Bearer {addon.config.githubToken}"
  var retryCount = 0
  let client = newHttpClient(headers = headers)
  var response: Response
  while true:
    try:
      response = client.get(url)
    except Exception as e:
      if retryCount > 4:
        addon.setAddonState(Failed, &"No response retrieving latest addon info: {addon.getLatestUrl()}",
        &"{addon.getName()}: Get latest JSON no response.", e)
        return
      retryCount += 1
      sleep(100)
      continue
    if response.status.contains("200"):
      return response
    if retryCount > 4:
      if response.status.contains("404"):
        log(&"{addon.getName()}: Got {response.status}: {addon.getLatestUrl()} - This usually means no releases are available so switching to trying main/master branch", Warning)
        let resp = client.get(&"https://api.github.com/repos/{addon.owner}/{addon.repo}/branches")
        let branches = parseJson(resp.body)
        let names = collect(for item in branches: item["name"].getStr())
        var branch: string
        if names.contains("master"):
          branch = "master"
        elif names.contains("main"):
          branch = "main"
        else:
          log(&"{addon.getName()}: No branch named master or main avaialable", Warning)
          addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
          &"{addon.getName()}: Get latest JSON bad response: {response.status}")
        # Change to AddonGithubRepo
        return addon.getLatest()
      else:
        addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
        &"{addon.getName()}: Get latest JSON bad response: {response.status}")
      return
    retryCount += 1
    sleep(100)