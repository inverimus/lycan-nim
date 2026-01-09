import std/algorithm
import std/sets
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
import logger

proc newAddonCurse*(curseId: string): AddonCurse =
  result = new(AddonCurse)
  result.curseId = curseId

proc newAddonGithub*(owner, name: string): AddonGithub =
  result = new(AddonGithub)
  result.owner = owner
  result.name = name

proc newAddonGithubRepo*(owner, name, branch: string): AddonGithubRepo =
  result = new(AddonGithubRepo)
  result.owner = owner
  result.name = name
  result.branch = branch

proc newAddonGitlab*(owner, name: string): AddonGitlab =
  result = new(AddonGitlab)
  result.owner = owner
  result.name = name

proc newAddonWowint*(projectId: string): AddonWowint =
  result = new(AddonWowint)
  result.projectId = projectId

proc newAddonTukui*(slug: string): AddonTukui =
  result = new(AddonTukui)
  result.slug = slug

proc `==`*(a, b: Addon): bool {.inline.} =
  try:
    return a.name.toLower() == b.name.toLower()
  except:
    discard
  try:
    return a.projectId == b.projectId
  except:
    discard
  try:
    return a.curseId == b.curseId
  except:
    discard
  return false

proc assignIds*(addons: seq[Addon]) =
  var ids: set[int16]
  addons.apply((a: Addon) => ids.incl(a.id))
  var id: int16 = 1
  for a in addons:
    if a.id == 0:
      while id in ids: id += 1
      a.id = id
      incl(ids, id)

proc writeAddons*(addons: var seq[Addon]) =
  if not configData.addonJsonFile.isEmptyOrWhitespace:
    addons.sort((a, z) => int(a.name.toLower() > z.name.toLower()))
    let addonsJson = addons.toJson(ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
    try:
      writeFile(configData.addonJsonFile, pretty(addonsJson))
      log(&"Installed addons file saved: {configData.addonJsonFile}", Info)
    except Exception as e:
      log(&"Fatal error writing installed addons file: {configData.addonJsonFile}", Fatal, e)

proc setAddonState*(addon: Addon, state: AddonState) {.gcsafe.} =
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

proc setAddonState*(addon: Addon, state: AddonState, loggedMsg: string, level: LogLevel = Info) {.gcsafe.} =
  if addon.state != Failed:
    addon.state = state
  logChannel.send(LogMessage(level: level, msg: loggedMsg, e: nil))
  addonChannel.send(addon.deepCopy())

proc setAddonState*(addon: Addon, state: AddonState, errorMsg: string, loggedMsg: string, e: ref Exception = nil, level: LogLevel = Fatal) {.gcsafe.} =
  addon.state = state
  addon.errorMsg = errorMsg
  logChannel.send(LogMessage(level: level, msg: loggedMsg, e: e))
  addonChannel.send(addon.deepCopy())

proc tocDir(path: string): bool {.gcsafe.} =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|classic|vanilla|classic_era|wrath|tbc|bcc|cata|wotlk))", flags = {reIgnoreCase})
          var m: array[2, string]
          discard find(cstring(name), p, m, 0, len(name))
          name = m[0]
          moveDir(dir, dir.parentDir() / name)
        return true
  return false

proc getAddonDirs*(addon: Addon): seq[string] {.gcsafe.} =
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

proc getBackupFiles*(addon: Addon): seq[string] {.gcsafe.} = 
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

proc removeAddonFiles*(addon: Addon, installDir: string, removeAllBackups: bool) {.gcsafe.} =
  for dir in addon.dirs:
    removeDir(installDir / dir)
  if removeAllBackups:
    var backups = addon.getBackupFiles()
    for file in backups:
      removeFile(file)

proc setIdAndCleanup*(addon: Addon) {.gcsafe.} =
  for a in addon.config.addons:
    if a == addon:
      addon.id = a.id
      a.removeAddonFiles(addon.config.installDir, removeAllBackups = false)
      break

proc moveDirs*(addon: Addon) {.gcsafe.} =
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

proc createBackup*(addon: Addon) {.gcsafe.} =
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

proc unzip*(addon: Addon) {.gcsafe.} =
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

proc download*(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  var headers = newHttpHeaders()
  if not addon.config.githubToken.isEmptyOrWhitespace:
    headers["Authorization"] = &"Bearer {addon.config.githubToken}"
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

proc getLatest*(addon: Addon): Response {.gcsafe.} =
  addon.setAddonState(Checking, &"Checking: {addon.getName()} getting latest version information")
  let url = addon.getLatestUrl()
  var headers = newHttpHeaders()
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
      addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
      &"{addon.getName()}: Get latest JSON bad response: {response.status}")
      return
    retryCount += 1
    sleep(100)

proc extractJson*(addon: Addon): JsonNode =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  try:
    json = parseJson(response.body)
  except Exception as e:
    addon.setAddonState(Failed, "JSON parsing error.", &"{addon.getName()}: JSON parsing error", e)
  return json