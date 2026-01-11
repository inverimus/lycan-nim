import std/enumerate
import std/httpclient
import std/json
import std/options
import std/os
import std/re
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/times

import config
import types
import term
import messages
import addonHelp
import files

import github
import curse
import wago

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

proc setName(addon: Addon, json: JsonNode, name: string = "none") {.gcsafe.} =
  if addon.state == Failed: return
  case addon.kind
  of Curse:
    addon.name = addon.nameCurse(json)
  of Github, GithubRepo, Gitlab:
    addon.name = addon.project.split('/')[^1]
  of Tukui:
    addon.name = json["name"].getStr()
  of Wowint:
    addon.name = json[0]["UIName"].getStr()
  of Wago:
    addon.name = json["props"]["addon"]["display_name"].getStr()

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
    addon.version = json[0]["UIVersion"].getStr()
  of Wago:
    for data in json["props"]["releases"]["data"]:
      if data["supported_" & addon.gameVersion & "_patches"].len > 0:
        addon.version = data["label"].getStr()
        return

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
    for source in json[0]["assets"]["sources"]:
      if source["format"].getStr() == "zip":
        addon.downloadUrl = source["url"].getStr()
  of Tukui:
    addon.downloadUrl = json["url"].getStr()
  of Wowint:
    addon.downloadUrl = json[0]["UIDownload"].getStr()
  of Wago:
    if addon.action == Install:
      addon.chooseDownloadUrlWago(json)
    else:
      addon.setDownloadUrlWago(json)

proc getLatest(addon: Addon): Response {.gcsafe.} =
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
        addon.setAddonState(Failed, &"No response retrieving latest addon info: {addon.getLatestUrl()}",
        &"{addon.getName()}: Get latest JSON no response.", e)
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
        addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
        &"{addon.getName()}: Get latest JSON bad response: {response.status}")
      return
    retryCount += 1
    sleep(100)

proc extractJson(addon: Addon): JsonNode {.gcsafe.} =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  case addon.kind
  of Wago:
    let pattern = re("""data-page="({.+?})"""")
    var matches: array[1, string]
    let found = find(cstring(response.body), pattern, matches, 0, len(response.body))
    if found != -1:
      let clean = matches[0].replace("&quot;", "\"").replace("\\/", "/").replace("&amp;", "&")
      json = parseJson(clean)
  else:
    try:
      json = parseJson(response.body)
    except Exception as e:
      addon.setAddonState(Failed, "JSON parsing error.", &"{addon.getName()}: JSON parsing error", e)
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
    addon.setAddonState(Failed, "JSON Error: Addon not found.", &"{addon.getName()}: JSON error, addon not found.")
    return
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
    addon.createBackup()
    addon.moveDirs()
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
  addon.createBackup()
  addon.moveDirs()
  addon.setAddonState(FinishedInstalled)

proc uninstall(addon: Addon) =
  addon.removeAddonFiles(addon.config.installDir, removeAllBackups = true)
  addon.setAddonState(Removed)

proc pin(addon: Addon) =
  addon.pinned = true
  addon.setAddonState(Pinned)

proc unpin(addon: Addon) =
  addon.pinned = false
  addon.setAddonState(Unpinned)

proc list*(addons: seq[Addon]) =
  if addons.len == 0:
    echo "No addons installed"
    quit()
  for line, addon in enumerate(addons):
    addon.state = List
    addon.line = line
  let 
    t = configData.term
    nameSpace = addons[addons.map(a => a.getName().len).maxIndex()].getName().len + 2
    versionSpace = addons[addons.map(a => a.getVersion().len).maxIndex()].getVersion().len + 2
  for addon in addons:
    addon.stateMessage(nameSpace, versionSpace)
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

proc setOverrideName(addon: Addon) =
  addon.setAddonState(Renamed)

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
    addon.setOverrideName()
  else: discard
  addon.state = if addon.state == Failed: DoneFailed else: Done
  addonChannel.send(addon)