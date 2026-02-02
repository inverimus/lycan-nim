import std/algorithm
import std/colors
import std/options
import std/sequtils
import std/strutils
import std/sugar
import std/times
import std/terminal

import addonHelp
import config
import types
import term

when not defined(release):
  import logger
  debugLog("messages.nim")

const LIGHT_GREY: Color = Color(0x34_34_34)

proc stateMessage*(addon: Addon, nameSpace, versionSpace, kindSpace, projectSpace: int) = 
  case addon.state
  of Failed, DoneFailed: return
  else: discard

  let
    t = configData.term
    stateSpace = 12
    even = addon.line mod 2 == 0
    branch = if addon.branch.isSome: addon.branch.get else: ""

    kind = case addon.kind
    of GithubRepo: "Github"
    else: $addon.kind

    stateColor = case addon.state
    of Checking, Parsing, Downloading, Installing, Restoring: fgCyan
    of FinishedUpdated, FinishedInstalled, FinishedUpToDate, Pinned, FinishedPinned, Removed, Unpinned, Renamed, Restored: fgGreen
    of Failed, NoBackup: fgRed
    else: fgWhite

    versionColor = case addon.state
    of Checking, Parsing, Downloading, Installing, Restoring, FinishedUpToDate, Pinned, FinishedPinned, Unpinned, Renamed, Failed, NoBackup: fgYellow
    of FinishedUpdated, FinishedInstalled, Removed, Restored: fgGreen
    else: fgWhite
    
  t.write(1, addon.line, true)
  if even:
    t.write((fgWhite, bgDefault), styleBright)
  else:
    t.write((fgWhite, LIGHT_GREY), if not t.trueColor: styleReverse else: styleBright)
  
  t.write(fgBlue, alignLeft($addon.id, 3),
    stateColor, alignLeft($addon.state, stateSpace),
    fgWhite, addon.getTruncatedName().alignLeft(nameSpace), 
    versionColor, addon.getVersion().alignLeft(versionSpace), 
    fgCyan, kind.alignLeft(kindSpace)
  )

  if addon.branch.isSome:
    let x = 16 + nameSpace + versionSpace + kind.len
    t.write(x, addon.line, fgWhite, "@", fgBlue, branch)
  
  t.write(resetStyle)

proc resetBackground*(t: Term, line: int, defaultBackground: bool) =
  t.write(0, line, true, resetStyle)
  if defaultBackground: 
    t.write((fgWhite, bgDefault), styleBright)
  else: 
    t.write((fgWhite, LIGHT_GREY), if not t.trueColor: styleReverse else: styleBright)

proc writeAddonLine(
  addon: Addon, 
  line, nameSpace, versionSpace, kindSpace, projectSpace: int, 
  detailed, defaultBackground: bool
): int =
  let t = configData.term
  let
    branch = if addon.branch.isSome: addon.branch.get else: ""
    pin = if addon.pinned: "!" else: " "
    time = addon.time.format("MM-dd-yy hh:mm")
    kind = if addon.kind == GitHubRepo: "Github" else: $addon.kind
    nameSpace = if nameSpace > 40: 40 else: nameSpace
  
  resetBackground(t, line, defaultBackground)
  
  t.write(0, line, " ", fgBlue, alignLeft($addon.id, 3),
    fgWhite, addon.getTruncatedName().alignLeft(nameSpace),
    fgRed, pin,
    fgGreen, addon.getVersion().alignLeft(versionSpace),
    fgCyan, kind.alignLeft(kindSpace)
  )
  if addon.branch.isSome:
    let x = 5 + nameSpace + versionSpace + kind.len
    t.write(x, line, fgWhite, "@", fgBlue, branch)
  if detailed:
    let x = 5 + nameSpace + versionSpace + kindSpace
    t.write(x, line, fgWhite, time.alignLeft(16), fgBlue, addon.project.alignLeft(projectSpace))
  t.write(resetStyle)
  return line + 1

proc writeAddonMultiLine(addon: Addon, line, endSpaces: int, detailed, defaultBackground: bool): int = 
  let t = configData.term
  let
    branch = if addon.branch.isSome: addon.branch.get else: ""
    pin = if addon.pinned: "!" else: ""
    time = addon.time.format("MM-dd-yy hh:mm")
    kind = if addon.kind == GitHubRepo: "Github" else: $addon.kind
    indent5 = "     "

  resetBackground(t, line, defaultBackground)
  t.write(0, line, " ", fgBlue, alignLeft($addon.id, 3), fgWhite, addon.getName().alignLeft(endSpaces + 10), resetStyle)

  resetBackground(t, line + 1, defaultBackground)
  t.write(0, line + 1, indent5, fgYellow, alignLeft("Version:", 9), fgRed, pin, fgGreen, addon.getVersion().alignLeft(endSpaces), resetStyle)

  resetBackground(t, line + 2, defaultBackground)
  t.write(0, line + 2, indent5, fgYellow, alignLeft("Source:", 9), fgCyan, kind.alignLeft(endSpaces), resetStyle)
  if addon.branch.isSome:
    let x = 14 + kind.len
    t.write(x, line + 2, fgWhite, "@", fgBlue, branch)

  if detailed:
    resetBackground(t, line + 3, defaultBackground)
    t.write(0, line + 3, indent5, fgYellow, alignLeft("Updated:", 9), fgWhite, time.alignLeft(endSpaces), resetStyle)
    
    resetBackground(t, line + 4, defaultBackground)
    t.write(0, line + 4, indent5, fgYellow, alignLeft("Project:", 9), fgBlue, addon.project.alignLeft(endSpaces), resetStyle)
  
  t.write(resetStyle)
  return line + 5

proc listAddons*(addons: var seq[Addon], args: seq[string]) = 
  let t = configData.term
  if addons.len == 0:
    t.write(1, fgWhite, "No addons installed\n", resetStyle)
    t.addLine()
    return
  let 
    detailed = "a" in args or "all" in args
    nameSpace = addons.mapIt(it.getName().len).max + 2
    versionSpace = addons.mapIt(it.getVersion().len).max + 2
    kindSpace = addons.mapIt(it.getKind().len).max + 2
    projectSpace = if detailed: addons.mapIt(it.project.len).max + 2 else: 0
    endSpaces = (
      if not detailed: 0
      else: addons.mapIt([
        it.getName().len,
        it.getVersion().len,
        (if it.kind == GitHubRepo: 6 else: len($it.kind)),
        it.project.len
      ].max).max
    )

  if "t" in args or "time" in args:
    addons.sort((a, z) => int(a.time < z.time))

  var 
    multiLine = nameSpace + versionSpace + kindSpace + projectSpace + 5 > t.width
    line = 0
    defaultBackground = true
  for addon in addons:
    if multiLine:
      line = writeAddonMultiLine(addon, line, endSpaces, detailed, defaultBackground)
    else:
      line = writeAddonLine(addon, line, nameSpace, versionSpace, kindSpace, projectSpace, detailed, defaultBackground)
    defaultBackground = not defaultBackground
  t.addLine()