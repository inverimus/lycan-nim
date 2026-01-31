#[
HearthSync - A very simple World of Warcraft addon manager
Copyright (C) 2026 Michael Green

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]#

import std/algorithm
import std/os
import std/parseopt
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/terminal
import std/times

import action
import addon
import addonHelp
import config
import help
import term
import types
import logger
import messages
import files

proc changeConfig(args: seq[string]) =
  let t = configData.term
  if len(args) == 0:
    showConfig()
  if len(args) < 2:
    t.write(0, fgRed, styleBright, "Error: ", fgWhite, "Missing argument\n\n", resetStyle)
    displayHelp(@["config"])
  for i in 0 ..< len(args) - 1:
    let item = args[i]
    case item:
    of "backup":
      setBackup(args[i + 1]); break
    of "github":
      setGithubToken(args[i + 1]); break
    else:
      t.write(0, fgRed, styleBright, "Error: ", fgWhite, "Unrecognized option ", fgCyan, item, "\n", resetStyle)
      displayHelp(@["config"])
  writeConfig(configData)
  quit()

proc processMessages(): seq[Addon] =
  var maxName {.global.} = 0
  var maxVersion {.global.} = 0
  var addons {.global.}: seq[Addon]
  while true:
    let (ok, addon) = addonChannel.tryRecv()
    if ok:
      case addon.state
      of Done, DoneFailed:
        result.add(addon)
      else:
        addons = addons.filterIt(it != addon)
        addons.add(addon)
        maxName = addons[addons.mapIt(it.getName().len).maxIndex()].getName().len + 2
        maxVersion = addons[addons.mapIt(it.getVersion().len).maxIndex()].getVersion().len + 2
        for addon in addons:
          addon.stateMessage(maxName, maxVersion)
    else:
      break

proc processLog() =
  while true:
    let (ok, logMessage) = logChannel.tryRecv()
    if ok:
      if logMessage.level <= configData.logLevel:
        log(logMessage)
    else:
      break

proc parseArgs(): (tuple[action: Action, args: seq[string]]) =
  if commandLineParams().len == 0:
    return (Update, @[])
  var 
    opt = initOptParser()
    action: Action
  for kind, key, _ in opt.getopt():
    case kind
    of cmdEnd: doAssert(false)
    of cmdShortOption, cmdLongOption:
      displayHelp()
    of cmdArgument:
      case key:
      of "a", "add":     action = Install
      of "i", "install": action = Install
      of "u", "update":  action = Update
      of "r", "remove":  action = Remove
      of "n", "name":    action = Name
      of "l", "list":    action = List
      of "c", "config":  action = Setup
      of "h", "help":    action = Help
      of "reinstall":    action = Reinstall
      of "revert":       action = Revert
      of "pin":          action = Pin
      of "unpin":        action = Unpin
      of "restore":      action = Restore
      else:              displayHelp()
      return (action, opt.remainingArgs())




proc main() {.inline.} =
  let (action, args) = parseArgs()
  if action == Setup and args.contains("path"):
    setPath(args)
  
  configData = loadConfig()
  logInit(configData.logLevel)
  
  let t = configData.term
  var
    addons: seq[Addon]
    ids: seq[int16]
  case action
  of Install:
    if args.len == 0:
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, "Unable to parse any addons to install.\n", resetStyle)
      quit()
    var addon = parseAddonFromString(args[0])
    addons.add(addon)
  of Update, Reinstall:
    for addon in configData.addons:
      addon.setAction(action)
      addons.add(addon)
    if addons.len == 0:
      displayHelp()
  of Revert:
    addons = getRecentlyUpdatedAddons()
    if addons.len == 0:
      displayHelp()
  of Remove, Restore, Pin, Unpin:
    if args.len == 0:
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, &"Unable to parse any addons to {($action).toLowerAscii()}. Please provide a list of addon ids.\n", resetStyle)
      quit()
    for arg in args:
      try:
        ids.add(int16(arg.parseInt()))
      except:
        t.write(2, fgRed, styleBright, "Error: ", fgWhite, &"Unable to parse id, instead found {arg}.\n", resetStyle)
        quit()
    for id in ids:
      var addon = parseAddonFromId(id, action)
      addons.add(addon)
  of Name:
    addons.add(renameAddon(args))
  of List, ListAll:
    addons = configData.addons
    if addons.len == 0:
      t.write(2, fgWhite, "No addons installed\n", resetStyle)
      quit()
    if "t" in args or "time" in args:
      addons.sort((a, z) => int(a.time < z.time))
    let listAll = "a" in args or "all" in args
    for addon in addons:
      addon.setAction(if listAll: ListAll else: List)
  of Setup:
    changeConfig(args)
  of Help:
    displayHelp(args)

  for i, addon in addons:
    addon.line = i

  addonChannel.open()
  var thr = newSeq[Thread[Addon]](len = addons.len)
  for i, addon in addons:
    addon.config = addr configData
    createThread(thr[i], workQueue, addon)

  var processed, failed, success, rest, final: seq[Addon]
  while true:
    processed &= processMessages()
    processLog()
    var runningCount = 0
    for t in thr:
      runningCount += int(t.running)
    if runningCount == 0:
      break
    sleep(POLLRATE)

  processLog()
  processed &= processMessages()
  thr.joinThreads()

  t.addLine()
  if action == List:
    quit(0)

  failed = processed.filterIt(it.state == DoneFailed)
  success = processed.filterIt(it.state == Done)

  case action
  of Install:
    assignIds(success & configData.addons)
    success.apply((a: Addon) => t.write(1, a.line, fgBlue, &"{a.id:<3}", resetStyle))
    t.addLine()
  else:
    discard

  rest = configData.addons.filterIt(it notin success)
  final = if action != Remove: success & rest else: rest

  writeAddons(final)
  writeConfig(configData)

  for addon in failed:
    t.write(0, fgRed, styleBright, &"\nError: ", fgCyan, addon.getName(), "\n", resetStyle)
    t.write(4, fgWhite, addon.errorMsg, "\n", resetStyle)

when isMainModule:
  main()
