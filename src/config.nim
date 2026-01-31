import std/json
import std/jsonutils
import std/options
import std/os
import std/strformat
import std/strutils
import std/terminal
import std/times

import types
import term
import logger

var configData*: Config
var addonChannel*: Channel[Addon]

proc fromJsonHook(a: var Addon, j: JsonNode) =
  var
    b, n: Option[string]
    d: seq[string]
    k: AddonKind
  try:
    b = some(j["branch"].getStr())
  except KeyError:
    b = none(string)
  try:
    n = some(j["overrideName"].getStr())
  except KeyError:
    n = none(string)

  d.fromJson(j["dirs"])
  k.fromJson(j["kind"])

  a = new(Addon)
  a.project = j["project"].getStr()
  a.kind = k
  a.branch = b
  a.version = j["version"].getStr()
  a.gameVersion = j["gameVersion"].getStr()
  a.name = j["name"].getStr()
  a.overrideName = n
  a.dirs = d
  a.id = int16(j["id"].getInt())
  a.pinned = j["pinned"].getBool()
  a.time = parse(j["time"].getStr(), "yyyy-MM-dd'T'HH:mm")

proc parseInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename): return @[]
  var addonsJson: JsonNode
  try:
    addonsJson = readFile(filename).parseJson()
  except Exception as e:
    configData.term.write(2, fgRed, styleBright, "Error: ", fgWhite, "Fatal error parsing installed addons file: ", fgCyan, filename, "\n", resetStyle)
    log(&"Fatal error parsing installed addons file: {filename}", Fatal, e)
    quit(1)
  for addon in addonsJson:
    var a = new(Addon)
    a.fromJson(addon)
    result.add(a)


let configPath = getCurrentDir() / "hearthsync.cfg"

proc writeConfig*(config: Config) =
  var json = newJObject()
  json["backupEnabled"] = %config.backupEnabled
  json["backupDir"] = %config.backupDir
  json["githubToken"] = %config.githubToken
  json["logLevel"] = %config.logLevel
  json["wowDir"] = %config.wowDir
  
  try:
    writeFile(configPath, pretty(json))
    log(&"Configuration file saved: {configPath}", Info)
  except Exception as e:
    log(&"Fatal error writing: {configPath}", Fatal, e)

proc loadConfig*(): Config =
  result = Config()
  result.tempDir = getTempDir() / "hearthsync"
  createDir(result.tempDir)
  result.term = termInit()
  result.time = now()
  
  var configJson: JsonNode
  try:
    configJson = readFile(configPath).parseJson()
  except:
    if dirExists(getCurrentDir() / "WTF"):
      result.logLevel = Debug
      result.backupEnabled = true
      result.wowDir = getCurrentDir()
      result.backupDir = getCurrentDir() / "Interface" / "hearthsync_backup"
      result.addonJsonFile = getCurrentDir() / "WTF" / "hearthsync.addons"
      result.installDir = getCurrentDir() / "Interface" / "AddOns"
      result.githubToken = ""
      result.addons = @[]
      writeConfig(result)
      log(&"{configPath} not found, defaults loaded", Info)
      return
    else:
      result.term.write(0, fgRed, styleBright, "Error: ", fgWhite, &"Did not find WTF directory. Run this program from the root of the game directory or set the wow path: {getAppFilename().lastPathPart()} config path <path>\n", resetStyle)
      quit(1)

  result.wowDir = configJson["wowDir"].getStr()
  result.addonJsonFile = result.wowDir / "WTF" / "hearthsync.addons"
  result.installDir = result.wowDir / "Interface" / "AddOns"
  result.logLevel = parseEnum[LogLevel](configJson["logLevel"].getStr())
  result.backupEnabled = configJson["backupEnabled"].getBool()
  result.backupDir = configJson["backupDir"].getStr()
  result.githubToken = configJson["githubToken"].getStr()
  result.addons = parseInstalledAddons(result.addonJsonFile)
  log("Configuration loaded", Info)

proc setBackup*(arg: string) =
  let t = configData.term
  case arg.toLower()
  of "y", "yes", "on", "enable", "enabled", "true":
    configData.backupEnabled = true
    t.write(2, fgWhite, "Backup enabled\n", resetStyle)
    t.write(2, fgWhite, "Backup directory: ", fgCyan, configData.backupDir, "\n", resetStyle)
    log(&"Backup enabled", Info)
  of "n", "no", "off", "disable", "disabled", "false":
    configData.backupEnabled = false
    t.write(2, fgWhite, "Backup disabled\n", resetStyle)
    log(&"Backup disabled", Info)
  else:
    let dir = arg.strip(chars = {'\'', '"'}).normalizePathEnd()
    if not dirExists(dir):
      t.write(2, fgRed, styleBright, "Error: ", fgWhite, "Path provided does not exist:\n  ", fgCyan, dir, "\n", resetStyle)
      quit()
    for kind, path in walkDir(configData.backupDir):
      if kind == pcFile:
        moveFile(path, arg / lastPathPart(path))
    configData.backupDir = arg
    log(&"New backup directory set: {dir}", Info)
    t.write(2, fgWhite, "Backup directory set to: ", fgCyan, dir, "\n", resetStyle)
    t.write(2, fgWhite, "Existing backup files have been moved.\n", resetStyle)

proc setGithubToken*(token: string) =
  configData.githubToken = token
  log(&"Github token set to: {token}", Info)

proc showConfig*() =
  let t = configData.term
  t.write(2, fgWhite, "Logging level: ", fgCyan, $configData.logLevel, "\n", resetStyle)
  t.write(2, fgWhite, "Backups enabled: ", fgCyan, $configData.backupEnabled, "\n", resetStyle)
  if configData.backupEnabled:
    t.write(2, fgWhite, "Backups directory: ", fgCyan, configData.backupDir, "\n", resetStyle)
  if not configData.githubToken.isEmptyOrWhitespace:
    t.write(2, fgWhite, "Github API token is set\n", resetStyle)
  else:
    t.write(2, fgWhite, "Github API token is not set\n", resetStyle)
  quit()

proc setLogLevel*(arg: string) =
  let level = arg.toLower()
  var newLevel: LogLevel
  case level
  of "off": newLevel = Off
  of "debug": newLevel = Debug
  of "warn", "warning": newLevel = Warning
  of "info": newLevel = Info
  of "fatal": newLevel = Fatal
  else: 
    configData.term.write(2, fgRed, styleBright, "Error: ", fgWhite, "Invalid logging level\n", resetStyle) 
    configData.term.write(2, fgWhite, "Valid logging levels are off, info, debug, warn, and fatal\n", resetStyle)
    quit(1)
  configData.logLevel = newLevel

proc setPath*(args: seq[string]) =
  let t = termInit()
  let path = args[^1].strip(chars = {'\'', '"'}).normalizePathEnd()
  if not dirExists(path):
    t.write(2, fgRed, styleBright, "Error: ", fgWhite, "Path provided does not exist:\n  ", fgCyan, path, "\n", resetStyle)
    quit(1)
  configData = Config()
  configData.logLevel = Debug
  configData.backupEnabled = true
  configData.backupDir = path / "Interface" / "hearthsync_backup"
  configData.addonJsonFile = path / "WTF" / "hearthsync.addons"
  configData.installDir = path / "Interface" / "AddOns"
  configData.wowDir = path
  configData.githubToken = ""
  configData.addons = @[]
  writeConfig(configData)
  t.write(0, fgWhite, "Config set. WoW found at: ", fgCyan, path, "\n", resetStyle)
  quit(0)