import std/algorithm
import std/enumerate
import std/httpclient
import std/[json, jsonutils]
import std/options
import std/os
import std/re
import std/sequtils
import std/[strformat, strutils]
import std/sugar
import std/times

import zippy/ziparchives

import config
import types
import term
import logger
import messages

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
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc writeAddons*(addons: var seq[Addon]) =
  if not configData.addonJsonFile.isEmptyOrWhitespace:
    addons.sort((a, z) => int(a.name.toLower() > z.name.toLower()))
    let addonsJson = addons.toJson(ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
    try:
      writeFile(configData.addonJsonFile, pretty(addonsJson))
      log(&"Installed addons file saved: {configData.addonJsonFile}", Info)
    except Exception as e:
      log(&"Fatal error writing installed addons file: {configData.addonJsonFile}", Fatal, e)

proc setAddonState(addon: Addon, state: AddonState) {.gcsafe.} =
  if addon.state != Failed:
    addon.state = state
  let loggedMsg = case state
  of Checking:          &"{addon.getName()}: Retrieving latest JSON"
  of Parsing:           &"{addon.getName()}: Parsing latest JSON"
  of Downloading:       &"{addon.getName()}: Downloading latest release"
  of Installing:        &"{addon.getName()}: Installing"
  of FinishedInstalled: &"{addon.getName()}: Finished install"
  of FinishedUpdated:   &"{addon.getName()}: Finished installing update"
  of FinishedPinned:    &"{addon.getName()}: Addon pinned, no update requested"
  of FinishedUpToDate:  &"{addon.getName()}: Finished, already up to date"
  of Restoring:         &"{addon.getName()}: Restoring to {addon.getVersion()}"
  of Restored:          &"{addon.getName()}: Finished restore to {addon.getVersion()}"
  of Pinned:            &"{addon.getName()}: Addon pinned to version {addon.getVersion()}"
  of Unpinned:          &"{addon.getName()}: Addon unpinned, next request will update if needed"
  of Removed:           &"{addon.getName()}: Addon removed"
  of NoBackup:          &"{addon.getName()}: Restoring error, addon has no backups to restore"
  of Renamed:           &"{addon.name}: renamed to {addon.getName()}"
  else: ""
  if not loggedMsg.isEmptyOrWhitespace:
    logChannel.send(LogMessage(level: Info, msg: loggedMsg, e: nil))
  addonChannel.send(addon.deepCopy())

proc setAddonState(addon: Addon, state: AddonState, loggedMsg: string, level: LogLevel = Info) {.gcsafe.} =
  if addon.state != Failed:
    addon.state = state
  logChannel.send(LogMessage(level: level, msg: loggedMsg, e: nil))
  addonChannel.send(addon.deepCopy())

proc setAddonState(addon: Addon, state: AddonState, errorMsg: string, loggedMsg: string, e: ref Exception = nil, level: LogLevel = Fatal) {.gcsafe.} =
  addon.state = state
  addon.errorMsg = errorMsg
  logChannel.send(LogMessage(level: level, msg: loggedMsg, e: e))
  addonChannel.send(addon.deepCopy())

proc setName(addon: Addon, json: JsonNode, name: string = "none") {.gcsafe.} =
  if addon.state == Failed: return
  case addon.kind
  of Curse:
    addon.name = json["fileName"].getStr().split('-')[0]
    if addon.name.endsWith(".zip"):
      addon.name = json["fileName"].getStr().split('_')[0]
    if addon.name.endsWith(".zip"):
      addon.name = json["fileName"].getStr().split('.')[0]
  of Github, GithubRepo, Gitlab:
    addon.name = addon.project.split('/')[^1]
  of Tukui:
    addon.name = json["name"].getStr()
  of Wowint:
    addon.name = json[0]["UIName"].getStr()

proc setVersion(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  addon.startVersion = addon.version
  case addon.kind
  of Curse:
    try:
      addon.version = json["displayName"].getStr()
      if addon.version.endsWith(".zip"):
        addon.version = json["dateModified"].getStr()  
    except KeyError:
      addon.version = json["dateModified"].getStr()
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

proc invalidKeywords(addon: Addon): Regex {.gcsafe.} =
  case addon.config.mode
  of Retail: result = re"wrath|tbc|classic|vanilla"
  of Vanilla: result = re"retail|mainline|wrath|tbc"
  of Classic: result = re"retail|mainline|vanilla"
  of None: discard

proc getLatestUrl(addon: Addon): string {.gcsafe.} =
  case addon.kind
  of Curse:
    return &"https://www.curseforge.com/api/v1/mods/{addon.project}/files"
  of Github:
    return &"https://api.github.com/repos/{addon.project}/releases/latest"
  of Gitlab:
    let urlEncodedProject = addon.project.replace("/", "%2F")
    return &"https://gitlab.com/api/v4/projects/{urlEncodedProject}/releases"
  of Tukui:
    return "https://api.tukui.org/v1/addons/"
  of Wowint:
    return &"https://api.mmoui.com/v3/game/WOW/filedetails/{addon.project}.json"
  of GithubRepo:
    return &"https://api.github.com/repos/{addon.project}/commits/{addon.branch.get}"

proc setDownloadUrl(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  case addon.kind
  of Curse:
    let id = $json["id"].getInt()
    addon.downloadUrl = &"https://www.curseforge.com/api/v1/mods/{addon.project}/files/{id}/download"
  of Github:
    let assets = json["assets"]
    for asset in assets:
      if asset["content_type"].getStr() != "application/zip":
        continue
      let name = asset["name"].getStr().toLower()
      if not name.contains(addon.invalidKeywords()):
        addon.downloadUrl = asset["browser_download_url"].getStr()
        return
    addon.downloadUrl = json["zipball_url"].getStr()
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

proc download(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  var headers = newHttpHeaders()
  if not addon.config.githubToken.isEmptyOrWhitespace:
    case addon.kind
    of Github, GithubRepo:
      headers["Authorization"] = &"Bearer {addon.config.githubToken}"
    else:
      discard
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
  var downloadName: string
  case addon.kind:
  of Curse:
    downloadName = json["fileName"].getStr()
  else:
    try:
      downloadName = response.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
    except KeyError:
      downloadName = addon.downloadUrl.split('/')[^1]
  addon.filename = addon.config.tempDir / downloadName
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

proc tocDir(path: string): bool {.gcsafe.} =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|classic|vanilla|classic_era|wrath|tbc|bcc))", flags = {reIgnoreCase})
          var m: array[2, string]
          discard find(cstring(name), p, m, 0, len(name))
          name = m[0]
          moveDir(dir, dir.parentDir() / name)
        return true
  return false

proc getAddonDirs(addon: Addon): seq[string] {.gcsafe.} =
  var current = addon.extractDir
  var firstPass = true
  while true:
    if not tocDir(current):
      log(&"{addon.getName()}: extractDir contains no toc files, collecting subdirectories")
      let subdirs = collect(for kind, dir in walkDir(current): (if kind == pcDir: dir))
      assert len(subdirs) != 0 
      current = subdirs[0]
    else:
      if firstPass: return @[current]
      else: return collect(for kind, dir in walkDir(parentDir(current)): (if kind == pcDir: dir))
    firstPass = false

proc getBackupFiles(addon: Addon): seq[string] {.gcsafe.} = 
  var name = $addon.kind & addon.project
  for c in invalidFilenameChars:
    name = name.replace(c, '-')
  var backups = collect(
    for kind, path in walkDir(addon.config.backupDir): 
      if kind == pcFile and lastPathPart(path).contains(name):
        path
  )
  # oldest to newest
  backups.sort((a, b) => int(getCreationTime(a).toUnix() - getCreationTime(b).toUnix()))
  return backups

proc removeAddonFiles(addon: Addon, installDir: string, removeAllBackups: bool) {.gcsafe.} =
  for dir in addon.dirs:
    removeDir(installDir / dir)
  if removeAllBackups:
    var backups = addon.getBackupFiles()
    for file in backups:
      removeFile(file)

proc setIdAndCleanup(addon: Addon) {.gcsafe.} =
  for a in addon.config.addons:
    if a == addon:
      addon.id = a.id
      a.removeAddonFiles(addon.config.installDir, removeAllBackups = false)
      break

proc moveDirs(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  var source = addon.getAddonDirs()
  source.sort()
  addon.setIdAndCleanup()
  addon.dirs = @[]
  for dir in source:
    let name = lastPathPart(dir)
    addon.dirs.add(name)
    let destination = addon.config.installDir / name
    try:
      moveDir(dir, destination)
    except Exception as e:
      addon.setAddonState(Failed, "Problem moving Addon directories.", &"{addon.getName()}: move directories error", e)
  log(&"{addon.getName()}: Files moved to install directory.", Info)

proc createBackup(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  let backups = getBackupFiles(addon)
  var name = $addon.kind & addon.project & "&V=" & addon.version & ".zip"
  for c in invalidFilenameChars:
    name = name.replace(c, '-')
  createDir(addon.config.backupDir)
  if len(backups) > 1:
    removeFile(backups[0])
  try:
    moveFile(addon.filename, addon.config.backupDir / name)
    log(&"{addon.getName()}: Backup created {addon.config.backupDir / name}", Info)
  except Exception as e:
    addon.setAddonState(Failed, "Problem creating backup files.", &"{addon.getName()}: create backup error", e)
    discard

proc unzip(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  let (_, name, _) = splitFile(addon.filename)
  addon.extractDir = addon.config.tempDir / name
  removeDir(addon.extractDir)
  try:
    extractAll(addon.filename, addon.extractDir)
    log(&"{addon.getName()}: Extracted {addon.filename}", Info)
  except Exception as e:
    addon.setAddonState(Failed, "Problem unzipping files.", &"{addon.getName()}: unzip error", e)
    discard

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
        return addon.getLatest()
      else:
        addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
        &"{addon.getName()}: Get latest JSON bad response: {response.status}")
      return
    retryCount += 1
    sleep(100)

proc getLatestJson(addon: Addon): JsonNode {.gcsafe.} =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  try:
    json = parseJson(response.body)
  except Exception as e:
    addon.setAddonState(Failed, "JSON parsing error.", &"{addon.getName()}: JSON parsing error", e)
  case addon.kind:
  of Curse:
    var gameVersions: seq[string]
    var gameVersionNumber = case addon.config.mode
      of Retail: "10."
      of Vanilla: "1."
      of Classic: "3."
      of None: ""
    for i, data in enumerate(json["data"]):
      gameVersions.fromJson(data["gameVersions"])
      for num in gameVersions:
        if num.startsWith(gameVersionNumber):
          return json["data"][i]
    addon.setAddonState(Failed, &"JSON Error: No game version matches current mode of {addon.config.mode}.",
    &"JSON Error: {addon.getName()}: no game version matches current mode of {addon.config.mode}.")
  of Tukui:
    for data in json:
      if data["slug"].getStr() == addon.project:
        return data
    addon.setAddonState(Failed, "JSON Error: Addon not found.", &"{addon.getName()}: JSON error, addon not found.")
    return
  else:
    discard
  return json

proc install*(addon: Addon) {.gcsafe.} =
  let json = addon.getLatestJson()
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
    if addon.action == Reinstall or addon.startVersion.isEmptyOrWhitespace:
      addon.setAddonState(FinishedInstalled)
    else:
      addon.setAddonState(FinishedUpdated)
  else:
    addon.setAddonState(FinishedUpToDate)

proc uninstall*(addon: Addon) =
  addon.removeAddonFiles(addon.config.installDir, removeAllBackups = true)
  addon.setAddonState(Removed)

proc pin*(addon: Addon) =
  addon.pinned = true
  addon.setAddonState(Pinned)

proc unpin*(addon: Addon) =
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
  t.write(0, t.yMax, false, "\n")
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
  of Install, Reinstall: 
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
  if addon.state == Failed:
    addon.state = DoneFailed
  else:
    addon.state = Done
  addonChannel.send(addon)