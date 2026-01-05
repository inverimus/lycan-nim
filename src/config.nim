import std/[json, jsonutils]
import std/options
import std/os
import std/[strformat, strutils]
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
    addonsJson = parseJson(readFile(filename))
  except Exception as e:
    echo &"Fatal error parsing installed addons file: {filename}"
    log(&"Fatal error parsing installed addons file: {filename}", Fatal, e)
    quit()
  for addon in addonsJson:
    var a = new(Addon)
    a.fromJson(addon)
    result.add(a)


let configPath = getCurrentDir() / "lycan.cfg"

proc writeConfig*(config: Config) =
  var json = newJObject()
  json["githubToken"] = %config.githubToken
  json["logLevel"] = %config.logLevel
  
  var existingConfig: JsonNode = newJObject()
  try:
    existingConfig = readFile(configPath).parseJson()
  except:
    discard
  
  json["addonJsonFile"] = %config.addonJsonFile
  json["installDir"] = %config.installDir
  json["backupEnabled"] = %config.backupEnabled
  json["backupDir"] = %config.backupDir
  
  json = existingConfig

  json["backupEnabled"] = %true
  json["installDir"] = %joinPath(getCurrentDir(), "Interface", "AddOns")

  try:
    writeFile(configPath, pretty(json))
    log(&"Configuration file saved: {configPath}", Info)
  except Exception as e:
    log(&"Fatal error writing: {configPath}", Fatal, e)

proc loadConfig*(): Config =
  result = Config()
  result.tempDir = getTempDir()
  result.term = termInit()
  
  var configJson: JsonNode
  try:
    configJson = readFile(configPath).parseJson()
  except:
    result.logLevel = Debug
    result.addonJsonFile = getCurrentDir() / "WTF" / "lycan_addons.json"
    result.installDir = getCurrentDir() / "Interface" / "AddOns"
    result.backupDir = getCurrentDir() / "Interface" / "lycan_backup"
    result.backupEnabled = true
    result.githubToken = ""
    return

  result.installDir = configJson["installDir"].getStr()
  result.addonJsonFile = configJson["addonJsonFile"].getStr()
  result.backupEnabled = configJson["backupEnabled"].getBool()
  result.backupDir = configJson["backupDir"].getStr()
  result.githubToken = configJson["githubToken"].getStr()
  result.logLevel = parseEnum[LogLevel](configJson["logLevel"].getStr())
  
  result.addons = parseInstalledAddons(result.addonJsonFile)   
  log("Configuration loaded", Info)

proc setBackup*(arg: string) =
  case arg.toLower()
  of "y", "yes", "on", "enable", "enabled", "true":
    configData.backupEnabled = true
    log(&"Backup enabled for {configData.mode}", Info)
  of "n", "no", "off", "disable", "disabled", "false":
    configData.backupEnabled = false
    log(&"Backup disabled for {configData.mode}", Info)
  else:
    let dir = arg.strip(chars = {'\'', '"'}).normalizePathEnd()
    if not dirExists(dir):
      echo &"Error: Path provided does not exist:\n  {dir}"
      quit()
    for kind, path in walkDir(configData.backupDir):
      if kind == pcFile:
        moveFile(path, arg / lastPathPart(path))
    configData.backupDir = arg
    log(&"New backup directory set: {dir}", Info)
    echo "Backup directory now ", dir
    echo "Existing backup files have been moved."

proc setGithubToken*(token: string) =
  configData.githubToken = token
  log(&"Github token set to: {token}", Info)

proc showConfig*() =
  echo &"  Logging level: {configData.logLevel}"
  echo &"  Backups enabled: {configData.backupEnabled}"
  if configData.backupEnabled:
    echo &"  Backups directory: {configData.backupDir}"
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
    echo "Valid logging levels are off, info, debug, warn, and fatal"
    quit()
  configData.logLevel = newLevel