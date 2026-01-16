#[
https://github.com/Stanzilla/AdvancedInterfaceOptions
https://github.com/Tercioo/Plater-Nameplates/tree/master
https://gitlab.com/woblight/actionmirroringframe
https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html
https://www.tukui.org/elvui
https://www.curseforge.com/api/v1/mods/1592/files/4963354/download
https://addons.wago.io/addons/rarescanner
]#

import std/algorithm
import std/enumerate
import std/options
import std/os
import std/parseopt
import std/re
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/terminal
import std/times

import addon
import addonHelp
import config
import help
import term
import types
import logger
import messages
import files

proc validProject(project: string, kind: AddonKind): bool =
  case kind
  of Curse, Wowint:
    return project.all(isDigit)
  of Tukui:
    return project == "tukui" or project == "elvui"
  of Github:
    return project.split("/").len == 2
  of Gitlab:
    let split = project.split("/")
    return split.len == 2 or split.len == 3
  of Wago:
    return not project.contains("/")
  else:
    discard
  return false

proc addonFromUrl(url: string): Option[Addon] =
  let t = configData.term
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?://)?(?:www\.)?(.+)\.(?:com|org|io)/(.+[^/\n])"
  let found = find(cstring(url), pattern, urlmatch, 0, len(url))
  if found == -1 or urlmatch[1] == "":
    t.write(0, fgRed, styleBright, "Error: ", fgWhite, &"Unable to determine addon from ", fgCyan, url, "\n", resetStyle)
  case urlmatch[0].toLower()
    of "curseforge":
      var m: array[1, string]
      let pattern = re"\/mods\/(\d+)\/"
      discard find(cstring(urlmatch[1]), pattern, m, 0, len(urlmatch[1]))
      if m[0] == "":
        t.write(0, fgRed, styleBright, "Error: ", fgWhite, &"Unable to determine addon from ", fgCyan, url, "\n", resetStyle)
        t.write(2, fgYellow, "Make sure you have the corret URL. Start a manual download then copy the 'try again' link.\n")
        t.write(2, fgYellow, "For curseforge, using the Project ID is easier. Locate the ID on the right side of the addon page and use lycan -i curse:<ID>\n")
      else:
        if validProject(m[0], Curse):
          return some(newAddon(m[0], Curse))
    of "github":
      let p = re"^(.+?/.+?)(?:/|$)(?:tree/)?(.+)?"
      var m: array[2, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if validProject(m[0], Github):
        if m[1] == "":
          return some(newAddon(m[0], Github))
        else:
          return some(newAddon(m[0], GithubRepo, branch = some(m[1])))
    of "gitlab":
      if validProject(urlmatch[1], Gitlab):
        return some(newAddon(urlmatch[1], Gitlab))
    of "tukui":
      if validProject(urlmatch[1], Tukui):
        return some(newAddon(urlmatch[1], Tukui))
    of "wowinterface":
      let p = re"^downloads\/info(\d+)-?"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if validProject(m[0], Wowint):
        return some(newAddon(m[0], Wowint))
    of "addons.wago":
      let p = re"^addons\/(.+)"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if validProject(m[0], Wago):
        return some(newAddon(m[0], Wago))
    else:
      discard
  return none(Addon)

proc addonFromProject(s: string): Option[Addon] =
  let t = configData.term
  var match: array[2, string]
  let pattern = re"^([^:]+):(.*)$"
  let found = find(cstring(s), pattern, match, 0, len(s))
  if found == -1:
    t.write(0, fgRed, styleBright, "Error: ", fgWhite, &"Unable to determine addon from ", fgCyan, s, "\n", resetStyle)
    return none(Addon)
  let source = match[0].toLower()
  let id = match[1].toLower()
  case source
  of "curse":  
    if validProject(id, Curse):  return some(newAddon(id, Curse))
  of "wowint": 
    if validProject(id, Wowint): return some(newAddon(id, Wowint))
  of "tukui":  
    if validProject(id, Tukui):  return some(newAddon(id, Tukui))
  of "gitlab": 
    if validProject(id, Gitlab): return some(newAddon(id, Gitlab))
  of "wago":   
    if validProject(id, Wago):   return some(newAddon(id, Wago))
  of "github":
    if validProject(id, Github):
      var match: array[2, string]
      let pattern = re"^(.+?)(?:@(.+))?$"
      discard find(cstring(id), pattern, match, 0, len(id))
      if match[1] == "":
        return some(newAddon(id, Github))
      else:
        return some(newAddon(match[0], GithubRepo, branch = some(match[1])))
  else: 
    discard
  return none(Addon)

proc parseAddon(s: string): Option[Addon] =
  var match: array[2, string]
  let pattern = re"^(?:https?:\/\/)?(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+.*[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?"
  let found = find(cstring(s), pattern, match, 0, len(s))
  if found == -1:
    return addonFromProject(s)
  else:
    return addonFromUrl(s)

proc addonFromId(id: int16): Option[Addon] =
  for a in configData.addons:
    if a.id == id: return some(a)
  return none(Addon)

proc changeConfig(args: seq[string]) =
  let t = configData.term
  if len(args) == 0:
    showConfig()
  if len(args) < 2:
    t.write(0, fgRed, styleBright, "Error: ", fgWhite, "Missing argument\n\n", resetStyle)
    displayHelp("config")
  for i in 0 ..< len(args) - 1:
    let item = args[i]
    case item:
    of "backup":
      setBackup(args[i + 1]); break
    of "github":
      setGithubToken(args[i + 1]); break
    else:
      t.write(0, fgRed, styleBright, "Error: ", fgWhite, "Unrecognized option ", fgCyan, item, "\n", resetStyle)
      displayHelp("config")
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





proc main() {.inline.} =
  configData = loadConfig()
  logInit(configData.logLevel)
  var opt = initOptParser(
    commandLineParams(),
    shortNoVal = {'u', 'i', 'a'}, 
    longNoVal = @["update"]
  )
  var
    action = Empty
    actionCount = 0
    args: seq[string]
  for kind, key, val in opt.getopt():
    case kind
    of cmdShortOption, cmdLongOption:
      if val == "":
        case key:
        of "a", "i":          action = Install;   actionCount += 1
        of "u", "update":     action = Update;    actionCount += 1
        of "r":               action = Remove;    actionCount += 1
        of "n", "name":       action = Name;      actionCount += 1
        of "l", "list":       action = List;      actionCount += 1
        of "c", "config":     action = Setup;     actionCount += 1
        of "h", "help":       action = Help;      actionCount += 1
        of "reinstall":       action = Reinstall; actionCount += 1
        else: displayHelp()
      else:
        args.add(val)
        case key:
        of "add", "install":  action = Install; actionCount += 1
        of "r", "remove":     action = Remove;  actionCount += 1
        of "l", "list":       action = List;    actionCount += 1
        of "pin":             action = Pin;     actionCount += 1
        of "unpin":           action = Unpin;   actionCount += 1
        of "name":            action = Name;    actionCount += 1
        of "restore":         action = Restore; actionCount += 1
        of "c", "config":     action = Setup;   actionCount += 1
        of "help":            action = Help;    actionCount += 1
        else: displayHelp()
    of cmdArgument:
      args.add(key)
    else:
      displayHelp()
    if actionCount > 1 or (len(args) > 0 and action == Empty):
      displayHelp()

  let t = configData.term
  var
    addons: seq[Addon]
    line = 0
    ids: seq[int16]
  case action
  of Install:
    let opt = parseAddon(args[0])
    if opt.isSome:
      var addon = opt.get
      addon.line = line
      addon.action = Install
      addons.add(addon)
      line += 1
    if addons.len == 0:
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, "Unable to parse any addons to install.\n", resetStyle)
      quit()
  of Update, Empty, Reinstall:
    for addon in configData.addons:
      addon.line = line
      addon.action = if action == Reinstall: Reinstall else: Update
      addons.add(addon)
      line += 1
    if addons.len == 0:
      displayHelp()
  of Remove, Restore, Pin, Unpin:
    for arg in args:
      try:
        ids.add(int16(arg.parseInt()))
      except:
        continue
    for id in ids:
      var opt = addonFromId(id)
      if opt.isSome:
        var addon = opt.get
        addon.line = line
        case action
        of Remove:  addon.action = Remove
        of Restore: addon.action = Restore
        of Pin:     addon.action = Pin
        of Unpin:   addon.action = Unpin
        else: discard
        addons.add(addon)
        line += 1
  of Name:
    var id: int16
    try:
      id = int16(args[0].parseInt())
    except:
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, "Unable to parse id.\n", resetStyle)
      t.write(2, fgWhite, "Usage: lycan -n <id> <new name>  (Leave blank to reset to default)\n", resetStyle)
      quit()
    var opt = addonFromId(id)
    if opt.isSome:
      let addon = opt.get
      if args.len == 1:
        addon.overrideName = none(string)
      elif args.len == 2:
        addon.overrideName = some(args[1])
      else:
        displayHelp()
      addon.action = Name
      addons.add(addon)
    else:
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, &"Unable to find addon with id: ", fgCyan, $id, "\n", resetStyle)
  of List:
    addons = configData.addons
    if "t" in args or "time" in args:
      addons.sort((a, z) => int(a.time < z.time))
    addons.list()
  of Setup:
    changeConfig(args)
  of Help:
    if args.len > 0:
      displayHelp(args[0])
    else:
      displayHelp()

  addonChannel.open()
  var thr = newSeq[Thread[Addon]](len = addons.len)
  for i, addon in enumerate(addons):
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
  
  failed = processed.filterIt(it.state == DoneFailed)
  success = processed.filterIt(it.state == Done)

  case action
  of Install:
    assignIds(success & configData.addons)
    success.apply((a: Addon) => t.write(1, a.line, fgBlue, &"{a.id:<3}", resetStyle))
  else:
    discard

  rest = configData.addons.filterIt(it notin success)
  final = if action != Remove: success & rest else: rest

  writeAddons(final)
  writeConfig(configData)

  t.addLine()
  for addon in failed:
    t.write(0, fgRed, styleBright, &"\nError: ", fgCyan, addon.getName(), "\n", resetStyle)
    t.write(4, fgWhite, addon.errorMsg, "\n", resetStyle)

when isMainModule:
  main()