import std/options
import std/times

const RETAIL_VERSION* = "12"
const POLLRATE* = 20

type
  Action* = enum
    Install, Update, Remove, List, Pin, Unpin, Restore, Setup, Empty, Help, Name, Export, Reinstall

  LogLevel* = enum
    Off = "OFF",
    Fatal = "FATAL"
    Warning = "WARN"
    Info = "INFO"
    Debug = "DEBUG"
    None = "None"

  Mode* = enum
    Retail = "Retail",
    Vanilla = "Vanilla",
    Classic = "Classic",
    None = "None"

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
    List = "List"
  
  AddonKind* = enum
    Github, GithubRepo, Gitlab, Tukui, Wowint, Curse

  LogMessage* = ref object
    level*: LogLevel
    msg*: string
    e*: ref Exception

  Config* = ref object
    mode*: Mode
    tempDir*: string
    installDir*: string
    backupEnabled*: bool
    backupDir*: string
    addonJsonFile*: string
    addons*: seq[AddonBase]
    term*: Term
    local*: bool
    githubToken*: string
    logLevel*: LogLevel

  AddonBase* = ref object of RootObj
    action*: Action
    state*: AddonState
    name*: string
    overrideName*: Option[string]
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

  AddonGithub* = ref object of AddonBase
    owner*: string
    repo*: string

  AddonGithubRepo* = ref object of AddonBase
    owner*: string
    repo*: string
    branch*: string

  AddonGitlab* = ref object of AddonBase
    owner*: string
    repo*: string
  
  AddonTukui* = ref object of AddonBase
    slug*: string
  
  AddonWowint* = ref object of AddonBase
    projectId*: string
  
  AddonCurse* = ref object of AddonBase
    curseId*: string

  Addon* = AddonGithub | AddonGithubRepo | AddonGitlab | AddonTukui | AddonWowint | AddonCurse

  Term* = ref object
    f*: File
    trueColor*: bool
    x*: int
    y*: int
    yMax*: int