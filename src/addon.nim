import std/enumerate
import std/httpclient
import std/json
import std/options
import std/os
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/terminal
import std/times

import config
import types
import term
import messages
import addonHelp
import files

import github
import gitlab
import curse
import wago
import zremax
import legacy

when not defined(release):
  import logger
  debugLog("addon.nim")


proc `==`*(a, b: Addon): bool {.inline.} =
  a.project.toLower() == b.project.toLower()

proc newAddon*(project: string, kind: AddonKind, branch: Option[string] = none(string)): Addon =
  result = new(Addon)
  result.project = project
  result.kind = kind
  result.branch = branch

proc assignIds*(addons: seq[Addon]) =
  var ids: set[int16]
  addons.apply((a: Addon) => ids.incl(a.id))
  var id: int16 = 1
  for a in addons:
    if a.id == 0:
      while id in ids: id += 1
      a.id = id
      incl(ids, id)

proc toJsonHook*(a: Addon): JsonNode =
  result = newJObject()
  result["project"] = %a.project
  if a.branch.isSome: result["branch"] = %a.branch.get
  result["name"] = %a.name
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["kind"] = %a.kind
  result["version"] = %a.version
  result["gameVersion"] = %a.gameVersion
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc setName(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  case addon.kind
  of Curse:  addon.name = addon.nameCurse(json)
  of Tukui:  addon.name = json["name"].getStr()
  of Wowint: addon.name = json["UIName"].getStr()
  of Wago:   addon.name = json["props"]["addon"]["display_name"].getStr()
  of Zremax: addon.name = json["name"].getStr()
  of Github, GithubRepo, Gitlab, Legacy: 
    addon.name = addon.project.split('/')[^1]

proc setVersion(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  case addon.kind
  of Curse:
    addon.version = addon.versionCurse(json)
  of Github:
    let v = json["tag_name"].getStr()
    addon.version = if not v.isEmptyOrWhitespace: v else: json["name"].getStr()
  of GithubRepo:
    addon.version = json["sha"].getStr()
  of Gitlab:
    let v = json[0]["tag_name"].getStr()
    addon.version = if not v.isEmptyOrWhitespace: v else: json[0]["name"].getStr()
  of Tukui:
    addon.version = json["version"].getStr()
  of Wowint:
    addon.version = json["UIVersion"].getStr()
  of Wago:
    addon.version = addon.versionWago(json)
  of Zremax:
    addon.version = json["version"].getStr()
  of Legacy:
    addon.version = "N/A"

proc setDownloadUrl(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  case addon.kind
  of Curse:
    let id = $json["id"].getInt()
    addon.downloadUrl = &"https://www.curseforge.com/api/v1/mods/{addon.project}/files/{id}/download"
  of Github:
    if addon.action == Install:
      addon.chooseDownloadUrlGithub(json)
    else:
      addon.setDownloadUrlGithub(json)
  of GithubRepo:
    addon.downloadUrl = &"https://www.github.com/{addon.project}/archive/refs/heads/{addon.branch.get}.zip"
  of Gitlab:
    if addon.action == Install:
      addon.chooseDownloadUrlGitlab(json)
    else:
      addon.setDownloadUrlGitlab(json)
  of Tukui:
    addon.downloadUrl = json["url"].getStr()
  of Wowint:
    addon.downloadUrl = json["UIDownload"].getStr()
  of Wago:
    if addon.action == Install:
      addon.chooseDownloadUrlWago(json)
    else:
      addon.setDownloadUrlWago(json)
  of Zremax:
    if addon.action == Install:
      addon.chooseDownloadUrlZremax(json)
    addon.downloadUrl = &"https://zremaxcom.s3.eu-north-1.amazonaws.com/addons/addons/{addon.project}-{addon.gameVersion}.zip"
  of Legacy:
    addon.downloadUrl = json["downloadUrl"].getStr()

proc getLatest(addon: Addon): Response {.gcsafe.} =
  if addon.state == Failed: return
  addon.setAddonState(Checking, &"Checking: {addon.getName()} getting latest version information")
  let url = addon.getLatestUrl()
  var headers = newHttpHeaders()
  if not addon.config.githubToken.isEmptyOrWhitespace:
    case addon.kind
    of Github, GithubRepo:
      headers["Authorization"] = &"Bearer {addon.config.githubToken}"
    else:
      discard
  var retryCount = 0
  let client = newHttpClient(headers = headers)
  var response: Response
  while true:
    try:
      response = client.get(url)
    except Exception as e:
      if retryCount > 4:
        addon.setAddonState(Failed, &"No response retrieving latest addon info: {addon.getLatestUrl()}", e)
        return
      retryCount += 1
      sleep(100)
      continue
    if response.status.contains("200"):
      return response
    if retryCount > 4:
      if addon.kind == Github and response.status.contains("404"):
        addon.fallbackToGithubRepo(client, response)
        return addon.getLatest()
      else:
        addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}")
      return
    retryCount += 1
    sleep(100)

proc extractJson(addon: Addon): JsonNode {.gcsafe.} =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  case addon.kind
  of Legacy:
    json = extractJsonLegacy(response)
  of Zremax:
    json = extractJsonZremax(response)
  of Wago:
    json = extractJsonWago(response)
  else:
    try:
      json = parseJson(response.body)
    except Exception as e:
      addon.setAddonState(Failed, "JSON parsing error.", e)
  case addon.kind:
  of Curse:
    if addon.action == Install:
      json = addon.chooseJsonCurse(json)
    else:
      json = addon.extractJsonCurse(json)
  of Tukui:
    for node in json:
      if node["slug"].getStr() == addon.project:
        return node
    addon.setAddonState(Failed, "JSON Error: Addon not found.")
    return
  of Github:
    try:
      if json["message"].getStr() == "Not Found":
        addon.setAddonState(Failed, "JSON Error: Addon not found.")
    except KeyError:
      discard
  of Wowint:
    return json[0]
  else:
    discard
  return json

proc update(addon: Addon) {.gcsafe.} =
  let json = addon.extractJson()
  addon.setAddonState(Parsing)
  addon.setVersion(json)
  if addon.pinned:
    addon.setAddonState(FinishedPinned)
    return
  if addon.action == Reinstall or addon.version != addon.startVersion:
    addon.time = now()
    addon.setDownloadUrl(json)
    addon.setName(json)
    addon.setAddonState(Downloading)
    addon.download(json)
    addon.setAddonState(Installing)
    addon.unzip()
    if addon.config.backupEnabled:
      addon.createBackup()
    addon.moveDirs()
    if addon.action == Reinstall:
      addon.setAddonState(FinishedInstalled)
    else:
      addon.setAddonState(FinishedUpdated)
  else:
    addon.setAddonState(FinishedUpToDate)

proc install(addon: Addon) {.gcsafe.} =
  let json = addon.extractJson()
  addon.setAddonState(Parsing)
  addon.setDownloadUrl(json)
  addon.setVersion(json)
  addon.time = now()
  addon.setName(json)
  addon.setAddonState(Downloading)
  addon.download(json)
  addon.setAddonState(Installing)
  addon.unzip()
  if addon.config.backupEnabled:
    addon.createBackup()
  addon.moveDirs()
  addon.setAddonState(FinishedInstalled)

proc uninstall(addon: Addon) =
  addon.removeAddonFiles(removeBackups = true)
  addon.setAddonState(Removed)

proc pin(addon: Addon) =
  addon.pinned = true
  addon.setAddonState(Pinned)

proc unpin(addon: Addon) =
  addon.pinned = false
  addon.setAddonState(Unpinned)

proc list*(addons: seq[Addon], args: seq[string] = @[]) =
  let t = configData.term
  if addons.len == 0:
    t.write(2, fgWhite, "No addons installed\n", resetStyle)
    quit()
  for line, addon in enumerate(addons):
    addon.state = List
    addon.line = line
  let 
    nameSpace = addons[addons.mapIt(it.getName().len).maxIndex()].getName().len + 2
    versionSpace = addons[addons.mapIt(it.getVersion().len).maxIndex()].getVersion().len + 2
  var full: bool = false
  if args.len > 0:
    full = args[0] == "all"
  for addon in addons:
    addon.stateMessage(nameSpace, versionSpace, full)
  t.addLine()
  quit()

proc restore*(addon: Addon) =
  addon.setAddonState(Restoring)
  var backups = getBackupFiles(addon)
  if len(backups) < 2:
    addon.setAddonState(NoBackup)
    return
  let filename = backups[0]
  let start = filename.find("&V=") + 3
  addon.filename = filename
  addon.startVersion = addon.version
  addon.version = filename[start .. ^5] #exclude .zip
  addon.time = getFileInfo(filename).creationTime.local()
  addon.unzip()
  addon.moveDirs()
  addon.setAddonState(Restored)
  if addon.state != Failed:
    removeFile(backups[1])

proc workQueue*(addon: Addon) {.thread.} =
  case addon.action
  of Update, Reinstall:
    addon.update()
  of Install: 
    addon.install()
  of Remove: 
    addon.uninstall()
  of Pin:
    addon.pin()
  of Unpin:
    addon.unpin()
  of Restore:
    addon.restore()
  of Name:
    addon.setAddonState(Renamed)
  else: discard
  addon.state = if addon.state == Failed: DoneFailed else: Done
  addonChannel.send(addon)