import std/algorithm
import std/httpclient
import std/json
import std/jsonutils
import std/options
import std/os
import std/re
import std/strformat
import std/strutils
import std/sugar
import std/times

import zippy/ziparchives

import config
import types
import logger
import addonHelp

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

proc writeAddons*(addons: var seq[Addon]) =
  if not configData.addonJsonFile.isEmptyOrWhitespace:
    addons.sort((a, z) => int(a.name.toLower() > z.name.toLower()))
    let addonsJson = addons.toJson(ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
    try:
      writeFile(configData.addonJsonFile, pretty(addonsJson))
      log(&"Installed addons file saved: {configData.addonJsonFile}", Info)
    except Exception as e:
      log(&"Fatal error writing installed addons file: {configData.addonJsonFile}", Fatal, e)

proc setDownloadFilename(addon: Addon, json: JsonNode, response: Response) {.gcsafe.} =
  var downloadName: string
  case addon.kind:
  of Wago:
    # The actual filename is included in a 302 redirect which is handled automatically by httpclient. We should be able to
    # make a request with maxRedirects = 0 to get the actual name, but it's not worth the overhead.
    # Should we just do this for all downloads? Maybe some value in matching manual downloads when possible.
    downloadName = addon.project & ".zip"
  of Curse:
    downloadName = json["fileName"].getStr()
  else:
    try:
      downloadName = response.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
    except KeyError:
      downloadName = addon.downloadUrl.split('/')[^1]
  addon.filename = addon.config.tempDir / downloadName

proc writeDownloadedFile(addon: Addon, response: Response) {.gcsafe.} =
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

proc download*(addon: Addon, json: JsonNode) {.gcsafe.} =
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
        addon.setAddonState(Failed, &"Error while trying to download: {addon.downloadUrl}",
          &"{addon.getName()}: download failed for {addon.downloadUrl}", e)
        return
      retryCount += 1
      sleep(100)
      continue
    if response.status.contains("200"):
      break
    if retryCount > 4:
      addon.setAddonState(Failed, &"Bad response downloading {response.status}: {addon.downloadUrl}",
        &"{addon.getName()}: download failed. Response code {response.status} from {addon.downloadUrl}")
      return
    retryCount += 1
    sleep(100)
  addon.setDownloadFilename(json, response)
  addon.writeDownloadedFile(response)
  
proc tocDir(path: string): bool {.gcsafe.} =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|classic|vanilla|classic_era|wrath|tbc|bcc|cata|wotlk|mop))", flags = {reIgnoreCase})
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

proc setIdAndCleanup(addon: Addon) {.gcsafe.} =
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