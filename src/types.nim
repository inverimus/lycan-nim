import std/options
import std/times

const POLLRATE* = 20

type
  Action* = enum
    Install, Update, Remove, List, ListAll, Pin, Unpin, Restore, Setup, Help, Name, Reinstall, Revert

  LogLevel* = enum
    Off = "OFF",
    Fatal = "FATAL"
    Warning = "WARN"
    Info = "INFO"
    Debug = "DEBUG"

  AddonState* = enum
    Checking = "Checking",
    Parsing = "Parsing",
    Downloading = "Downloading",
    Installing = "Installing",
    FinishedInstalled = "Installed",
    FinishedUpdated = "Updated",
    FinishedPinned = "Pinned",
    FinishedUpToDate = "Up-to-Date",
    Failed = "Failed",
    Restoring = "Restoring",
    Restored = "Restored",
    Pinned = "Pinned",
    Unpinned = "Unpinned",
    Removed = "Removed",
    NoBackup = "Not Found"
    Renamed = "Renamed"
    Done = "Done"
    DoneFailed = "Failed"
    Listed = "Listed"
  
  AddonKind* = enum
    Github, GithubRepo, Gitlab, Tukui, Wowint, Curse, Wago, Zremax, Legacy

  LogMessage* = ref object
    level*: LogLevel
    msg*: string
    e*: ref Exception

  Config* = ref object
    tempDir*: string
    installDir*: string
    wowDir*: string
    backupEnabled*: bool
    backupDir*: string
    addonJsonFile*: string
    addons*: seq[Addon]
    term*: Term
    local*: bool
    githubToken*: string
    logLevel*: LogLevel
    time*: DateTime

  Addon* = ref object
    action*: Action
    state*: AddonState
    project*: string
    branch*: Option[string]
    name*: string
    overrideName*: Option[string]
    kind*: AddonKind
    version*: string
    startVersion*: string
    gameVersion*: string
    id*: int16
    dirs*: seq[string]
    downloadUrl*: string
    filename*: string
    extractDir*: string
    line*: int
    pinned*: bool
    time*: DateTime
    config*: ptr Config
    errorMsg*: string

  Term* = ref object
    f*: File
    trueColor*: bool
    x*: int
    y*: int
    yMax*: int