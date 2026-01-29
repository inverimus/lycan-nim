import std/options
import std/os
import std/re
import std/sequtils
import std/strformat
import std/strutils
import std/terminal

import addon
import config
import term
import types

when not defined(release):
  import logger
  debugLog("action.nim")

proc validProject(project: string, kind: AddonKind): bool =
  case kind
  of Curse, Wowint: return project.all(isDigit)
  of Tukui:         return project == "tukui" or project == "elvui"
  of Github:        return project.split("/").len == 2
  of Wago, Zremax:  return not project.contains("/")
  of Gitlab:        return project.split("/").len in [2, 3]
  of GithubRepo:    return false # unused

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
        t.write(2, fgYellow, &"For curseforge, using the Project ID is easier. Locate the ID on the right side of the addon page and use {getAppFilename().lastPathPart()} -i curse:<ID>\n")
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
    of "zremax":
      let p = re"^wow\/addons\/(.+)"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if validProject(m[0], Zremax):
        return some(newAddon(m[0], Zremax))
    else:
      discard
  return none(Addon)

proc addonFromProject(s: string): Option[Addon] =
  let t = configData.term
  var match: array[2, string]
  let pattern = re"^([^:]+):(.*)$"
  if find(cstring(s), pattern, match, 0, len(s)) == -1:
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
  of "zremax:": 
    if validProject(id, Zremax): return some(newAddon(id, Zremax))
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
  if find(cstring(s), pattern, match, 0, len(s)) == -1:
    return addonFromProject(s)
  else:
    return addonFromUrl(s)

proc addonFromId(id: int16): Option[Addon] =
  for a in configData.addons:
    if a.id == id: return some(a)
  return none(Addon)

proc parseAddonFromString*(arg: string): Addon =
  let option = parseAddon(arg)
  if option.isSome:
    result = option.get
    result.action = Install
  else:
    configData.term.write(2, fgRed, styleBright, "Error: ", fgWhite, "Unable to parse addon from arg: ", fgCyan, arg, "\n", resetStyle)
    quit(1)

proc parseAddonFromId*(id: int16, action: Action): Addon =
  let option = addonFromId(id)
  if option.isSome:
    result = option.get
    result.action = action
  else:
    configData.term.write(2, fgRed, styleBright, "Error: ", fgWhite, "Unable to parse addon from id: ", fgCyan, $id, "\n", resetStyle)
    quit(1)

proc setAction*(addon: Addon, action: Action) =
  addon.action = action

proc renameAddon*(args: seq[string]): Addon =
  let t = configData.term
  var id: int16
  try:
    id = int16(args[0].parseInt())
  except:
    t.write(2, fgRed, styleBright, "Error: ", fgWhite, &"Unable to parse id, instead found {args[0]}\n", resetStyle)
    t.write(2, fgWhite, &"Usage: {getAppFilename().lastPathPart()} -n <id> <new name>  (Leave blank to reset to default)\n", resetStyle)
    quit()
  var opt = addonFromId(id)
  if opt.isSome:
    result = opt.get
    if args.len == 1:
      result.overrideName = none(string)
    elif args.len == 2:
      result.overrideName = some(args[1])
    else:
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, "Too many arguments.\n", resetStyle)
      t.write(2, fgWhite, &"Usage: {getAppFilename().lastPathPart()} -n <id> <new name>  (Leave blank to reset to default)\n", resetStyle)
      quit()
    result.action = Name
  else:
    t.write(2, fgRed, styleBright, "Error: ", fgWhite, &"Unable to find addon with id: ", fgCyan, $id, "\n", resetStyle)