import std/options
import std/strformat
import std/strutils

import config
import types
import logger

proc getVersion*(addon: Addon): string =
  if addon.version.isEmptyOrWhitespace and addon.startVersion.isEmptyOrWhitespace: 
    return ""
  case addon.kind
  of GithubRepo: 
    if addon.version.isEmptyOrWhitespace: 
      return addon.startVersion[0 ..< 7]
    return addon.version[0 ..< 7]
  else:
    if addon.version.isEmptyOrWhitespace: 
      return addon.startVersion
    return addon.version

proc getName*(addon: Addon): string =
  if addon.overrideName.isSome: 
    return addon.overrideName.get
  if addon.name.isEmptyOrWhitespace:
    return $addon.kind & ':' & addon.project
  return addon.name

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

proc getLatestUrl*(addon: Addon): string {.gcsafe.} =
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
  of Wago:
    return &"https://addons.wago.io/addons/{addon.project}/versions?stability=stable"