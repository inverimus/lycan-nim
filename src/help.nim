import std/terminal

import term

const 
  version = "0.1.0"

proc displayHelp*(option: string = "") =
  let t = termInit()
  
  case option
  of "a", "i", "add", "install":
    t.write(2, fgCyan, "-a, --add <args>", "\n")
    t.write(2, fgCyan, "-i, --install <args>", "\n\n")
    t.write(2, fgWhite, "Installs an addon from a url, addon short name, or file. Supported sites are github releases, github repositories, gitlab releases, tukui, wowinterface, and curseforge.\n\n")
    t.write(2, fgGreen, "EXAMPLES:", "\n")
    t.write(4, fgWhite, "hs -i https://github.com/Stanzilla/AdvancedInterfaceOptions", "\n")
    t.write(4, fgWhite, "hs -i github:Stanzilla/AdvancedInterfaceOptions", "\n")
    t.write(4, "hs -i https://github.com/Tercioo/Plater-Nameplates/tree/master", "\n")
    t.write(4, "hs -i github:Tercioo/Plater-Nameplates@master", "\n")
    t.write(6, fgYellow, "Including the branch will install and track the latest commit to that branch instead of releases.", "\n")
    t.write(4, fgWhite, "hs -i https://gitlab.com/woblight/actionmirroringframe", "\n")
    t.write(4, fgWhite, "hs -i gitlab:woblight/actionmirroringframe", "\n")
    t.write(4, "hs -i https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html", "\n")
    t.write(4, "hs -i wowint:24608", "\n")
    t.write(4, "hs -i https://www.tukui.org/elvui", "\n")
    t.write(4, "hs -i tukui:elvui", "\n")
    t.write(4, "hs -i https://www.curseforge.com/api/v1/mods/334372/files/4956577/download", "\n")
    t.write(4, "hs -i curse:334372", "\n")
    t.write(6, fgYellow, "To get this url, go the addon page and click download, then click the download button, then copy the link for 'try again.'", "\n")
    t.write(6, fgYellow, "For curseforge, using the Project ID is easier. Locate the ID on the right side of the addon page.", "\n")
    t.write(4, fgWhite, "hs -i https://addons.wago.io/addons/rarescanner", "\n")
    t.write(4, fgWhite, "hs -i wago:rarescanner", "\n")


  of "c", "config":
    t.write(2, fgCyan, "-c, --config [options]", "\n\n")
    t.write(2, fgWhite, "Sets various configuration options. If no options are provided, displays the current configuration.\n\n")
    t.write(2, fgGreen, "OPTIONS:", "\n")
    t.write(4, fgCyan, "backup [path|on|off]\n")
    t.write(6, fgWhite, "Replace path with the location of the backup directory. The default is located inside the WoW Interface directory.\n")
    t.write(6, "On or off enables or disables backups respectively.\n")
    t.write(4, fgCyan, "github <token>\n")
    t.write(6, fgWhite, "Sets a github personal access token. This may be required if you get 403 forbidden responses from github for too may requests.\n")

  of "l", "list":
    t.write(2, fgCyan, "-l, --list [options]", "\n\n")
    t.write(2, fgWhite, "Lists installed addons. The default order is alphabetical.\n\n")
    t.write(2, fgGreen, "OPTIONS:", "\n")
    t.write(4, fgCyan, "[t|time]\n")
    t.write(6, fgWhite, "Sort by most recent install or update time.\n\n")

  else:
    t.write(2, false, fgGreen, "HearthSync", fgYellow, " ", version, fgWhite, " by Michael Green\n\n", resetStyle)
    t.write(2, true, fgCyan, "-a, --add <addon>")
    t.write(30, false, fgWhite, "Install an addon.", "\n")
    t.write(2, true, fgCyan, "-c, --config [options]")
    t.write(30, false, fgWhite, "Configuration options.", "\n")
    t.write(6, true, fgCyan, "--help")
    t.write(30, false, fgWhite, "Display this message.", "\n")
    t.write(2, true, fgCyan, "-i, --install <args>")
    t.write(30, false, fgWhite, "Alias for --add", "\n")
    t.write(2, true, fgCyan, "-l, --list [options]")
    t.write(30, false, fgWhite, "List installed addons sorted by name.", "\n")
    t.write(2, true, fgCyan, "-n, --name <id> <name>")
    t.write(30, false, fgWhite, "Set your own <name> for addon with <id>. Must use quotes around <name> if it contains spaces.\n")
    t.write(30, false, fgWhite, "Leave <name> blank to go back to the default name.\n")
    t.write(6, true, fgCyan, "--pin <ids>")
    t.write(30, false, fgWhite, "Pin addon to current version. Addon will not be updated until unpinned.", "\n")
    t.write(2, true, fgCyan, "-r, --remove <ids>")
    t.write(30, false, fgWhite, "Remove installed addons by id number", "\n")
    t.write(6, true, fgCyan, "--reinstall")
    t.write(30, false, fgWhite, "Force a reinstall of all addons. Can be used to restore from an existing hs_addons.json file.", "\n")
    t.write(6, true, fgCyan, "--restore <ids>")
    t.write(30, false, fgWhite, "Restore addons to the version prior to last update. Backups must be enabled.", "\n")
    t.write(6, true, fgCyan, "--unpin")
    t.write(30, false, fgWhite, "Unpin addon to restore updates.", "\n")
    t.write(2, true, fgCyan, "-u, --update")
    t.write(30, false, fgWhite, "Update all installed addons. The default if no arguments are given.", "\n")
  quit()