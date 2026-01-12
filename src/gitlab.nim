import std/enumerate
import std/json
import std/strformat
import std/strutils
import std/sugar
import std/terminal

import types
import term
import addonHelp

proc setDownloadUrlGitlab*(addon: Addon, json: JsonNode) {.gcsafe.} =
  let sources = json[0]["assets"]["sources"]
  # If gameVersion is empty, choose the shortest zip file
  if addon.gameVersion.isEmptyOrWhitespace:
    let urls = collect(
      for source in sources:
        if source["format"].getStr() == "zip":
          source["url"].getStr()
    )
    var shortest = urls[0]
    for url in urls[1..^1]:
      if url.len < shortest.len:
        shortest = url
    addon.downloadUrl = shortest
    return
  # if gameVersion is not empty, choose the zip file that contains it
  for source in sources:
    if source["content_type"].getStr() == "zip":
      let url = source["url"].getStr()
      if url.contains(addon.gameVersion):
        addon.downloadUrl = url
        return
  # if no zip file contains the gameVersion and it is not empty, we fail and ask the user to reinstall
  if not addon.gameVersion.isEmptyOrWhitespace:
    addon.setAddonState(Failed, &"No matching zip file matching: {addon.gameVersion}. Try reinstalling as file names might have changed.", 
      &"{addon.getName()}: no matching zip file for {addon.gameVersion}.")

proc userSelectDownloadGitlab(addon: Addon, options: seq[string]): int {.gcsafe.} =
  let t = addon.config.term
  var selected = 1
  for _ in 0 ..< options.len:
    t.addLine()
  while true:
    for (i, option) in enumerate(options):
      let name = option.rsplit("/", maxsplit=1)[1]
      if selected == i + 1:
        t.write(16, addon.line + i + 1, false, bgWhite, fgBlack, &"{i + 1}: {name}", resetStyle)
      else:
        t.write(16, addon.line + i + 1, false, bgBlack, fgWhite, &"{i + 1}: {name}", resetStyle)
    let newSelected = handleSelection(options.len, selected)
    if newSelected == selected:
      t.clear(addon.line .. addon.line + options.len)
      return selected - 1
    elif newSelected != -1:
      selected = newSelected

proc chooseDownloadUrlGitlab*(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  var options: seq[string]
  for source in json[0]["assets"]["sources"]:
    if source["format"].getStr() == "zip":
      options.add(source["url"].getStr())
  case options.len
  of 0:
    addon.setAddonState(Failed, "No zip file found", &"{addon.getName()}: no zip file found")
    return
  of 1:
    addon.downloadUrl = options[0]
    return
  else:
    let i = addon.userSelectDownloadGitlab(options)
    addon.gameVersion = extractVersionFromDifferences(options, i)
    addon.downloadUrl = options[i]