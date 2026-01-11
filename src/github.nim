import std/enumerate
import std/httpclient
import std/json
import std/options
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/terminal

import types
import term
import logger
import addonHelp

proc setDownloadUrlGithub*(addon: Addon, json: JsonNode) {.gcsafe.} =
  let assets = json["assets"]
  # if gameVersion is zipball, use the zipball_url
  if addon.gameVersion == "zipball":
    addon.downloadUrl = json["zipball_url"].getStr()
    return
  # If gameVersion is empty, choose the shortest zip file
  if addon.gameVersion.isEmptyOrWhitespace:
    let names = collect(
      for (i, asset) in enumerate(assets):
        if asset["content_type"].getStr() != "application/zip":
          continue
        (i, asset["name"].getStr())
    )
    var shortest = names[0]
    for name in names[1..^1]:
      if name[1].len < shortest[1].len:
        shortest = name
    addon.downloadUrl = assets[shortest[0]]["browser_download_url"].getStr()
    return
  # if gameVersion is not empty, choose the zip file that contains it
  for asset in assets:
    if asset["content_type"].getStr() != "application/zip":
      continue
    let name = asset["name"].getStr()
    if name.contains(addon.gameVersion):
      addon.downloadUrl = asset["browser_download_url"].getStr()
      return
  # if no zip file contains the gameVersion and it is not empty, we fail and ask the user to reinstall
  if not addon.gameVersion.isEmptyOrWhitespace:
    addon.setAddonState(Failed, &"No matching zip file matching: {addon.gameVersion}. Try reinstalling as file names might have changed.", 
      &"{addon.getName()}: no matching zip file for {addon.gameVersion}.")
        
proc userSelectDownloadGithub(addon: Addon, options: seq[string]): int {.gcsafe.} =
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
      return selected - 1
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

proc chooseDownloadUrlGithub*(addon: Addon, json: JsonNode) {.gcsafe.} =
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

proc fallbackToGithubRepo*(addon: Addon, client: HttpClient, response: Response) {.gcsafe.} =
    log(&"{addon.getName()}: Got {response.status}: {addon.getLatestUrl()} - This usually means no releases are available so switching to trying main/master branch", Warning)
    let resp = client.get(&"https://api.github.com/repos/{addon.project}/branches")
    let branches = parseJson(resp.body)
    let names = collect(for item in branches: item["name"].getStr())
    if names.contains("master"):
      addon.branch = some("master")
    elif names.contains("main"):
      addon.branch = some("main")
    else:
      log(&"{addon.getName()}: No branch named master or main avaialable", Warning)
      addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
      &"{addon.getName()}: Get latest JSON bad response: {response.status}")
    addon.kind = GithubRepo