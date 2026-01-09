import std/enumerate
import std/sets
import std/httpclient
import std/json
import std/options
import std/os
import std/re
import std/sequtils
import std/strutils
import std/sugar
import std/times

import config
import types
import term
import messages

import github
import curse
import gitlab
import wowint
import tukui
import addonBase

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
  let json = addon.chooseJson()
  addon.setAddonState(Parsing)
  addon.chooseDownload(json)
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