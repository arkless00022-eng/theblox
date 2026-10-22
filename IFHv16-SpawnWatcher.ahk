#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Client"
CoordMode "Pixel", "Screen"
SetKeyDelay 50, 30
SetDefaultMouseSpeed 0

; =====================================================================
;  Item Factory Helper  -  F6 = start/stop,  F7 = test click positions
; =====================================================================

; ---------------- CONFIG (tweak if clicks land in the wrong spot) -----
RobloxWin := "ahk_exe RobloxPlayerBeta.exe"
IniFile   := A_ScriptDir "\ItemFactoryHelper.ini"

LeftX     := 0.001                       ; click near the left edge of the upgrade buttons
Rows := [
    Map("name", "Conveyor",  "y", 0.368),
    Map("name", "Molder",    "y", 0.445),
    Map("name", "Upgrader",  "y", 0.519),
    Map("name", "Enchanter", "y", 0.594),
    Map("name", "Appraiser", "y", 0.669),
]
CloseX   := 0.727, CloseY   := 0.183     ; red X on the popup
AttackX  := 0.500, AttackY  := 0.500     ; middle of the screen
ChatToggleX := 138, ChatToggleY := 34 ; fixed client pixels: Roblox chat bubble in the top-left bar

; "Join The Arena?" prompt: green Queue (left) + red Close (right), under the upgrade list
QueueL := 0.000, QueueT := 0.78, QueueR := 0.085, QueueB := 0.92
QueueBtnX := 0.038, QueueBtnY := 0.825
QueueColor := 0x31A709                 ; lime of the Queue button (RGB)
QueueTol   := 48
QueueCloseColor := 0xC41A1A            ; red of the Close button beside it
QueueCloseTol   := 55

LogDir := EnvGet("LOCALAPPDATA") "\Roblox\logs"
DisconnectRegex := "Disconnection Notification|disconnect with reason: [1-9]\d*|ID_CONNECTION_LOST|Connection lost"
StaleLogSeconds := 0

DialogColor := 0x393B3D
DialogTol   := 8

ChatL := Number(IniRead(IniFile, "chat", "L", "0.003"))
ChatT := Number(IniRead(IniFile, "chat", "T", "0.055"))
ChatR := Number(IniRead(IniFile, "chat", "R", "0.370"))
ChatB := Number(IniRead(IniFile, "chat", "B", "0.430"))
ManualChatL := ChatL, ManualChatT := ChatT, ManualChatR := ChatR, ManualChatB := ChatB

global running := false
global cycles := 0
global lastLaunch := 0
global joinPending := false
global startTick := 0
global logPath := ""
global logPos := 0
global abort := false
global dlgStrikes := 0
global arenaClicked := false
global arenaClickTick := 0
global arenaGone := 0
global arenaTries := 0
global calibStep := 0
global calibX := 0
global calibY := 0
global Tips := Map()
global spawnRunning := false
global spawnCapturing := false
global macroCycleBusy := false
global chatReviewHoverActive := false
global chatReviewHoverHwnd := 0
global SpawnSent := Map()
global SpawnPending := Map()
global SpawnVotes := Map()
global SpawnLastWebhookMessageId := ""
global SpawnLastWebhookError := ""
global SpawnLogLines := []
global SpawnRobloxExe := "ahk_exe RobloxPlayerBeta.exe"
global spawnPsFile := A_ScriptDir "\spawn_ocr.ps1"
global SpawnLogFile := A_ScriptDir "\spawn_log.txt"
global SpawnSampleDir := A_ScriptDir "\OCR Samples"
global chatAreaDetectionDone := false
global GitHubRepo := Trim(IniRead(IniFile, "updates", "githubRepo", ""))
global DupSeconds := 3600 ; suppress repeats of the same event for 1 hour
global DupSimilarity := 0.70
global MathRetryAt := 0
global MathAnswered := Map()

; ---------------- GUI ----------------
g := Gui(, "Item Factory Helper")
g.BackColor := "14141F"
g.MarginX := 20, g.MarginY := 14

; ===== Top bar =====
g.SetFont("s20 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x20 y12 w320", "Item Factory Helper")
g.SetFont("s9 Norm c8A8AA8", "Segoe UI")
g.Add("Text", "x22 y50 w420", "Auto-attack  |  auto-upgrade  |  chat math  |  private server  |  FPS limit")

g.SetFont("s13 Bold cFF5C5C", "Segoe UI")
statusTxt := g.Add("Text", "x360 y22 w300 Center", "● STOPPED")

g.SetFont("s11 Bold cFFFFFF", "Segoe UI")
toggleBtn := g.Add("Button", "x690 y14 w290 h46", "Start   (F6)")
toggleBtn.OnEvent("Click", Toggle)
g.SetFont("s9 Norm cFFFFFF", "Segoe UI")
helpBtn := g.Add("Button", "x690 y62 w174 h20", "?  How to use (quick start)")
helpBtn.OnEvent("Click", ShowHelp)
updateBtn := g.Add("Button", "x870 y62 w110 h20", "Check updates")
updateBtn.OnEvent("Click", CheckForUpdates)

tab := g.Add("Tab3", "x10 y82 w980 h470", ["Macro", "Spawn Watcher"])
tab.UseTab(1)

; ===== Column 1: Attack =====
g.SetFont("s10 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x20 y108 w290", "ATTACK")
g.SetFont("s10 Norm cE6E6F0", "Segoe UI")
cbAtk := g.Add("Checkbox", "x20 y136 w290 -Theme cE6E6F0", "Auto-attack (click middle of screen)")
cbAtk.Value := IniRead(IniFile, "main", "atkOn", "1")
g.Add("Text", "x20 y171 w290", "Attack every 0.5 sec when free")
g.Add("Text", "x20 y199 w300", "Chat checks run throughout the session")
cbEquip := g.Add("Checkbox", "x20 y232 w200 -Theme cE6E6F0", "Press hotbar key on start:")
cbEquip.Value := IniRead(IniFile, "main", "equipOn", "0")
edSlot := g.Add("Edit", "x225 y229 w80 Center Limit1", IniRead(IniFile, "main", "slot", "1"))

; ===== Column 2: Upgrades =====
g.SetFont("s10 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x340 y108 w290", "UPGRADES")
g.SetFont("s10 Norm cE6E6F0", "Segoe UI")
rowY := 136
for r in Rows {
    g.Add("Text", "x340 y" (rowY + 2) " w110", r["name"])
    r["up"] := g.Add("Checkbox", "x455 y" rowY " w170 -Theme cE6E6F0", "Auto-upgrade")
    r["up"].Value := IniRead(IniFile, "rows", r["name"], "1")
    rowY += 28
}
g.SetFont("s8 Norm c8A8AA8", "Segoe UI")
g.Add("Text", "x340 y278 w300", "10 attempts per selected upgrade, every 8 min")
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
g.Add("Text", "x340 y309 w300", "Chat checks and attacks fit between clicks")

; ===== Chat math =====
g.SetFont("s10 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x20 y294 w290", "CHAT MATH")
g.SetFont("s10 Norm cE6E6F0", "Segoe UI")
cbMath := g.Add("Checkbox", "x20 y322 w300 -Theme cE6E6F0", "Auto-answer math prompts")
cbMath.Value := IniRead(IniFile, "main", "mathOn", "0")
cbMath.OnEvent("Click", MathToggleChanged)
g.SetFont("s8 Norm c8A8AA8", "Segoe UI")
mathStatusTxt := g.Add("Text", "x20 y350 w300 h25 0x200", cbMath.Value ? "Math: enabled; starts with F6" : "Math: off")

; ===== Column 3: Private server + FPS + Arena Queue =====
g.SetFont("s10 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x660 y108 w320", "PRIVATE SERVER")
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
edLink := g.Add("Edit", "x660 y136 w320", IniRead(IniFile, "main", "link", ""))
edLink.OnEvent("Change", (*) => IniWrite(edLink.Value, IniFile, "main", "link"))
g.SetFont("s10 Norm cFFFFFF", "Segoe UI")
joinBtn := g.Add("Button", "x660 y166 w110 h30", "Join now")
joinBtn.OnEvent("Click", (*) => LaunchServer())
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
cbAuto := g.Add("Checkbox", "x782 y171 w200 -Theme cE6E6F0", "Auto-rejoin (closed / dropped)")
cbAuto.Value := IniRead(IniFile, "main", "autojoin", "1")
cbAuto.OnEvent("Click", (*) => IniWrite(cbAuto.Value, IniFile, "main", "autojoin"))

g.SetFont("s10 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x660 y208 w150", "ROBLOX FPS LIMIT")
readabilityBtn := g.Add("Button", "x824 y204 w156 h28", "OCR settings")
readabilityBtn.OnEvent("Click", SetOcrSettings)
g.SetFont("s10 Norm cE6E6F0", "Segoe UI")
g.Add("Text", "x660 y238 w80", "Max FPS:")
edFps := g.Add("Edit", "x740 y235 w70 Number Center", IniRead(IniFile, "main", "fps", "30"))
g.SetFont("s10 Norm cFFFFFF", "Segoe UI")
fpsApply := g.Add("Button", "x822 y232 w75 h30", "Apply")
fpsApply.OnEvent("Click", ApplyFps)
fpsClear := g.Add("Button", "x903 y232 w77 h30", "Reset")
fpsClear.OnEvent("Click", ClearFps)
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
cbLock := g.Add("Checkbox", "x660 y265 w320 -Theme cE6E6F0", "Lock file (read-only) so Roblox can't reset it")
cbLock.Value := IniRead(IniFile, "main", "lock", "1")
cbLock.OnEvent("Click", (*) => IniWrite(cbLock.Value, IniFile, "main", "lock"))

g.SetFont("s10 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x660 y294 w320", "ARENA QUEUE")
g.SetFont("s10 Norm cE6E6F0", "Segoe UI")
cbArena := g.Add("Checkbox", "x660 y322 w320 -Theme cE6E6F0", "Auto-join Arena queue")
cbArena.Value := IniRead(IniFile, "main", "arenaOn", "1")
cbArena.OnEvent("Click", (*) => IniWrite(cbArena.Value, IniFile, "main", "arenaOn"))

; ===== Footer =====
g.SetFont("s10 Norm cFFFFFF", "Segoe UI")
testBtn := g.Add("Button", "x20 y494 w180 h30", "Test positions (F7)")
testBtn.OnEvent("Click", TestPositions)
g.SetFont("s9 Norm c8A8AA8", "Segoe UI")
cycleTxt := g.Add("Text", "x210 y494 w150 h30 0x200", "Upgrades: 0 | 00:00:00")
g.Add("Text", "x340 y494 w640 h30 Right 0x200",
    "Running minimizes this window. Press F6 anywhere to stop. Hover any control for help.")

tab.UseTab(2)
g.SetFont("s12 Bold cFFC83D", "Segoe UI")
g.Add("Text", "x35 y116 w900 h28", "SPAWN WATCHER")
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
g.Add("Text", "x35 y146 w150", "Discord webhook:")
edHook := g.Add("Edit", "x190 y143 w560 Password", IniRead(IniFile, "spawn", "webhook", ""))
edHook.OnEvent("Change", (*) => IniWrite(Trim(edHook.Value), IniFile, "spawn", "webhook"))
hookBtn := g.Add("Button", "x765 y141 w180 h28", "Test webhook")
hookBtn.OnEvent("Click", SpawnTestWebhook)
g.Add("Text", "x35 y180 w150", "Alt label:")
edLabel := g.Add("Edit", "x190 y177 w200", IniRead(IniFile, "spawn", "label", "Alt"))
edLabel.OnEvent("Change", (*) => IniWrite(Trim(edLabel.Value), IniFile, "spawn", "label"))
g.Add("Text", "x410 y180 w370", "F6 finds chat in 5 captures, then locks it for the run")
g.Add("Text", "x35 y213 w150", "Spawn keywords:")
edKeys := g.Add("Edit", "x190 y210 w755", IniRead(IniFile, "spawn", "keywords", "appeared"))
edKeys.OnEvent("Change", (*) => IniWrite(Trim(edKeys.Value), IniFile, "spawn", "keywords"))
g.Add("Text", "x35 y246 w150", "Ignore lines with:")
edIgnore := g.Add("Edit", "x190 y243 w755", IniRead(IniFile, "spawn", "ignore", ""))
edIgnore.OnEvent("Change", (*) => IniWrite(Trim(edIgnore.Value), IniFile, "spawn", "ignore"))
g.SetFont("s8 Norm c8A8AA8", "Segoe UI")
g.Add("Text", "x190 y267 w755", "Comma-separated. A line must contain a keyword and none of the ignore words.")
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
g.Add("Text", "x35 y296 w150", "Alt server link:")
edServerLink := g.Add("Edit", "x190 y293 w755", IniRead(IniFile, "spawn", "serverLink", ""))
edServerLink.OnEvent("Change", (*) => IniWrite(Trim(edServerLink.Value), IniFile, "spawn", "serverLink"))
g.Add("Text", "x35 y329 w150", "Champion role ID:")
edRole := g.Add("Edit", "x190 y326 w755", IniRead(IniFile, "spawn", "championRoleId", ""))
edRole.OnEvent("Change", (*) => IniWrite(Trim(edRole.Value), IniFile, "spawn", "championRoleId"))
g.Add("Text", "x35 y358 w150", "Minimum RNG to send:")
edPingRng := g.Add("Edit", "x190 y355 w120", IniRead(IniFile, "spawn", "pingRngMin", "0"))
edPingRng.OnEvent("Change", (*) => IniWrite(Trim(edPingRng.Value), IniFile, "spawn", "pingRngMin"))
g.SetFont("s8 Norm c8A8AA8", "Segoe UI")
g.Add("Text", "x320 y360 w155", "Legendary Gems bypass it")
g.SetFont("s9 Norm cE6E6F0", "Segoe UI")
cbSpawn := g.Add("Checkbox", "x490 y358 w330 -Theme cE6E6F0", "Run watcher together with F6")
cbSpawn.Value := IniRead(IniFile, "spawn", "enabled", "0")
cbSpawn.OnEvent("Click", (*) => IniWrite(cbSpawn.Value, IniFile, "spawn", "enabled"))
cbSamples := g.Add("Checkbox", "x35 y382 w440 -Theme cE6E6F0", "Save last 200 checks (chat images + OCR text)")
cbSamples.Value := IniRead(IniFile, "spawn", "saveSamples", "0")
cbSamples.OnEvent("Click", (*) => IniWrite(cbSamples.Value, IniFile, "spawn", "saveSamples"))
cbSkipElites := g.Add("Checkbox", "x490 y382 w390 -Theme cE6E6F0", "Skip Elite alerts")
cbSkipElites.Value := IniRead(IniFile, "spawn", "championsOnly", "0")
cbSkipElites.OnEvent("Click", SpawnSetSkipElites)
areaSpawnBtn := g.Add("Button", "x35 y412 w150 h30", "Manual area (F8)")
areaSpawnBtn.OnEvent("Click", SetChatArea)
readSpawnBtn := g.Add("Button", "x195 y412 w140 h30", "Test read now")
readSpawnBtn.OnEvent("Click", SpawnTestRead)
spawnStatusTxt := g.Add("Text", "x350 y417 w590 h24 0x200", "Watcher: off (enable above; F6 starts it)")
logBox := g.Add("Edit", "x35 y452 w910 h60 ReadOnly Multi")
for ctrl in [edHook, edLabel, edKeys, edIgnore, edServerLink, edRole, edPingRng, logBox]
    ctrl.SetFont("c14141F")
tab.UseTab()

for ctrl in [edSlot, edLink, edFps]
    ctrl.SetFont("c14141F")

Tip(toggleBtn, "Start or stop everything. Hotkey: F6.")
Tip(helpBtn, "Short step-by-step guide.")
Tip(cbAtk, "Clicks the middle every 0.5 seconds when OCR and upgrades are not using the mouse.")
Tip(cbMath, "Uses the Spawn Watcher's multi-frame OCR. It only types an answer after at least four OCR reads agree across multiple captures.")
Tip(cbEquip, "Press slot key on start.")
Tip(edSlot, "Hotbar slot.")
for r in Rows
    Tip(r["up"], "Every 8 minutes, performs 10 click-and-close attempts for " r["name"] ".")
Tip(edLink, "Private server link.")
Tip(joinBtn, "Opens link.")
Tip(cbAuto, "Auto-rejoin on crash.")
Tip(edFps, "FPS limit.")
Tip(readabilityBtn, "Close Roblox, then set graphics quality to 1, background transparency to fully opaque, and preferred text size to its largest setting.")
Tip(fpsApply, "Apply limit.")
Tip(fpsClear, "Reset limit.")
Tip(cbLock, "Read-only lock.")
Tip(cbArena, "Clicks the green Queue button in the Join The Arena prompt.")
Tip(testBtn, "Test click spots. Hotkey: F7.")
    Tip(areaSpawnBtn, "Fallback manual chat region. F6 auto-finds the chat area from five captures, then keeps it fixed for that run.")
Tip(updateBtn, "Set the public GitHub source once or check now. New releases install automatically while the macro is stopped.")
Tip(cbSamples, "Saves chat crops and OCR text for the latest 200 checks in an OCR Samples folder next to this script.")
Tip(cbSkipElites, "When enabled, Elite alerts are skipped regardless of RNG. Champion and Gem alerts can still be sent if they meet the RNG minimum.")
Tip(readSpawnBtn, "Read the chat and show spawn messages that match.")
Tip(edPingRng, "Only send recognized webhook messages whose numeric RNG is at least this value. Legendary Gem drops always send regardless of RNG. Use 0 for no minimum.")
OnMessage(0x200, ShowTip)

g.OnEvent("Close", (*) => (SaveAll(), ExitApp()))
EnsureSpawnOcrScript()
g.Show("w1000 h565 x" Max(0, (A_ScreenWidth - 1000) // 2) " y" Max(0, A_ScreenHeight - 650))
if GitHubRepo != ""
    SetTimer(AutoCheckForUpdates, -1500)

F6:: Toggle()
F7:: TestPositions()
F8:: CalibKey()

; ---------------- helpers ----------------
CheckForUpdates(*) {
    global running
    if running {
        MsgBox("Stop the macro before checking or installing an update.", "Check updates")
        return
    }
    CheckForUpdatesCore(false)
}

AutoCheckForUpdates() {
    global GitHubRepo, running
    if running || Trim(GitHubRepo) = ""
        return
    CheckForUpdatesCore(true)
}

CheckForUpdatesCore(automatic := false) {
    global GitHubRepo, IniFile
    repo := Trim(GitHubRepo)
    if repo = "" {
        if automatic
            return
        answer := InputBox("Enter the public GitHub repository as owner/repository.`nExample: yourname/ItemFactoryHelper", "Set update source")
        if answer.Result != "OK"
            return
        repo := Trim(answer.Value)
        if !RegExMatch(repo, "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
            MsgBox("Use the GitHub account and repository name, separated by /.", "Check updates")
            return
        }
        GitHubRepo := repo
        IniWrite(repo, IniFile, "updates", "githubRepo")
    }
    if StrLower(SubStr(A_ScriptFullPath, -4)) != ".ahk" {
        MsgBox("The updater can only replace an .ahk script. Run the downloaded AHK file directly.", "Check updates")
        return
    }

    url := "https://github.com/" repo "/releases/latest/download/IFHv16-SpawnWatcher.ahk"
    tempFile := A_Temp "\IFHv16-update-" A_Pid ".ahk"
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(5000, 5000, 10000, 30000)
        request.Open("GET", url, false)
        request.SetRequestHeader("User-Agent", "ItemFactoryHelper-Updater")
        request.Send()
        if request.Status != 200 {
            if !automatic
                MsgBox("GitHub returned HTTP " request.Status ". Check that the repository is public and its latest release includes the asset named:`nIFHv16-SpawnWatcher.ahk", "Check updates")
            return
        }
        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(request.ResponseBody)
        stream.SaveToFile(tempFile, 2)
        stream.Close()
        remoteText := FileRead(tempFile, "UTF-8")
        if !InStr(SubStr(remoteText, 1, 512), "#Requires AutoHotkey v2.0") || !InStr(remoteText, "Item Factory Helper") {
            if !automatic
                MsgBox("The GitHub asset doesn't look like this helper's AHK script, so it wasn't installed.", "Check updates")
            return
        }
        localText := FileRead(A_ScriptFullPath, "UTF-8")
        if StrReplace(remoteText, "`r`n", "`n") = StrReplace(localText, "`r`n", "`n") {
            if !automatic
                MsgBox("This copy already matches the latest GitHub release.", "Check updates")
            return
        }
        if !automatic && MsgBox("A different AHK file is available from " repo ". Install it and restart now?", "Update available", "YesNo Iconi") != "Yes"
            return
        FileCopy(tempFile, A_ScriptFullPath, true)
        FileDelete(tempFile)
        if !automatic
            MsgBox("Update installed. The helper will restart with the new script.", "Check updates")
        Reload()
    } catch as e {
        if !automatic
            MsgBox("Couldn't check or install the GitHub update:`n" e.Message, "Check updates")
    } finally {
        if FileExist(tempFile) {
            try FileDelete(tempFile)
        }
    }
}

SpawnSetStatus(text, color) {
    spawnStatusTxt.Text := "Watcher: " StrReplace(text, "● ")
    spawnStatusTxt.SetFont("c" color)
}

SpawnLog(text) {
    global SpawnLogLines
    line := FormatTime(, "HH:mm:ss") "  " text
    SpawnLogLines.Push(line)
    while SpawnLogLines.Length > 14
        SpawnLogLines.RemoveAt(1)
    out := ""
    for l in SpawnLogLines
        out .= (out = "" ? "" : "`r`n") l
    logBox.Value := out
    try FileAppend(line "`n", SpawnLogFile, "UTF-8")
}

SplitList(s) {
    out := []
    for part in StrSplit(StrLower(s), ",") {
        part := Trim(part)
        if part != ""
            out.Push(part)
    }
    return out
}

JsonEsc(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`t", " ")
    return s
}

; Dice coefficient on letter pairs: 1 = identical, 0 = nothing alike.
Dice(a, b) {
    if StrLen(a) < 2 || StrLen(b) < 2
        return (a = b) ? 1 : 0
    pairs := Map()
    loop StrLen(a) - 1 {
        k := SubStr(a, A_Index, 2)
        pairs[k] := pairs.Has(k) ? pairs[k] + 1 : 1
    }
    common := 0
    loop StrLen(b) - 1 {
        k := SubStr(b, A_Index, 2)
        if pairs.Has(k) && pairs[k] > 0 {
            common += 1
            pairs[k] -= 1
        }
    }
    return 2 * common / (StrLen(a) + StrLen(b) - 2)
}

; ---------------- Roblox windows ----------------
GetRobloxWindows() {
    out := []
    for id in WinGetList(SpawnRobloxExe) {
        try {
            if WinGetMinMax("ahk_id " id) = -1
                continue
            WinGetClientPos(&x, &y, &w, &h, "ahk_id " id)
            if w < 200 || h < 200
                continue
            out.Push(id)
        }
    }
    n := out.Length                      ; sort ascending so "#1, #2 ..." stay stable
    loop n - 1 {
        i := A_Index + 1
        v := out[i]
        j := i - 1
        while j >= 1 && out[j] > v {
            out[j + 1] := out[j]
            j -= 1
        }
        out[j + 1] := v
    }
    return out
}

WindowsToWatch() {
    wins := GetRobloxWindows()
    ; This build watches one alt/window at a time.
    return wins.Length ? [wins[1]] : []
}

LabelFor() {
    return Trim(edLabel.Value)
}

; ---------------- OCR ----------------
SpawnOcrWindow(hwnd, &lines, coordinated := false, forceHover := false, keepHover := false, shotCount := 4) {
    global spawnCapturing, macroCycleBusy, running, cbSamples, SpawnSampleDir
    lines := []
    id := "ahk_id " hwnd
    if !WinExist(id) {
        lines := ["ERROR: window is gone"]
        return false
    }
    WinGetClientPos(&cx, &cy, &cw, &ch, id)
    relX := Round(cw * ChatL), relY := Round(ch * ChatT)
    w := Round(cw * (ChatR - ChatL)), h := Round(ch * (ChatB - ChatT))
    x := cx + relX, y := cy + relY
    if w < 20 || h < 20 {
        lines := ["ERROR: chat area is too small - use Set chat area"]
        return false
    }
    out := A_ScriptDir "\spawn_ocr_" hwnd ".txt"
    try FileDelete(out)
    sampleArgs := cbSamples.Value ? ' -SaveSamples -SampleDir "' SpawnSampleDir '"' : ""
    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' spawnPsFile '" -X ' x ' -Y ' y ' -W ' w ' -H ' h ' -Txt "' out '" -ShotCount ' shotCount sampleArgs
    if (!coordinated && macroCycleBusy) || spawnCapturing {
        lines := ["ERROR: macro is using the screen; retry shortly"]
        return false
    }
    spawnCapturing := true
    hovered := false
    try {
        if forceHover {
            MouseGetPos(&oldMouseX, &oldMouseY)
            hovered := true
            ; Mouse coordinates are client-relative; x/y above are screen coordinates.
            MouseMove(relX + Min(3, w - 1), relY + Round(h / 2), 0)
            Sleep(350)
        }
        RunWait(cmd, A_ScriptDir, "Hide")
    } catch as e {
        lines := ["ERROR: couldn't start PowerShell (" e.Message ")"]
        return false
    } finally {
        try {
            if hovered && !keepHover
                MouseMove(oldMouseX, oldMouseY, 0)
        } finally {
            spawnCapturing := false
        }
    }
    if !FileExist(out) {
        lines := ["ERROR: no OCR result file"]
        return false
    }
    raw := Trim(FileRead(out, "UTF-8"), " `t`r`n")
    if SubStr(raw, 1, 6) = "ERROR:" {
        lines := [raw]
        return false
    }
    for line in StrSplit(raw, "`n", "`r") {
        if SubStr(line, 1, 2) = "L|"
            lines.Push(SubStr(line, 3))
        else if SubStr(line, 1, 2) = "B|"
            lines.Push("")
    }
    return true
}

; On F6 start, scan the Roblox upper-left corner five times. Use the chat
; header or bottom-row controls as landmarks, take the median bounds, and keep
; that region fixed for the run. The manual F8 area remains the fallback.
SpawnDetectChatArea(hwnd, &newL, &newT, &newR, &newB) {
    global spawnCapturing, spawnPsFile, chatReviewHoverActive, chatReviewHoverHwnd
    global ManualChatT
    newL := newT := newR := newB := 0
    id := "ahk_id " hwnd
    if !WinExist(id) || spawnCapturing
        return false
    WinGetClientPos(&cx, &cy, &cw, &ch, id)
    scanW := Round(cw * 0.58), scanH := Round(ch * 0.62)
    if scanW < 220 || scanH < 180
        return false

    out := A_Temp "\IFHv16-chat-detect-" hwnd ".txt"
    try FileDelete(out)
    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' spawnPsFile '" -X ' cx ' -Y ' cy ' -W ' scanW ' -H ' scanH ' -Txt "' out '" -ShotCount 5 -DetectArea'
    MouseGetPos(&oldMouseX, &oldMouseY)
    spawnCapturing := true
    chatReviewHoverHwnd := hwnd
    chatReviewHoverActive := true
    SetTimer(RefreshChatReviewHover, 500)
    try {
        RefreshChatReviewHover()
        Sleep(400)
        RunWait(cmd, A_ScriptDir, "Hide")
    } catch {
        return false
    } finally {
        chatReviewHoverActive := false
        SetTimer(RefreshChatReviewHover, 0)
        try MouseMove(oldMouseX, oldMouseY, 0)
        spawnCapturing := false
    }
    if !FileExist(out)
        return false
    raw := Trim(FileRead(out, "UTF-8"), " `t`r`n")
    try FileDelete(out)
    if SubStr(raw, 1, 6) = "ERROR:"
        return false

    frames := Map()
    for line in StrSplit(raw, "`n", "`r") {
        if SubStr(line, 1, 2) != "P|"
            continue
        fields := StrSplit(line, "|")
        if fields.Length < 7
            continue
        frameNo := fields[2]
        label := StrLower(Trim(fields[3]))
        box := Map("x", Number(fields[4]), "y", Number(fields[5]), "w", Number(fields[6]), "h", Number(fields[7]))
        if !frames.Has(frameNo)
            frames[frameNo] := Map("here", [], "friends", [], "unlock", [], "input", [], "body", [])
        frame := frames[frameNo]
        if RegExMatch(label, "^\W*here\W*$")
            frame["here"].Push(box)
        else if RegExMatch(label, "^\W*friends\W*$")
            frame["friends"].Push(box)
        else if InStr(label, "unlock chat")
            frame["unlock"].Push(box)
        else if InStr(label, "to chat") || (InStr(label, "click here") && InStr(label, "press"))
            frame["input"].Push(box)
        else if InStr(label, "appeared") || InStr(label, "rng") || InStr(label, "gem has fallen")
            frame["body"].Push(box)
    }

    rects := []
    for frameNo, frame in frames {
        here := SpawnAverageBoxes(frame["here"])
        friends := SpawnAverageBoxes(frame["friends"])
        unlock := SpawnAverageBoxes(frame["unlock"])
        input := SpawnAverageBoxes(frame["input"])
        body := frame["body"]
        if IsObject(here) && IsObject(friends) {
            hereCenter := here["x"] + here["w"] / 2
            friendsCenter := friends["x"] + friends["w"] / 2
            tabGap := friendsCenter - hereCenter
            if tabGap < 20
                continue
            left := Max(0, hereCenter - tabGap / 2 - Round(cw * 0.008))
            right := Min(scanW, friendsCenter + tabGap / 2 + Round(cw * 0.012))
            top := Min(here["y"], friends["y"]) - Round(ch * 0.012)
        } else if IsObject(input) {
            center := input["x"] + input["w"] / 2
            left := 0
            right := Min(scanW, center * 2 + Round(cw * 0.01))
            top := IsObject(unlock) ? unlock["y"] : input["y"]
        } else if IsObject(unlock) {
            center := unlock["x"] + unlock["w"] / 2
            left := 0
            right := Min(scanW, center * 2 - Round(cw * 0.035))
            top := unlock["y"] - Round(ch * 0.28)
        } else {
            continue
        }

        if body.Length {
            minBodyY := 100000, maxBodyBottom := 0, maxBodyRight := 0
            for bodyBox in body {
                minBodyY := Min(minBodyY, bodyBox["y"])
                maxBodyBottom := Max(maxBodyBottom, bodyBox["y"] + bodyBox["h"])
                maxBodyRight := Max(maxBodyRight, bodyBox["x"] + bodyBox["w"])
            }
            if !IsObject(here) && !IsObject(friends)
                top := minBodyY - Round(ch * 0.012)
            if !IsObject(unlock) && !IsObject(input)
                bottom := maxBodyBottom + Round(ch * 0.045)
            else if IsObject(unlock)
                bottom := Max(maxBodyBottom, unlock["y"] + unlock["h"]) + Round(ch * 0.012)
            else
                bottom := Max(maxBodyBottom, input["y"] + input["h"]) + Round(ch * 0.012)
            right := Min(scanW, Max(right, maxBodyRight + Round(cw * 0.01)))
        } else {
            if IsObject(unlock)
                bottom := unlock["y"] + unlock["h"] + Round(ch * 0.012)
            else if IsObject(input)
                bottom := input["y"] + input["h"] + Round(ch * 0.012)
            else
                bottom := Min(scanH, Round(ch * 0.43))
        }
        if !body.Length && !IsObject(here) && !IsObject(friends)
            top := Round(ch * ManualChatT)
        top := Max(0, top)
        bottom := Min(scanH, bottom)
        if right - left < 160 || bottom - top < Round(ch * 0.12)
            continue
        rects.Push(Map("l", left / cw, "t", top / ch, "r", right / cw, "b", bottom / ch))
    }
    if rects.Length < 3
        return false

    lefts := [], tops := [], rights := [], bottoms := []
    for rect in rects {
        lefts.Push(rect["l"]), tops.Push(rect["t"]), rights.Push(rect["r"]), bottoms.Push(rect["b"])
    }
    newL := Round(SpawnMedian(lefts), 4)
    newT := Round(SpawnMedian(tops), 4)
    newR := Round(SpawnMedian(rights), 4)
    newB := Round(SpawnMedian(bottoms), 4)
    return newR > newL && newB > newT
}

SpawnAverageBoxes(boxes) {
    if !boxes.Length
        return ""
    x := 0, y := 0, w := 0, h := 0
    for box in boxes {
        x += box["x"], y += box["y"], w += box["w"], h += box["h"]
    }
    return Map("x", x / boxes.Length, "y", y / boxes.Length, "w", w / boxes.Length, "h", h / boxes.Length)
}

SpawnMedian(values) {
    sorted := []
    for value in values {
        pos := 1
        while pos <= sorted.Length && sorted[pos] <= value
            pos += 1
        sorted.InsertAt(pos, value)
    }
    n := sorted.Length
    if Mod(n, 2)
        return sorted[(n + 1) // 2]
    return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
}

EnsureChatAreaForRun(hwnd) {
    global chatAreaDetectionDone, ChatL, ChatT, ChatR, ChatB
    global ManualChatL, ManualChatT, ManualChatR, ManualChatB
    if chatAreaDetectionDone
        return
    chatAreaDetectionDone := true
    if SpawnDetectChatArea(hwnd, &newL, &newT, &newR, &newB) {
        ChatL := newL, ChatT := newT, ChatR := newR, ChatB := newB
        SpawnLog("chat area auto-detected from five captures and locked for this run")
        ToolTip("Chat area found and locked for this run.", A_ScreenWidth - 320, A_ScreenHeight - 50)
        SetTimer(ClearTip, -3000)
    } else {
        ChatL := ManualChatL, ChatT := ManualChatT, ChatR := ManualChatR, ChatB := ManualChatB
        SpawnLog("chat area detection could not verify a stable panel; using the saved manual area")
        ToolTip("Chat location wasn't clear; using saved manual area.", A_ScreenWidth - 320, A_ScreenHeight - 50)
        SetTimer(ClearTip, -4000)
    }
}

; Briefly move away and re-hover the chat during long OCR reviews. Roblox fades
; the opaque chat background shortly after the pointer stops hovering.
RefreshChatReviewHover() {
    global chatReviewHoverActive, chatReviewHoverHwnd, ChatL, ChatT, ChatR, ChatB
    if !chatReviewHoverActive || !WinExist("ahk_id " chatReviewHoverHwnd)
        return
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " chatReviewHoverHwnd)
        relX := Round(cw * ChatL), relY := Round(ch * ChatT)
        w := Round(cw * (ChatR - ChatL)), h := Round(ch * (ChatB - ChatT))
        ; The Roblox window is active throughout review, so these are client coords.
        MouseMove(Round(cw * 0.5), Round(ch * 0.5), 0)
        MouseMove(relX + Min(3, w - 1), relY + Round(h / 2), 0)
    }
}

; Canonicalize recurring OCR mistakes before validating a spawn announcement.
SpawnNormalizeOcrText(text) {
    ; Repair recurring, unambiguous OCR substitutions from observed chat.
    text := RegExReplace(text, "i)\+[lI](?=\s)", "+1")
    text := RegExReplace(text, "i)\bEd[jd]pse\b", "Eclipse")
    text := RegExReplace(text, "i)\bEline\b", "Elite")
    text := RegExReplace(text, "i)\bANoobis\b", "Anubis")
    text := RegExReplace(text, "i)\b(?:Elitels|Elimegs|IEDimeOs|El\s+IP|Eli-i-|Flite's?)\s+D?omain\b", "Elite's Domain")
    text := RegExReplace(text, "i)\bChampion(?:l|')?s\s+Isle\b", "Champion's Isle")
    ; Accept common OCR substitutions in the RNG label (including RNC/ANG),
    ; then standardize the outgoing webhook text to RNG.
    text := RegExReplace(text, "i)\(\s*[RA][NM][GQCL](?=\s*[\d,])", "(RNG")

    ; Use the spawn-message vocabulary as context for small OCR misspellings.
    ; This fixes words such as "appearec", "Elitc", or "Doman" without
    ; guessing at arbitrary creature names or numeric values.
    text := SpawnRepairKnownWords(text)
    text := SpawnNormalizeKnownLocation(text)

    appearedAt := InStr(StrLower(text), "appeared")
    if !appearedAt
        return text
    subject := StrLower(Trim(SubStr(text, 1, appearedAt - 1)))
    ; A Champion event with only "Isle" remaining can be repaired from its
    ; subject and the game's known Champion area.
    if InStr(subject, "champion") && RegExMatch(text, "i)\bappeared\s+in\s+Isle\b")
        text := RegExReplace(text, "i)\bappeared\s+in\s+Isle\b", "appeared in Champion's Isle")

    ; These area names identify the spawn class if OCR dropped its final word.
    if RegExMatch(text, "i)\bappeared\s+in\s+Champion's Isle\b") {
        if !InStr(subject, "champion")
            text := SubStr(text, 1, appearedAt - 1) " Champion" SubStr(text, appearedAt)
    } else if RegExMatch(text, "i)\bappeared\s+in\s+(?:Elite's Domain|Island of Kings|Duelist Island)\b") {
        if !InStr(subject, "elite") && !InStr(subject, "champion")
            text := SubStr(text, 1, appearedAt - 1) " Elite" SubStr(text, appearedAt)
    } else if RegExMatch(text, "i)\bappeared\s+in\s+Domain\b") {
        ; OCR sometimes drops both "Elite" and the possessive area prefix,
        ; leaving only "appeared in Domain". Restore the known Elite area.
        if !InStr(subject, "elite") && !InStr(subject, "champion")
            text := SubStr(text, 1, appearedAt - 1) " Elite" SubStr(text, appearedAt)
        text := RegExReplace(text, "i)\bappeared\s+in\s+Domain\b", "appeared in Elite's Domain")
    }

    ; If the spawn shape and RNG marker are clear but OCR mangled the value
    ; (for example, "RNG trus 1"), keep the alert with an explicit unknown
    ; value. Another OCR pass with the actual number will replace this version.
    if RegExMatch(text, "i)\(\s*RNG\s+([^)]*)\)?\s*$", &rngTail) {
        rawRng := Trim(rngTail[1])
        if rawRng != "" && !RegExMatch(rawRng, "^\d[\d,]*(?:\.\d+)?$") && RegExMatch(rawRng, "\d")
            text := RegExReplace(text, "i)\(\s*RNG\s+[^)]*\)?\s*$", "(RNG ?)")
    }
    return text
}

; Normalize only the game's observed location names. Word-level OCR repair
; runs first, then these phrase patterns restore dropped words and canonical
; capitalization for spawn announcements and Gem drops.
SpawnNormalizeKnownLocation(text) {
    anchor := "i)(\b(?:appeared\s+in|down\s+onto)\s+)"
    text := RegExReplace(text, anchor . "(?:Duelist|Duellist)\s+Island\b", "$1Duelist Island")
    text := RegExReplace(text, anchor . "(?:Island\s+(?:of\s+)?Kings|Isle\s+of\s+Kings)\b", "$1Island of Kings")
    text := RegExReplace(text, anchor . "Champion(?:'s|s)?\s+Isle\b", "$1Champion's Isle")

    ; Domain is unique to Elite's Domain. OCR sometimes turns its prefix into
    ; unrelated or accented characters ("IEDimeOs Domain", "ÍÉ0jmeOs Domain",
    ; "Elite L Domain") or drops it. Match the area by its final known word.
    text := RegExReplace(text, anchor . "(?:[^\s!?.(),;:]+\s+){0,3}Domain\b", "$1Elite's Domain")
    return text
}

SpawnRepairKnownWords(text) {
    repaired := ""
    word := ""
    i := 1
    textLen := StrLen(text)
    while i <= textLen {
        char := SubStr(text, i, 1)
        if RegExMatch(char, "^[A-Za-z]$") || (char = "'" && word != "") {
            word .= char
        } else {
            if word != "" {
                repaired .= SpawnCorrectKnownWord(word)
                word := ""
            }
            repaired .= char
        }
        i += 1
    }
    if word != ""
        repaired .= SpawnCorrectKnownWord(word)
    return repaired
}

SpawnCorrectKnownWord(word) {
    static known := [
        "Impossible", "Eclipse", "Divine", "Eternal", "Opulent", "Zenith", "Radiant", "Godly",
        "Shiny", "Neon", "Zombie", "Speedster", "Skeleton", "Iron", "Fire", "Turkey", "Leg",
        "Traffic", "Cone", "Rocket", "Burst", "Disco", "Giant", "Noob", "Wizard", "Mafia",
        "Scythe", "Ice", "Boomer", "Pocket", "Elite", "Champion", "appeared", "Island", "Kings",
        "Duelist", "Domain", "RNG", "Isle", "Elite's", "Champion's"
    ]
    target := StrLower(word)
    if target = "rng" || target = "rnc" || target = "ang"
        return "RNG"
    for canonical in known {
        canonicalLower := StrLower(canonical)
        maxDistance := StrLen(canonical) >= 8 ? 2 : 1
        if Abs(StrLen(target) - StrLen(canonicalLower)) <= maxDistance
            && SpawnEditDistance(target, canonicalLower) <= maxDistance
            return canonical
    }
    return word
}

SpawnEditDistance(a, b) {
    a := StrLower(a), b := StrLower(b)
    lenA := StrLen(a), lenB := StrLen(b)
    previous := []
    Loop lenB + 1
        previous.Push(A_Index - 1)
    i := 1
    while i <= lenA {
        current := [i]
        j := 1
        while j <= lenB {
            cost := SubStr(a, i, 1) = SubStr(b, j, 1) ? 0 : 1
            current.Push(Min(current[j] + 1, previous[j + 1] + 1, previous[j] + cost))
            j += 1
        }
        previous := current
        i += 1
    }
    return previous[lenB + 1]
}

; Returns complete spawn candidates that haven't been reported yet.
; Join wrapped spawn and Gem-fall announcements before validating them.
SpawnFindSpawns(hwnd, lines, &alreadySeen) {
    global SpawnSent, cbSkipElites
    alreadySeen := []
    keys := SplitList(edKeys.Value)
    ign := SplitList(edIgnore.Value)
    candidates := []
    if !SpawnSent.Has(hwnd)
        SpawnSent[hwnd] := []
    list := SpawnSent[hwnd]
    i := list.Length
    while i >= 1 {                       ; forget old entries
        if A_TickCount - list[i][2] > DupSeconds * 1000
            list.RemoveAt(i)
        i -= 1
    }
    for idx, raw in lines {
        line := Trim(raw)
        if StrLen(line) < 3
            continue
        ; Chat can wrap both the mob name and the RNG value across lines.
        text := line
        prevIdx := idx
        prepended := 0
        lowerText := StrLower(text)
        targetPos := InStr(lowerText, "appeared")
        if !targetPos
            targetPos := InStr(lowerText, "gem has fallen")
        if targetPos {
            subject := Trim(SubStr(text, 1, targetPos - 1))
            while !RegExMatch(subject, "i)^a(?:n)?\s+\S+") && prevIdx > 1 && prepended < 2 {
                prev := Trim(lines[prevIdx - 1])
                if StrLen(prev) < 3 || RegExMatch(prev, "[)!?.]$")
                    break
                text := prev " " text
                prevIdx -= 1
                prepended += 1
                lowerText := StrLower(text)
                targetPos := InStr(lowerText, "appeared")
                if !targetPos
                    targetPos := InStr(lowerText, "gem has fallen")
                subject := targetPos ? Trim(SubStr(text, 1, targetPos - 1)) : ""
            }
        }
        nextIdx := idx
        extra := 0
        while nextIdx < lines.Length && extra < 3 {
            needsRngTail := InStr(text, "(") && !InStr(text, ")")
            if !needsRngTail && InStr(StrLower(text), "appeared in") {
                nxt := Trim(lines[nextIdx + 1])
                ; The area or the parenthesized value can wrap onto another line.
                needsRngTail := RegExMatch(text, "i)\bappeared\s+in\s*$")
                    || RegExMatch(nxt, "^\s*\(")
            }
            if !needsRngTail && RegExMatch(text, "i)\bGem\s+has\b")
                needsRngTail := !RegExMatch(text, "i)\(\s*[RA][NM][GQCL]\s*[\d,]+(?:\.\d+)?\s*\)")
            if !needsRngTail && RegExMatch(text, "i)^\s*a(?:n)?\s+.+?\bGem\b")
                needsRngTail := !RegExMatch(text, "i)\(\s*[RA][NM][GQCL]\s*[\d,]+(?:\.\d+)?\s*\)")
            if !needsRngTail
                break
            nextIdx += 1
            extra += 1
            nxt := Trim(lines[nextIdx])
            if nxt = ""
                break
            text .= " " nxt
        }

        text := SpawnNormalizeOcrText(text)
        tlow := StrLower(text)
        gemEvent := SpawnIsGemEvent(text)
        hit := gemEvent
        appearedAt := InStr(tlow, "appeared")
        if appearedAt && InStr(SubStr(tlow, 1, appearedAt - 1), "champion")
            hit := true
        for k in keys
            if InStr(tlow, k)
                hit := true
        if !hit
            continue

        ; Recognize the announcement by its shape, without depending on OCR's
        ; spelling of the RNG label: article + subject + appeared in + area +
        ; parenthesized number. This tolerates readings such as "ANG 26,842".
        appearedAt := InStr(tlow, "appeared")
        if !appearedAt && !gemEvent
            continue
        if cbSkipElites.Value && SpawnIsElite(text)
            continue
        if !gemEvent {
            subject := Trim(SubStr(tlow, 1, appearedAt - 1))
            tail := Trim(SubStr(tlow, appearedAt + StrLen("appeared")))
            if (
                !RegExMatch(subject, "i)^a(?:n)?\s+[a-z][a-z0-9+'-]*(?:\s+[a-z0-9][a-z0-9+'-]*)+$")
                || !RegExMatch(tail, "i)^in\s+.+?\s*\(\s*(?:[RA][NM][GQCL]\s*)?(?:\d[\d,]*(?:\.\d+)?|\?)\s*\)?\s*$")
            )
                continue
        }

        ; Apply the minimum to every recognized RNG-bearing alert, except
        ; Legendary Gem drops, which are always eligible regardless of RNG.
        if !SpawnMeetsRngMinimum(text)
            continue

        bad := false
        for w in ign
            if InStr(tlow, w)
                bad := true
        if bad
            continue
        norm := RegExReplace(tlow, "[^a-z0-9]", "")
        candidates.Push(Map("text", text, "norm", norm, "score", SpawnCandidateScore(text)))
    }

    ; The OCR passes and repeated frames can produce partial variants of the
    ; same spawn. Keep the strongest version before persistent de-duplication.
    best := []
    for c in candidates {
        matched := false
        for i, kept in best {
            if SpawnSameEvent(c["text"], kept["text"]) {
                if c["score"] > kept["score"]
                    best[i] := c
                matched := true
                break
            }
        }
        if !matched
            best.Push(c)
    }

    found := []
    for c in best {
        dup := false
        for e in list {
            if SpawnSameEvent(c["text"], e[1]) {
                dup := true
                break
            }
        }
        if dup {
            isListed := false
            for prior in alreadySeen {
                if SpawnSameEvent(c["text"], prior) {
                    isListed := true
                    break
                }
            }
            if !isListed
                alreadySeen.Push(c["text"])
            continue
        }
        found.Push(c["text"])
    }
    return found
}

SpawnCandidateScore(text) {
    clean := RegExReplace(StrLower(text), "[^a-z0-9]+", " ")
    score := StrLen(clean)
    for word in StrSplit(Trim(clean), A_Space) {
        if StrLen(word) > 1
            score += 100 + StrLen(word)
    }
    ; Prefer complete spawn announcements when repeated OCR shots disagree.
    ; These are ranking hints only; they don't require a fixed creature name.
    if InStr(clean, "appeared in")
        score += 500
    if RegExMatch(text, "i)\b(?:Elite|Champion)\s+appeared\s+in\b")
        score += 100
    if RegExMatch(text, "i)\b(?:Elite's Domain|Island of Kings|Duelist Island|Champion's Isle)\b")
        score += 100
    if InStr(clean, "rng")
        score += 180
    if RegExMatch(clean, "i)\brng\s+\d")
        score += 250
    if SpawnIsGemEvent(text)
        score += 500
    if InStr(text, "!")
        score += 25
    return score
}

; Compare event fields separately. Keep the numeric value exact so two real
; spawns with similar names and areas are not merged; OCR-known word variants
; and area aliases are normalized before this comparison.
SpawnSameEvent(textA, textB) {
    global DupSimilarity
    gemPattern := "i)^\s*a(?:n)?\s+(.+?)\s+Gem\s+has\s+fallen\s+out\s+of\s+the\s+sky\s+down\s+onto\s+(.+?)!?\s*\(\s*RNG\s+([\d,]+(?:\.\d+)?)\s*\)\s*$"
    isGemA := RegExMatch(textA, gemPattern, &gemA)
    isGemB := RegExMatch(textB, gemPattern, &gemB)
    if isGemA || isGemB {
        if !isGemA || !isGemB
            return false
        if StrReplace(gemA[3], ",") != StrReplace(gemB[3], ",")
            return false
        nameA := RegExReplace(StrLower(gemA[1]), "[^a-z0-9]", "")
        nameB := RegExReplace(StrLower(gemB[1]), "[^a-z0-9]", "")
        areaA := RegExReplace(StrLower(gemA[2]), "[^a-z0-9]", "")
        areaB := RegExReplace(StrLower(gemB[2]), "[^a-z0-9]", "")
        return Dice(nameA, nameB) >= Max(DupSimilarity, 0.88) && Dice(areaA, areaB) >= 0.86
    }
    pattern := "i)^\s*a(?:n)?\s+(.+?)\s+appeared\s+in\s+(.+?)\s*\(\s*(?:[RA][NM][GQCL]\s*)?(\d[\d,]*(?:\.\d+)?|\?)"
    if !RegExMatch(textA, pattern, &eventA)
        return false
    if !RegExMatch(textB, pattern, &eventB)
        return false
    rngA := StrReplace(eventA[3], ",")
    rngB := StrReplace(eventB[3], ",")
    if rngA != "?" && rngB != "?" && rngA != rngB
        return false
    subjectA := RegExReplace(StrLower(eventA[1]), "[^a-z0-9]", "")
    subjectB := RegExReplace(StrLower(eventB[1]), "[^a-z0-9]", "")
    areaA := RegExReplace(StrLower(eventA[2]), "[^a-z0-9]", "")
    areaB := RegExReplace(StrLower(eventB[2]), "[^a-z0-9]", "")
    if Dice(areaA, areaB) < 0.86
        return false
    return Dice(subjectA, subjectB) >= Max(DupSimilarity, 0.88)
}

SpawnGetVoteGroups(hwnd) {
    global SpawnVotes
    if !SpawnVotes.Has(hwnd)
        SpawnVotes[hwnd] := []
    groups := SpawnVotes[hwnd]
    i := groups.Length
    while i >= 1 {
        if groups[i]["queued"] || A_TickCount - groups[i]["lastSeen"] > 120000
            groups.RemoveAt(i)
        i -= 1
    }
    return groups
}

SpawnRememberEvent(hwnd, text) {
    global SpawnSent
    if !SpawnSent.Has(hwnd)
        SpawnSent[hwnd] := []
    SpawnSent[hwnd].Push([text, A_TickCount])
}

SpawnQueueAlert(hwnd, text) {
    global SpawnPending
    if !SpawnPending.Has(hwnd)
        SpawnPending[hwnd] := []
    pending := SpawnPending[hwnd]
    for item in pending
        if SpawnSameEvent(text, item["text"])
            return false
    pending.Push(Map("text", text, "attempts", 0, "nextAt", A_TickCount))
    return true
}

SpawnFlushPending(hwnd) {
    global SpawnPending, cbSkipElites
    if !SpawnPending.Has(hwnd)
        return
    pending := SpawnPending[hwnd]
    i := pending.Length
    while i >= 1 {
        item := pending[i]
        if A_TickCount < item["nextAt"] {
            i -= 1
            continue
        }
        if cbSkipElites.Value && SpawnIsElite(item["text"]) {
            pending.RemoveAt(i)
            i -= 1
            continue
        }
        if !SpawnMeetsRngMinimum(item["text"]) {
            pending.RemoveAt(i)
            SpawnLog("queued alert skipped (below minimum RNG): " SubStr(item["text"], 1, 75))
            i -= 1
            continue
        }
        if SpawnNotify(LabelFor(), item["text"]) {
            SpawnRememberEvent(hwnd, item["text"])
            pending.RemoveAt(i)
        } else {
            item["attempts"] += 1
            backoff := 5000
            Loop Min(item["attempts"] - 1, 4)
                backoff *= 2
            item["nextAt"] := A_TickCount + Min(60000, backoff)
        }
        i -= 1
    }
}

SpawnNeedsExtraOcr(voteGroups, scanStart) {
    for group in voteGroups {
        if group["lastSeen"] < scanStart
            continue
        if group["seen"] < 2 || InStr(group["text"], "(RNG ?)")
            return true
    }
    return false
}

SpawnIsChampion(text) {
    return RegExMatch(text, "i)\bChampion\s+appeared\s+in\b")
}

SpawnIsElite(text) {
    if SpawnIsChampion(text) || SpawnIsGemEvent(text)
        return false
    return RegExMatch(text, "i)\bElite\s+appeared\s+in\b")
        || RegExMatch(text, "i)\bappeared\s+in\s+(?:[^\s!?.(),;:]+\s+){0,3}Domain\b")
}

SpawnIsGemEvent(text) {
    return RegExMatch(text, "i)^\s*a(?:n)?\s+.+?\s+Gem\s+has\s+fallen\s+out\s+of\s+the\s+sky\s+down\s+onto\s+.+!?\s*\(\s*RNG\s+[\d,]+(?:\.\d+)?\s*\)\s*$")
}

SpawnIsLegendaryGem(text) {
    return SpawnIsGemEvent(text) && RegExMatch(text, "i)\bLegendary\b")
}

SpawnSetSkipElites(*) {
    global cbSkipElites, IniFile, SpawnPending
    IniWrite(cbSkipElites.Value, IniFile, "spawn", "championsOnly")
    if !cbSkipElites.Value
        return
    ; A toggle should also affect alerts already waiting for a webhook retry.
    for hwnd, pending in SpawnPending {
        i := pending.Length
        while i >= 1 {
            if SpawnIsElite(pending[i]["text"])
                pending.RemoveAt(i)
            i -= 1
        }
    }
    SpawnLog("Elite filter enabled; queued Elite alerts cleared")
}

SpawnUpdatePendingAlert(hwnd, text) {
    global SpawnPending
    if !SpawnPending.Has(hwnd)
        return
    for item in SpawnPending[hwnd] {
        if SpawnSameEvent(text, item["text"]) && SpawnCandidateScore(text) > SpawnCandidateScore(item["text"]) {
            item["text"] := text
            return
        }
    }
}

; Count a spawn only when separate OCR treatments or frames agree on it.
SpawnTallyPass(hwnd, passLines, voteGroups, prime := false) {
    alreadySeen := []
    for text in SpawnFindSpawns(hwnd, passLines, &alreadySeen) {
        norm := RegExReplace(StrLower(text), "[^a-z0-9]", "")
        score := SpawnCandidateScore(text)
        matched := false
        for group in voteGroups {
            if SpawnSameEvent(text, group["text"]) {
                group["seen"] += 1
                group["lastSeen"] := A_TickCount
                if score > group["score"] {
                    group["text"] := text
                    group["norm"] := norm
                    group["score"] := score
                    if group["queued"] && !prime
                        SpawnUpdatePendingAlert(hwnd, text)
                }
                matched := true
                if group["seen"] >= 2 && !group["queued"] {
                    group["queued"] := true
                    if prime {
                        SpawnRememberEvent(hwnd, group["text"])
                        SpawnLog("startup baseline confirmed in " group["seen"] " OCR reads: " SubStr(group["text"], 1, 95))
                    } else {
                        wasQueued := SpawnQueueAlert(hwnd, group["text"])
                        SpawnLog("spawn matched " group["seen"] " OCR reads; " (wasQueued ? "queued" : "already queued") ": " SubStr(group["text"], 1, 95))
                    }
                }
                break
            }
        }
        if !matched {
            voteGroups.Push(Map("text", text, "norm", norm, "score", score, "seen", 1, "queued", false, "lastSeen", A_TickCount))
            SpawnLog((prime ? "startup candidate seen once; not baselined yet: " : "spawn candidate seen once; holding for another read: ") SubStr(text, 1, 95))
        }
    }
}

SpawnTallyOcrLines(hwnd, lines, voteGroups, prime := false) {
    passLines := []
    for line in lines {
        if Trim(line) = "" {
            if passLines.Length
                SpawnTallyPass(hwnd, passLines, voteGroups, prime)
            passLines := []
        } else {
            passLines.Push(line)
        }
    }
    if passLines.Length
        SpawnTallyPass(hwnd, passLines, voteGroups, prime)
}

; ---------------- chat math, using the same multi-frame OCR pass ----------------
MathCollectQuestionVotes(lines, votes) {
    blockText := ""
    sawPrompt := false
    for line in lines {
        clean := Trim(line)
        if clean = "" {
            if blockText != "" {
                MathCollectQuestionBlock(blockText, votes, &sawPrompt)
                blockText := ""
            }
        } else {
            blockText .= (blockText = "" ? "" : " ") clean
        }
    }
    if blockText != ""
        MathCollectQuestionBlock(blockText, votes, &sawPrompt)
    return sawPrompt
}

MathCollectQuestionBlock(text, votes, &sawPrompt) {
    if RegExMatch(text, "i)\bReward\b|\bWhat\s+[il1t][s5]\b")
        sawPrompt := true
    if !MathParseQuestion(text, &a, &op, &b)
        return
    key := a "|" op "|" b
    if !votes.Has(key)
        votes[key] := Map("count", 0, "a", a, "op", op, "b", b)
    votes[key]["count"] += 1
}

MathGetConsensus(votes, &a, &op, &b, &voteCount) {
    best := "", bestCount := 0, tied := false
    for key, vote in votes {
        if vote["count"] > bestCount {
            best := key
            bestCount := vote["count"]
            tied := false
        } else if vote["count"] = bestCount {
            tied := true
        }
    }
    voteCount := bestCount
    ; Three treatments come from each captured frame; four matching reads
    ; therefore require agreement from more than one screenshot.
    if bestCount < 4 || tied
        return false
    vote := votes[best]
    a := vote["a"], op := vote["op"], b := vote["b"]
    return true
}

MathParseQuestion(raw, &a, &op, &b) {
    a := 0, op := "", b := 0
    bestPos := 0
    pos := 1
    while RegExMatch(raw, "i)(?:What\s+[il1t][s5]|Rewa?rd\W{0,3})\s*(\d+)\s*([²³]|\^\s*[23])", &m, pos) {
        if m.Pos >= bestPos {
            bestPos := m.Pos
            a := Integer(m[1]), op := (InStr(m[2], "³") || InStr(m[2], "3") ? "cube" : "sq"), b := 0
        }
        pos := m.Pos + m.Len
    }
    pos := 1
    while RegExMatch(raw, "i)(?:What\s+[il1t][s5]|Rewa?rd\W{0,3})\s*(\d+)\s+([23])\s*\?", &m, pos) {
        if m.Pos >= bestPos {
            bestPos := m.Pos
            a := Integer(m[1]), op := (m[2] = "3" ? "cube" : "sq"), b := 0
        }
        pos := m.Pos + m.Len
    }
    pos := 1
    while RegExMatch(raw, "i)(?:What\s+[il1t][s5]|Rewa?rd\W{0,3})\s*(\d+)\s*([x×*÷/:>+\-−–])\s*(\d+)", &m, pos) {
        if m.Pos >= bestPos {
            symbol := m[2]
            if InStr("xX×*", symbol)
                op := "x"
            else if InStr("÷/:>", symbol)
                op := "÷"
            else if symbol = "+"
                op := "+"
            else
                op := "-"
            bestPos := m.Pos
            a := Integer(m[1]), b := Integer(m[3])
        }
        pos := m.Pos + m.Len
    }
    pos := 1
    while RegExMatch(raw, "i)(?:What\s+[il1t][s5]|Rewa?rd\W{0,3})\s*([√∛vyj¥✓\\(\[{/|'<]{1,2})\s*(\d+)", &m, pos) {
        if m.Pos >= bestPos {
            bestPos := m.Pos
            a := Integer(m[2]), op := (InStr(m[1], "∛") ? "cbrt" : "sqrt"), b := 0
        }
        pos := m.Pos + m.Len
    }
    return bestPos > 0
}

MathQuestionText(a, op, b) {
    switch op {
        case "sq":   return a "²"
        case "cube": return a "³"
        case "sqrt": return "√" a
        case "cbrt": return "∛" a
    }
    return a " " op " " b
}

MathToggleChanged(*) {
    global cbMath, mathStatusTxt, IniFile
    IniWrite(cbMath.Value, IniFile, "main", "mathOn")
    mathStatusTxt.Text := cbMath.Value ? "Math: enabled; starts with F6" : "Math: off"
}

MathSolve(a, op, b, &answer) {
    switch op {
        case "x":
            answer := a * b
        case "÷":
            if b = 0 || Mod(a, b) != 0
                return false
            answer := a // b
        case "+":
            answer := a + b
        case "-":
            answer := a - b
        case "sq":
            answer := a * a
        case "cube":
            answer := a * a * a
        case "sqrt":
            root := Round(Sqrt(a))
            if root * root != a
                return false
            answer := root
        case "cbrt":
            root := Round(a ** (1 / 3))
            if root * root * root != a
                return false
            answer := root
        default:
            return false
    }
    return true
}

MathAnswerChat(answer) {
    global RobloxWin, chatReviewHoverActive
    if !WinExist(RobloxWin)
        return false
    wasReviewing := chatReviewHoverActive
    if wasReviewing {
        chatReviewHoverActive := false
        SetTimer(RefreshChatReviewHover, 0)
    }
    try {
        FocusRoblox()
        Sleep(150)
        WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
        MouseMove(Round(cw * 0.5), Round(ch * 0.5), 0)
        Sleep(40)
        Click()
        Sleep(200)
        SendEvent("/")
        Sleep(300)
        SendEvent("{Text}" answer)
        Sleep(200)
        SendEvent("{Enter}")
        Sleep(300)
        return true
    } finally {
        if wasReviewing {
            chatReviewHoverActive := true
            SetTimer(RefreshChatReviewHover, 500)
        }
    }
}

MathTryAnswer(votes, sawPrompt) {
    global cbMath, MathRetryAt, MathAnswered, mathStatusTxt
    if !cbMath.Value || !sawPrompt
        return
    if !MathGetConsensus(votes, &a, &op, &b, &voteCount) {
        mathStatusTxt.Text := "Math prompt unclear; no answer typed."
        MathRetryAt := A_TickCount + 7000
        return
    }
    now := A_TickCount
    expiredQuestions := []
    for key, tick in MathAnswered {
        if now - tick > 600000
            expiredQuestions.Push(key)
    }
    for key in expiredQuestions
        MathAnswered.Delete(key)
    questionKey := a "|" op "|" b
    if MathAnswered.Has(questionKey) {
        mathStatusTxt.Text := "Math: already answered this prompt."
        return
    }
    if !MathSolve(a, op, b, &answer) {
        mathStatusTxt.Text := "Math: couldn't solve " MathQuestionText(a, op, b) "."
        return
    }
    if MathAnswerChat(answer) {
        MathAnswered[questionKey] := now
        MathRetryAt := now + 2000
        mathStatusTxt.Text := "Last: " MathQuestionText(a, op, b) " = " answer "  (" FormatTime(, "HH:mm:ss") ")"
    } else {
        mathStatusTxt.Text := "Math: Roblox window not available."
    }
}

; ---------------- webhook ----------------
SpawnHookUrlOk(url) {
    return RegExMatch(url, "i)^https://(\w+\.)?(discord|discordapp)\.com/api/webhooks/\d+/[\w\-]+")
}

SpawnSendWebhook(url, content, pingRoleId := "") {
    global SpawnLastWebhookMessageId, SpawnLastWebhookError
    SpawnLastWebhookMessageId := ""
    SpawnLastWebhookError := ""
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(3000, 3000, 3000, 5000)
        sendUrl := url
        if RegExMatch(sendUrl, "i)[?&]wait=")
            sendUrl := RegExReplace(sendUrl, "i)([?&]wait=)[^&]*", "$1true")
        else
            sendUrl .= InStr(sendUrl, "?") ? "&wait=true" : "?wait=true"
        http.Open("POST", sendUrl, false)
        http.SetRequestHeader("Content-Type", "application/json")
        allowed := '{"parse":[]}'
        if RegExMatch(pingRoleId, "^\d{17,20}$")
            allowed := '{"parse":[],"roles":["' pingRoleId '"]}'
        http.Send('{"content":"' JsonEsc(content) '","flags":4,"allowed_mentions":' allowed '}')
        if http.Status = 200 {
            body := http.ResponseText
            idPattern := Chr(34) "id" Chr(34) "\s*:\s*" Chr(34) "(\d+)" Chr(34)
            if RegExMatch(body, idPattern, &messageMatch)
                SpawnLastWebhookMessageId := messageMatch[1]
        } else {
            SpawnLastWebhookError := http.ResponseText
        }
        return http.Status
    } catch as e {
        SpawnLastWebhookError := e.Message
        return "ERROR " e.Message
    }
}

SpawnTestWebhook(*) {
    global SpawnLastWebhookMessageId
    url := Trim(edHook.Value)
    if !SpawnHookUrlOk(url) {
        MsgBox("Paste a Discord webhook URL first (Channel settings > Integrations > Webhooks > Copy Webhook URL).", "Spawn Watcher")
        return
    }
    st := SpawnSendWebhook(url, "Spawn Watcher test from " Trim(edLabel.Value))
    if st = 200 && SpawnLastWebhookMessageId != ""
        MsgBox("Discord confirmed the test message. Message ID: " SpawnLastWebhookMessageId, "Spawn Watcher")
    else
        MsgBox("The test wasn't confirmed. Discord answered: " st "`n`n401/404 usually means the webhook URL is wrong or deleted.", "Spawn Watcher")
}

SpawnBuildAlert(label, text, &pingRoleId) {
    global edServerLink, edRole
    msg := (label != "" ? "[" label "] " : "") text
    link := Trim(edServerLink.Value)
    if link != ""
        msg .= " • [Private server](" link ")"
    pingRoleId := ""
    spawnName := StrLower(text)
    appearedAt := InStr(spawnName, "appeared")
    if appearedAt
        spawnName := SubStr(spawnName, 1, appearedAt - 1)
    if InStr(spawnName, "champion") && SpawnMeetsRngMinimum(text) {
        candidate := Trim(edRole.Value)
        if RegExMatch(candidate, "^\d{17,20}$") {
            pingRoleId := candidate
            msg .= "`n<@&" pingRoleId ">"
        }
    }
    return msg
}

SpawnParsePingRng(&minimum) {
    global edPingRng
    raw := Trim(edPingRng.Value)
    if raw = ""
        raw := "0"
    if !RegExMatch(raw, "^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$")
        return false
    minimum := Number(StrReplace(raw, ",", ""))
    return true
}

SpawnMeetsRngMinimum(text) {
    if !SpawnParsePingRng(&minimum)
        return false
    if SpawnIsLegendaryGem(text)
        return true
    if minimum <= 0
        return true
    if !RegExMatch(text, "i)\(\s*RNG\s+([\d,]+(?:\.\d+)?)\s*\)", &rngMatch)
        return false
    rngValue := Number(StrReplace(rngMatch[1], ",", ""))
    return rngValue >= minimum
}

SpawnNotify(label, text) {
    global SpawnLastWebhookMessageId, SpawnLastWebhookError
    roleId := ""
    msg := SpawnBuildAlert(label, text, &roleId)
    url := Trim(edHook.Value)
    st := SpawnSendWebhook(url, msg, roleId)
    pingRejected := false
    if st = 400 && roleId != "" {
        ; Preserve the spawn alert if Discord rejects the configured role mention.
        fallbackMsg := StrReplace(msg, "`n<@&" roleId ">", "")
        st := SpawnSendWebhook(url, fallbackMsg)
        msg := fallbackMsg
        pingRejected := true
    }
    if st = 200 && SpawnLastWebhookMessageId != "" {
        SpawnLog("sent (confirmed" (pingRejected ? "; role ping omitted" : "") "; ID " SpawnLastWebhookMessageId "): " SubStr(msg, 1, 100))
        return true
    }
    detail := Trim(SpawnLastWebhookError)
    if detail != ""
        detail := " - " SubStr(detail, 1, 140)
    SpawnLog("webhook unconfirmed (HTTP " st "; queued for retry" (pingRejected ? "; ping fallback failed" : "") "): " SubStr(msg, 1, 75) detail)
    return false
}

; ---------------- run loop ----------------
; First pass: remember what is already in chat so old spawn lines aren't re-sent.
SpawnPrime() {
    for hwnd in WindowsToWatch() {
        lines := []
        primeVotes := []
        if SpawnOcrWindow(hwnd, &lines, false, true)
            SpawnTallyOcrLines(hwnd, lines, primeVotes, true)
    }
}

SpawnReviewCheck(hwnd) {
    global chatReviewHoverActive, chatReviewHoverHwnd, cbSpawn, spawnRunning, cbMath, MathRetryAt
    MouseGetPos(&oldMouseX, &oldMouseY)
    watchSpawns := cbSpawn.Value && spawnRunning
    voteGroups := watchSpawns ? SpawnGetVoteGroups(hwnd) : []
    mathVotes := Map()
    mathPromptSeen := false
    scanStart := A_TickCount
    chatReviewHoverHwnd := hwnd
    chatReviewHoverActive := true
    SetTimer(RefreshChatReviewHover, 500)
    try {
        lines := []
        ocrOk := SpawnOcrWindow(hwnd, &lines, true, true, true)
        if ocrOk {
            if watchSpawns
                SpawnTallyOcrLines(hwnd, lines, voteGroups)
            if cbMath.Value
                mathPromptSeen := MathCollectQuestionVotes(lines, mathVotes)
            ; Most checks stay at four frames (12 OCR treatments). Take extra
            ; frames when a spawn or math prompt is still ambiguous.
            needSpawnMore := watchSpawns && SpawnNeedsExtraOcr(voteGroups, scanStart)
            needMathMore := false
            if cbMath.Value && mathPromptSeen && A_TickCount >= MathRetryAt
                needMathMore := !MathGetConsensus(mathVotes, &qa, &qop, &qb, &qv)
            if needSpawnMore || needMathMore {
                extraLines := []
                if SpawnOcrWindow(hwnd, &extraLines, true, false, true, 2) {
                    if watchSpawns
                        SpawnTallyOcrLines(hwnd, extraLines, voteGroups)
                    if cbMath.Value
                        mathPromptSeen := MathCollectQuestionVotes(extraLines, mathVotes) || mathPromptSeen
                }
                needSpawnMore := watchSpawns && SpawnNeedsExtraOcr(voteGroups, scanStart)
                needMathMore := false
                if cbMath.Value && mathPromptSeen && A_TickCount >= MathRetryAt
                    needMathMore := !MathGetConsensus(mathVotes, &qa, &qop, &qb, &qv)
                if needSpawnMore || needMathMore {
                    finalLines := []
                    if SpawnOcrWindow(hwnd, &finalLines, true, false, true, 2) {
                        if watchSpawns
                            SpawnTallyOcrLines(hwnd, finalLines, voteGroups)
                        if cbMath.Value
                            mathPromptSeen := MathCollectQuestionVotes(finalLines, mathVotes) || mathPromptSeen
                    }
                }
            }
            if cbMath.Value
                MathTryAnswer(mathVotes, mathPromptSeen)
        }
        ; Keep failed sends in memory and retry them on later review cycles.
        if watchSpawns
            SpawnFlushPending(hwnd)
        return ocrOk
    } finally {
        chatReviewHoverActive := false
        SetTimer(RefreshChatReviewHover, 0)
        MouseMove(oldMouseX, oldMouseY, 0)
        chatReviewHoverHwnd := 0
    }
}

SpawnTestRead(*) {
    wins := WindowsToWatch()
    if !wins.Length {
        MsgBox("No Roblox window found.", "Spawn Watcher")
        return
    }
    msg := ""
    for i, hwnd in wins {
        lines := []
        ok := SpawnOcrWindow(hwnd, &lines, false, true)
        msg .= "Window " i ":`n"
        if !ok {
            msg .= "  " (lines.Length ? lines[1] : "OCR problem") "`n`n"
            continue
        }
        alreadySeen := []
        hits := SpawnFindSpawns(hwnd, lines, &alreadySeen)
        shown := 0
        for line in lines {
            if shown < 12 && Trim(line) != "" {
                msg .= "  " SubStr(line, 1, 110) "`n"
                shown += 1
            }
        }
        msg .= "  -> " hits.Length " new line(s) would be sent`n"
        for text in hits {
            roleId := ""
            preview := SpawnBuildAlert(LabelFor(), text, &roleId)
            msg .= "     " SubStr(preview, 1, 240) "`n"
        }
        mathVotes := Map()
        mathPrompt := MathCollectQuestionVotes(lines, mathVotes)
        if MathGetConsensus(mathVotes, &ma, &mop, &mb, &mathVoteCount)
            msg .= "  -> Math OCR agrees " mathVoteCount " times: " MathQuestionText(ma, mop, mb) "`n"
        else if mathPrompt
            msg .= "  -> Math prompt seen, but the OCR reads do not agree yet.`n"
        if alreadySeen.Length {
            msg .= "  -> " alreadySeen.Length " matching spawn(s) were already seen or sent:`n"
            for text in alreadySeen
                msg .= "     " SubStr(text, 1, 180) "`n"
        } else if !hits.Length {
            msg .= "  -> No complete new candidate passed the keyword/ignore filters.`n"
        }
        msg .= "`n"
    }
    MsgBox(msg, "Spawn Watcher - test read")
}

; ---------------- chat area calibration ----------------
; ---------------- OCR helper script (PowerShell, Windows built-in OCR) ----------------
EnsureSpawnOcrScript() {
    ps := "
(
param([int]$X, [int]$Y, [int]$W, [int]$H, [string]$Txt, [int]$ShotCount = 4, [string]$SampleDir = '', [switch]$SaveSamples, [switch]$DetectArea)
$ErrorActionPreference = 'Stop'
function Save-Text($t) {
    [System.IO.File]::WriteAllText($Txt, $t, (New-Object System.Text.UTF8Encoding($false)))
}
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type -AssemblyName System.Drawing
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
    $code = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class Cap {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    // mode 0 = plain enlarged copy; mode 1 = brightest-channel threshold;
    // mode 2 = isolate neutral, red, orange, yellow, magenta, blue, and cyan text while
    // rejecting the green scenery visible behind chat.
    public static Bitmap Capture(int x, int y, int w, int h) {
        try { SetProcessDPIAware(); } catch { }
        Bitmap src = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(src)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
        return src;
    }
    public static Bitmap Grab(Bitmap src, int scale, int mode, int thr) {
        Bitmap big = new Bitmap(src.Width * scale, src.Height * scale, PixelFormat.Format32bppArgb);
        using (Graphics g2 = Graphics.FromImage(big)) {
            g2.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g2.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            g2.DrawImage(src, 0, 0, src.Width * scale, src.Height * scale);
        }
        if (mode == 1) {
            BitmapData d = big.LockBits(new Rectangle(0, 0, big.Width, big.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int bytes = Math.Abs(d.Stride) * big.Height;
            byte[] buf = new byte[bytes];
            Marshal.Copy(d.Scan0, buf, 0, bytes);
            for (int i = 0; i < bytes; i += 4) {
                int lum = Math.Max((int)buf[i + 2], Math.Max((int)buf[i + 1], (int)buf[i]));
                byte v = (lum > thr) ? (byte)0 : (byte)255;
                buf[i] = v; buf[i + 1] = v; buf[i + 2] = v; buf[i + 3] = 255;
            }
            Marshal.Copy(buf, 0, d.Scan0, bytes);
            big.UnlockBits(d);
        } else if (mode == 2) {
            BitmapData d = big.LockBits(new Rectangle(0, 0, big.Width, big.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int bytes = Math.Abs(d.Stride) * big.Height;
            byte[] buf = new byte[bytes];
            Marshal.Copy(d.Scan0, buf, 0, bytes);
            for (int i = 0; i < bytes; i += 4) {
                int b = buf[i], g = buf[i + 1], r = buf[i + 2];
                int hi = Math.Max(r, Math.Max(g, b));
                int lo = Math.Min(r, Math.Min(g, b));
                bool neutral = hi > 105 && hi - lo < 28;
                bool red = r > 65 && r > g * 1.35 && r > b * 1.35;
                bool magenta = r > 65 && b > 65 && Math.Min(r, b) > g * 1.25;
                bool blue = b > 85 && b > r * 1.25 && b > g * 1.15;
                bool cyan = g > 75 && b > 75 && Math.Min(g, b) > r * 1.25;
                bool orange = r > 100 && g > 35 && r > g * 1.25 && g > b * 1.15;
                bool yellow = r > 115 && g > 90 && b < Math.Min(r, g) * 0.72;
                byte v = (neutral || red || magenta || blue || cyan || orange || yellow) ? (byte)0 : (byte)255;
                buf[i] = v; buf[i + 1] = v; buf[i + 2] = v; buf[i + 3] = 255;
            }
            Marshal.Copy(buf, 0, d.Scan0, bytes);
            big.UnlockBits(d);
        }
        return big;
    }
}
'@
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $code
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq ('IAsyncOperation' + [char]96 + '1') })[0]
    function Await($op, $type) {
        $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
        $task.Wait(-1) | Out-Null
        $task.Result
    }
    $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $eng) {
        Save-Text 'ERROR: Windows OCR engine not available'
        exit
    }
    $passes = @(@(3,0,0), @(3,1,120), @(3,2,0))
    $passNames = @('enlarged color', 'threshold', 'isolated text colors')
    $outLines = @()
    $sampleReport = New-Object 'System.Collections.Generic.List[string]'
    $sampleStamp = [DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')
    $framesToCapture = [Math]::Max(1, [Math]::Min(6, $ShotCount))
    for ($shot = 0; $shot -lt $framesToCapture; $shot++) {
        if ($shot -gt 0) { Start-Sleep -Milliseconds 160 }
        $frame = [Cap]::Capture($X, $Y, $W, $H)
        if ($SaveSamples) {
            try {
                if (!(Test-Path -LiteralPath $SampleDir)) { New-Item -ItemType Directory -Path $SampleDir -Force | Out-Null }
                $frameFile = Join-Path $SampleDir ($sampleStamp + '_frame' + ('{0:D2}' -f ($shot + 1)) + '.png')
                $frame.Save($frameFile, [System.Drawing.Imaging.ImageFormat]::Png)
                [void]$sampleReport.Add(('FRAME ' + ($shot + 1) + ' IMAGE ' + [System.IO.Path]::GetFileName($frameFile)))
            } catch {
                [void]$sampleReport.Add(('FRAME ' + ($shot + 1) + ' IMAGE SAVE ERROR: ' + $_.Exception.Message))
            }
        }
        $passIndex = 0
        foreach ($p in $passes) {
            $passIndex++
            $outLines += 'B|'
            $bmp = [Cap]::Grab($frame, $p[0], $p[1], $p[2])
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            $ms.Position = 0
            $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
            $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
            $sb = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
            $res = Await ($eng.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
            if ($SaveSamples) {
                [void]$sampleReport.Add(('  TREATMENT ' + $passNames[$passIndex - 1]))
            }
            foreach ($line in $res.Lines) {
                if ($DetectArea) {
                    $rect = $line.BoundingRect
                    $outLines += ('P|' + ($shot + 1) + '|' + $line.Text + '|' + [int][Math]::Round($rect.X / $p[0]) + '|' + [int][Math]::Round($rect.Y / $p[0]) + '|' + [int][Math]::Round($rect.Width / $p[0]) + '|' + [int][Math]::Round($rect.Height / $p[0]))
                } else {
                    $outLines += ('L|' + $line.Text)
                }
                if ($SaveSamples) {
                    [void]$sampleReport.Add(('    ' + $line.Text))
                }
            }
        }
        $frame.Dispose()
    }
    if ($SaveSamples) {
        try {
            $sampleText = Join-Path $SampleDir ($sampleStamp + '_ocr.txt')
            [System.IO.File]::WriteAllText($sampleText, ($sampleReport.ToArray() -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
            $oldChecks = @(Get-ChildItem -LiteralPath $SampleDir -Filter '*_ocr.txt' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 200)
            foreach ($old in $oldChecks) {
                $oldStamp = $old.BaseName -replace '_ocr$', ''
                try { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue } catch { }
                try {
                    Get-ChildItem -LiteralPath $SampleDir -Filter ($oldStamp + '_frame*.png') -File | Remove-Item -Force -ErrorAction SilentlyContinue
                } catch { }
            }
        } catch { }
    }
    Save-Text ($outLines -join [Environment]::NewLine)
} catch {
    Save-Text ('ERROR: ' + $_.Exception.Message)
}
)"
    try FileDelete(spawnPsFile)
    FileAppend(ps, spawnPsFile, "UTF-8")
}


SpawnStart() {
    global spawnRunning
    if spawnRunning
        return
    spawnRunning := true
    SpawnSetStatus("● WATCHING", "5CFF8A")
    spawnStatusTxt.Text := "Watcher: running with F6"
    SpawnPrime()
}

SpawnStop() {
    global spawnRunning
    if !spawnRunning
        return
    spawnRunning := false
    SpawnSetStatus("● STOPPED", "FF5C5C")
    spawnStatusTxt.Text := "Watcher: off (F6 stopped both)"
}
; ---------------- Logic ----------------
SetStatus(text, color) {
    statusTxt.Text := text
    statusTxt.SetFont("c" color)
}

Tip(ctrl, text) {
    Tips[ctrl.Hwnd] := text
}

ShowTip(wParam, lParam, msg, hwnd) {
    static last := 0
    MouseGetPos(, , , &h, 2)
    if h = last
        return
    last := h
    if Tips.Has(h) {
        ToolTip(Tips[h])
        SetTimer(ClearTip, -6000)
    } else {
        ToolTip()
    }
}

ClearTip() {
    ToolTip()
}

UpdateClock() {
    secs := running ? (A_TickCount - startTick) // 1000 : 0
    cycleTxt.Text := "Upgrades: " cycles " | " Format("{:02}:{:02}:{:02}", secs // 3600, Mod(secs // 60, 60), Mod(secs, 60))
}

SaveAll() {
    global cbMath, edPingRng
    IniWrite(edSlot.Value, IniFile, "main", "slot")
    IniWrite(cbAtk.Value, IniFile, "main", "atkOn")
    IniWrite(cbEquip.Value, IniFile, "main", "equipOn")
    IniWrite(cbMath.Value, IniFile, "main", "mathOn")
    IniWrite(cbArena.Value, IniFile, "main", "arenaOn")
    IniWrite(edFps.Value, IniFile, "main", "fps")
    IniWrite(edHook.Value, IniFile, "spawn", "webhook")
    IniWrite(edLabel.Value, IniFile, "spawn", "label")
    IniWrite(edKeys.Value, IniFile, "spawn", "keywords")
    IniWrite(edIgnore.Value, IniFile, "spawn", "ignore")
    IniWrite(cbSkipElites.Value, IniFile, "spawn", "championsOnly")
    IniWrite(edPingRng.Value, IniFile, "spawn", "pingRngMin")
    IniWrite(edServerLink.Value, IniFile, "spawn", "serverLink")
    IniWrite(edRole.Value, IniFile, "spawn", "championRoleId")
    IniWrite(cbSpawn.Value, IniFile, "spawn", "enabled")
    IniWrite(cbSamples.Value, IniFile, "spawn", "saveSamples")
    for r in Rows
        IniWrite(r["up"].Value, IniFile, "rows", r["name"])
}

ShowHelp(*) {
    MsgBox("QUICK START`n`n"
        . "1. Open Roblox, or paste your private server link and click 'Join now'.`n"
        . "2. Select the upgrades you want; each gets 10 attempts every 8 minutes.`n"
        . "3. Enable Chat Math to answer reward questions after multiple OCR reads agree.`n"
        . "4. Enable the Spawn Watcher to keep checking chat while the macro runs.`n"
        . "5. Optional: save recent chat image/OCR checks in the OCR Samples folder.`n"
        . "6. With chat reading enabled, F6 checks five captures to find chat and locks that area for the run.`n"
        . "7. Press Start (or F6); attacks run when chat scans and upgrades are idle. Press F6 again to stop.`n"
        . "8. Set the public GitHub source once with Check updates; new releases install automatically when the macro is stopped.",
        "Item Factory Helper - Help")
}

; ---------------- Arena Queue Auto-Join ----------------
CheckArenaQueue() {
    global arenaClicked, arenaClickTick, arenaGone, arenaTries, spawnCapturing
    if !running || !cbArena.Value || spawnCapturing || joinPending || !WinExist(RobloxWin)
        return
    WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
    if cw <= 0 || ch <= 0
        return

    x1 := Round(cx + cw * QueueL)
    y1 := Round(cy + ch * QueueT)
    x2 := Round(cx + cw * QueueR)
    y2 := Round(cy + ch * QueueB)

    ; green Queue button (turns into a red Cancel button once you are queued)
    green := false
    try green := PixelSearch(&gx, &gy, x1, y1, x2, y2, QueueColor, QueueTol)

    ; the prompt is on screen while its red Close button is
    red := false
    try red := PixelSearch(&rx, &ry, x1, y1, Round(cx + cw * 0.18), y2, QueueCloseColor, QueueCloseTol)

    if !green && !red {
        ; prompt is gone: after ~3 seconds of that, allow ONE click on the next prompt
        arenaGone += 1
        if arenaGone >= 3 {
            arenaClicked := false
            arenaTries := 0
        }
        return
    }
    arenaGone := 0

    if arenaClicked {
        ; Already clicked for this prompt. Never click again (a second click would CANCEL),
        ; except one retry if the button is still green 3 seconds later (the click missed).
        if green && red && arenaTries < 2 && A_TickCount - arenaClickTick > 3000 {
            arenaTries += 1
            arenaClickTick := A_TickCount
            ClickAt(gx - cx + Round(cw * 0.025), gy - cy + Round(ch * 0.008))
        } else if A_TickCount - arenaClickTick > 300000 {
            arenaClicked := false             ; safety: re-arm after 5 minutes
            arenaTries := 0
        }
        return
    }

    if !green || !red
        return

    ; the red Close button must sit to the right of the green button
    rx1 := gx + Max(8, Round(cw * 0.02))
    rx2 := Round(cx + cw * 0.18)
    ry1 := gy - Round(ch * 0.02)
    ry2 := gy + Round(ch * 0.03)
    if rx2 <= rx1
        return
    near := false
    try near := PixelSearch(&nx, &ny, rx1, ry1, rx2, ry2, QueueCloseColor, QueueCloseTol)
    if !near
        return

    ClickAt(gx - cx + Round(cw * 0.025), gy - cy + Round(ch * 0.008))
    arenaClicked := true
    arenaTries := 1
    arenaClickTick := A_TickCount
}

SetChatArea(*) {
    global calibStep
    calibStep := 1
    MsgBox("1) Click OK and switch to Roblox.`n"
        . "2) Hover TOP-LEFT of chat messages and press F8.`n"
        . "3) Hover BOTTOM-RIGHT of chat messages and press F8.", "Item Factory Helper")
}

CalibKey() {
    global calibStep, calibX, calibY, ChatL, ChatT, ChatR, ChatB
    global ManualChatL, ManualChatT, ManualChatR, ManualChatB
    if calibStep = 0
        return
    if !WinExist(RobloxWin) {
        calibStep := 0
        return
    }
    WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
    CoordMode "Mouse", "Screen"
    MouseGetPos(&mx, &my)
    CoordMode "Mouse", "Client"
    rx := (mx - cx) / cw
    ry := (my - cy) / ch
    if calibStep = 1 {
        calibX := rx
        calibY := ry
        calibStep := 2
        ToolTip("Top-left saved. Hover BOTTOM-RIGHT and press F8.")
        SetTimer(ClearTip, -4000)
        return
    }
    ChatL := Round(Min(calibX, rx), 4)
    ChatR := Round(Max(calibX, rx), 4)
    ChatT := Round(Min(calibY, ry), 4)
    ChatB := Round(Max(calibY, ry), 4)
    ManualChatL := ChatL, ManualChatT := ChatT, ManualChatR := ChatR, ManualChatB := ChatB
    IniWrite(ChatL, IniFile, "chat", "L")
    IniWrite(ChatT, IniFile, "chat", "T")
    IniWrite(ChatR, IniFile, "chat", "R")
    IniWrite(ChatB, IniFile, "chat", "B")
    calibStep := 0
    ToolTip("Chat area saved.")
    SetTimer(ClearTip, -3000)
}

FocusRoblox() {
    if !WinExist(RobloxWin)
        return
    try {
        if WinGetMinMax(RobloxWin) = -1
            WinRestore(RobloxWin)
        if !WinActive(RobloxWin) {
            WinActivate(RobloxWin)
            WinWaitActive(RobloxWin, , 2)
        }
    }
}

FindNewestLog() {
    newest := "", newestTime := 0
    Loop Files LogDir "\*.log" {
        if InStr(A_LoopFileName, "Player") && A_LoopFileTimeModified > newestTime {
            newest := A_LoopFileFullPath
            newestTime := A_LoopFileTimeModified
        }
    }
    return newest
}

ResetLogBaseline() {
    global logPath, logPos
    logPath := FindNewestLog()
    logPos := 0
    if logPath = ""
        return
    try {
        f := FileOpen(logPath, "r")
        logPos := f.Length
        f.Close()
    }
}

CheckDisconnect() {
    global logPath, logPos
    newest := FindNewestLog()
    if newest = ""
        return false
    if newest != logPath {
        logPath := newest
        logPos := 0
    }
    if StaleLogSeconds > 0 {
        try {
            if DateDiff(A_Now, FileGetTime(logPath, "M"), "Seconds") > StaleLogSeconds
                return true
        }
    }
    txt := ""
    try {
        f := FileOpen(logPath, "r", "UTF-8")
        if f.Length < logPos
            logPos := 0
        f.Seek(logPos)
        txt := f.Read()
        logPos := f.Pos
        f.Close()
    } catch {
        return false
    }
    return RegExMatch(txt, "i)" DisconnectRegex) > 0
}

WatchDisconnect() {
    global dlgStrikes, spawnCapturing
    if !running || joinPending || !cbAuto.Value
        return
    if spawnCapturing
        return
    if WinExist("Roblox Crash") {
        try WinClose("Roblox Crash")
        HandleDisconnect()
        return
    }
    if !WinExist(RobloxWin)
        return
    dlgStrikes := DisconnectDialogVisible() ? dlgStrikes + 1 : 0
    if dlgStrikes >= 2 {
        dlgStrikes := 0
        HandleDisconnect()
        return
    }
    if CheckDisconnect()
        HandleDisconnect()
}

DisconnectDialogVisible() {
    WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
    if cw <= 0
        return false
    mx := cx + cw // 2, my := cy + ch // 2
    hits := 0
    Loop 5 {
        i := A_Index
        Loop 4 {
            x := mx - 90 + (i - 1) * 45
            y := my - 36 + (A_Index - 1) * 24
            try c := PixelGetColor(x, y)
            catch
                continue
            r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
            if Abs(r - ((DialogColor >> 16) & 0xFF)) <= DialogTol
                && Abs(g - ((DialogColor >> 8) & 0xFF)) <= DialogTol
                && Abs(b - (DialogColor & 0xFF)) <= DialogTol
                hits += 1
        }
    }
    return hits >= 12
}

HandleDisconnect() {
    global abort, lastLaunch
    abort := true
    SetStatus("● DISCONNECTED - REJOINING", "FF8A3D")
    try WinClose("Roblox Crash")
    try WinClose(RobloxWin)
    if !WinWaitClose(RobloxWin, , 6) {
        try WinKill(RobloxWin)
        WinWaitClose(RobloxWin, , 6)
    }
    lastLaunch := 0
}

ToInt(ctrl, default, minimum := 1) {
    v := ctrl.Value
    return IsInteger(v) ? Max(Integer(v), minimum) : default
}

Toggle(*) {
    global running, cycles, lastLaunch, joinPending, startTick, abort, arenaClicked, arenaTries, arenaGone, MathRetryAt
    global cbSpawn, cbMath, chatAreaDetectionDone, ChatL, ChatT, ChatR, ChatB
    global ManualChatL, ManualChatT, ManualChatR, ManualChatB, GitHubRepo
    if !running && cbSpawn.Value {
        if !SpawnHookUrlOk(Trim(edHook.Value)) {
            MsgBox("Enter a valid webhook in the Spawn Watcher tab, or disable the watcher checkbox.", "Item Factory Helper")
            return
        }
        roleId := Trim(edRole.Value)
        if roleId != "" && !RegExMatch(roleId, "^\d{17,20}$") {
            MsgBox("Champion role ID must be digits only, or left blank.", "Item Factory Helper")
            return
        }
        if !SpawnParsePingRng(&pingMinimum) {
            MsgBox("Enter a number for the minimum RNG to send (0 means no minimum).", "Item Factory Helper")
            return
        }
    }
    if !running {
        chatAreaDetectionDone := false
        ChatL := ManualChatL, ChatT := ManualChatT, ChatR := ManualChatR, ChatB := ManualChatB
    }
    running := !running
    if running {
        toggleBtn.Text := "Stop   (F6)"
        SetStatus("● RUNNING", "5CFF8A")
        cycles := 0
        startTick := A_TickCount
        lastLaunch := 0
        joinPending := false
        abort := false
        arenaClicked := false
        arenaTries := 0
        arenaGone := 0
        MathRetryAt := 0
        SaveAll()
        ResetLogBaseline()
        g.Minimize()
        if WinExist(RobloxWin) {
            FocusRoblox()
            Sleep(250)
            if cbEquip.Value && edSlot.Value != ""
                PressKey(edSlot.Value)
        }
        EnsureChatOpen()
        if (cbSpawn.Value || cbMath.Value) && WinExist(RobloxWin)
            EnsureChatAreaForRun(WinExist(RobloxWin))
        ToolTip("Item Factory Helper is running - press F6 to stop", A_ScreenWidth - 320, A_ScreenHeight - 50)
        SetTimer(ClearTip, -5000)
        SetTimer(UpdateClock, 1000)
        if cbSpawn.Value
            SpawnStart()
        SetTimer(Cycle, -10)
    } else {
        EnsureChatOpen()
        SpawnStop()
        SetTimer(Cycle, 0)
        SetTimer(UpdateClock, 0)
        chatAreaDetectionDone := false
        ChatL := ManualChatL, ChatT := ManualChatT, ChatR := ManualChatR, ChatB := ManualChatB
        toggleBtn.Text := "Start   (F6)"
        SetStatus("● STOPPED", "FF5C5C")
        g.Restore()
        if Trim(GitHubRepo) != ""
            SetTimer(AutoCheckForUpdates, -1000)
    }
}

EnsureChatOpen() {
    global RobloxWin, ChatToggleX, ChatToggleY
    if !WinExist(RobloxWin)
        return false
    hwnd := WinExist(RobloxWin)
    state := ChatOpenState(hwnd)
    if state = 1
        return true
    if state = 0 {
        FocusRoblox()
        ClickAt(ChatToggleX, ChatToggleY)
        Sleep(700)
        return ChatOpenState(hwnd) = 1
    }
    return false
}

; Filled bubble = chat open; outlined bubble = chat closed.
; Sample the upper interior of the icon, away from its horizontal lines.
ChatOpenState(hwnd) {
    global ChatToggleX, ChatToggleY
    id := "ahk_id " hwnd
    if !WinExist(id)
        return -1
    WinGetClientPos(&cx, &cy, &cw, &ch, id)
    bright := 0, dark := 0
    for dx in [-3, 0, 3] {
        try c := PixelGetColor(cx + ChatToggleX + dx, cy + ChatToggleY - 7, "RGB")
        catch
            continue
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        if r > 180 && g > 180 && b > 180
            bright += 1
        else if r < 90 && g < 90 && b < 90
            dark += 1
    }
    if bright >= 2
        return 1
    if dark >= 2
        return 0
    return -1
}

JoinUrl(link) {
    if RegExMatch(link, "i)roblox\.com/games/(\d+)[^?#]*\?[^#]*privateServerLinkCode=([\w\-]+)", &m)
        return "roblox://placeID=" m[1] "&linkcode=" m[2]
    if RegExMatch(link, "i)roblox\.com/share\?[^#]*code=(\w+)", &m) && InStr(link, "type=Server")
        return "roblox://navigation/share_links?code=" m[1] "&type=Server"
    return link
}

LaunchServer() {
    global lastLaunch, joinPending
    link := Trim(edLink.Value)
    if link = "" {
        MsgBox("Paste your private server link into the box first.", "Item Factory Helper")
        return false
    }
    IniWrite(link, IniFile, "main", "link")
    try Run(JoinUrl(link))
    catch {
        MsgBox("Couldn't open that link.", "Item Factory Helper")
        return false
    }
    lastLaunch := A_TickCount
    joinPending := true
    return true
}

PressKey(k) {
    Send("{" k " down}")
    Sleep(40)
    Send("{" k " up}")
}

ClickAt(x, y) {
    if !WinExist(RobloxWin)
        return
    if !WinActive(RobloxWin) {
        FocusRoblox()
        Sleep(150)
    }
    MouseMove(Round(x), Round(y), 0)
    Sleep(25)
    Click()
}

Cycle() {
    global running, cycles, joinPending, abort, macroCycleBusy, spawnCapturing, lastLaunch
    global cbAuto, edLink, cbEquip, edSlot, cbAtk, cbArena, cbSpawn, cbMath, spawnRunning
    global Rows, RobloxWin, AttackX, AttackY, LeftX, CloseX, CloseY
    global chatReviewHoverActive
    if !running
        return
    if macroCycleBusy || spawnCapturing {
        SetTimer(Cycle, -250)
        return
    }
    macroCycleBusy := true
    try {
        nextUpgradeTick := A_TickCount + 8 * 60 * 1000
        nextSpawnCheck := 0
        nextAttack := A_TickCount
        nextMaintenance := A_TickCount
        nextDisconnectCheck := A_TickCount
        nextUpgradeAction := 0
        upgradeRows := []
        upgradeIndex := 1
        upgradeAttempt := 0
        upgradeActive := false
        needInitialize := true

        while running {
            if !WinExist(RobloxWin) {
                needInitialize := true
                if cbAuto.Value && Trim(edLink.Value) != "" && (lastLaunch = 0 || A_TickCount - lastLaunch > 120000) {
                    SetStatus("● JOINING SERVER…", "FFB020")
                    LaunchServer()
                } else if lastLaunch != 0 && A_TickCount - lastLaunch <= 120000 {
                    SetStatus("● JOINING SERVER…", "FFB020")
                } else {
                    SetStatus("● Roblox not found", "FFB020")
                }
                Sleep(1500)
                continue
            }

            if abort {
                Sleep(1000)
                abort := false
                continue
            }

            if joinPending {
                SetStatus("● LOADING GAME…", "FFB020")
                loadEnd := A_TickCount + 15000
                while running && WinExist(RobloxWin) && A_TickCount < loadEnd {
                    FocusRoblox()
                    Sleep(500)
                }
                joinPending := false
                ResetLogBaseline()
                if cbEquip.Value && edSlot.Value != "" && running && WinExist(RobloxWin) {
                    FocusRoblox()
                    Sleep(250)
                    PressKey(edSlot.Value)
                }
                if !running
                    break
                EnsureChatOpen()
                if (cbSpawn.Value || cbMath.Value) && WinExist(RobloxWin) {
                    initHwnd := WinExist(RobloxWin)
                    EnsureChatAreaForRun(initHwnd)
                    if cbSpawn.Value && spawnRunning
                        SpawnPrime()
                }
                needInitialize := false
                continue
            }

            if needInitialize {
                FocusRoblox()
                EnsureChatOpen()
                if (cbSpawn.Value || cbMath.Value) && WinExist(RobloxWin) {
                    initHwnd := WinExist(RobloxWin)
                    EnsureChatAreaForRun(initHwnd)
                    if cbSpawn.Value && spawnRunning
                        SpawnPrime()
                }
                needInitialize := false
            }

            now := A_TickCount
            if now >= nextDisconnectCheck {
                WatchDisconnect()
                nextDisconnectCheck := A_TickCount + 1500
            }
            if abort
                continue

            if now >= nextMaintenance {
                CheckArenaQueue()
                nextMaintenance := A_TickCount + 500
            }

            ; Run OCR throughout the session. Actions pause during a scan so
            ; clicks cannot pull the hover background away from chat.
            if ((cbSpawn.Value && spawnRunning) || cbMath.Value) && now >= nextSpawnCheck {
                hwnd := WinExist(RobloxWin)
                if hwnd {
                    SetStatus("● CHECKING CHAT", "6CB6FF")
                    FocusRoblox()
                    SpawnReviewCheck(hwnd)
                    nextSpawnCheck := A_TickCount + 2000
                    if running && !abort
                        SetStatus(upgradeActive ? "● UPGRADING" : "● RUNNING", upgradeActive ? "6CB6FF" : "5CFF8A")
                } else {
                    nextSpawnCheck := A_TickCount + 1000
                }
                continue
            }

            if !upgradeActive && now >= nextUpgradeTick {
                upgradeRows := []
                for r in Rows {
                    if r["up"].Value
                        upgradeRows.Push(r)
                }
                if upgradeRows.Length {
                    upgradeActive := true
                    upgradeIndex := 1
                    upgradeAttempt := 0
                    nextUpgradeAction := now
                } else {
                    nextUpgradeTick := now + 8 * 60 * 1000
                }
            }

            if upgradeActive {
                while upgradeIndex <= upgradeRows.Length && !upgradeRows[upgradeIndex]["up"].Value {
                    upgradeIndex += 1
                    upgradeAttempt := 0
                }
                if upgradeIndex > upgradeRows.Length {
                    upgradeActive := false
                    nextUpgradeTick := A_TickCount + 8 * 60 * 1000
                    cycles += 1
                    UpdateClock()
                    SetStatus("● RUNNING", "5CFF8A")
                    continue
                }
                if A_TickCount >= nextUpgradeAction {
                    r := upgradeRows[upgradeIndex]
                    SetStatus("● " StrUpper(r["name"]) " " (upgradeAttempt + 1) "/10", "6CB6FF")
                    FocusRoblox()
                    if !WinExist(RobloxWin) {
                        Sleep(250)
                        continue
                    }
                    WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
                    ClickAt(cw * LeftX, ch * r["y"])
                    Sleep(500)
                    if !running
                        break
                    ClickAt(cw * CloseX, ch * CloseY)
                    Sleep(500)
                    if !running
                        break
                    upgradeAttempt += 1
                    if upgradeAttempt >= 10 {
                        upgradeAttempt := 0
                        upgradeIndex += 1
                    }
                    nextUpgradeAction := A_TickCount + 500
                    continue
                }
            }

            if cbAtk.Value && A_TickCount >= nextAttack && WinExist(RobloxWin) {
                WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
                ClickAt(cw * AttackX, ch * AttackY)
                nextAttack := A_TickCount + 500
                continue
            }
            Sleep(50)
        }
    } finally {
        chatReviewHoverActive := false
        SetTimer(RefreshChatReviewHover, 0)
        macroCycleBusy := false
    }
}

TestPositions(*) {
    global running
    if running
        Toggle()
    if !WinExist(RobloxWin) {
        MsgBox("Couldn't find the Roblox window.", "Item Factory Helper")
        return
    }
    WinActivate(RobloxWin)
    Sleep(300)
    WinGetClientPos(&cx, &cy, &cw, &ch, RobloxWin)
    spots := [["Attack point", AttackX, AttackY]]
    for r in Rows
        spots.Push([r["name"], LeftX, r["y"]])
    spots.Push(["Close popup", CloseX, CloseY])
    spots.Push(["Arena Queue", QueueBtnX, QueueBtnY])
    for s in spots {
        MouseMove(Round(cw * s[2]), Round(ch * s[3]), 0)
        ToolTip(s[1])
        Sleep(700)
    }
    ToolTip()
}

SettingsFile() {
    return EnvGet("LOCALAPPDATA") "\Roblox\GlobalBasicSettings_13.xml"
}

SetFramerateCap(fps, lock := false) {
    f := SettingsFile()
    if !FileExist(f) {
        MsgBox("Couldn't find:`n" f, "Item Factory Helper")
        return false
    }
    if WinExist(RobloxWin) {
        MsgBox("Close Roblox first.", "Item Factory Helper")
        return false
    }
    try FileSetAttrib("-R", f)
    if !FileExist(f ".bak")
        FileCopy(f, f ".bak")
    txt := FileRead(f, "UTF-8")
    if RegExMatch(txt, '<int name="FramerateCap">-?\d+</int>')
        txt := RegExReplace(txt, '(<int name="FramerateCap">)-?\d+(</int>)', "${1}" fps "${2}")
    else
        txt := RegExReplace(txt, "(</Properties>)", '  <int name="FramerateCap">' fps "</int>`n    $1", , 1)
    FileDelete(f)
    FileAppend(txt, f, "UTF-8-RAW")

    check := FileRead(f, "UTF-8")
    if !RegExMatch(check, '<int name="FramerateCap">(-?\d+)</int>', &m) || m[1] != fps {
        MsgBox("Error updating FramerateCap.", "Item Factory Helper")
        return false
    }
    if lock
        FileSetAttrib("+R", f)
    return true
}

ApplyFps(*) {
    fps := ToInt(edFps, 30, 1)
    IniWrite(fps, IniFile, "main", "fps")
    if SetFramerateCap(fps, cbLock.Value)
        MsgBox("FramerateCap set to " fps ".", "Item Factory Helper")
}

ClearFps(*) {
    if SetFramerateCap(60, false)
        MsgBox("FPS cap reset to 60.", "Item Factory Helper")
}

SetOcrSettings(*) {
    f := SettingsFile()
    if !FileExist(f) {
        MsgBox("Roblox settings file wasn't found.`n`nLaunch Roblox once, close it, then try again.", "Item Factory Helper")
        return
    }
    if WinExist(RobloxWin) {
        MsgBox("Close Roblox before applying these settings. They take effect the next time Roblox starts.", "Item Factory Helper")
        return
    }

    wasLocked := InStr(FileGetAttrib(f), "R") != 0
    try FileSetAttrib("-R", f)
    try {
        if !FileExist(f ".bak")
            FileCopy(f, f ".bak")
        doc := ComObject("Msxml2.DOMDocument.6.0")
        doc.async := false
        doc.preserveWhiteSpace := true
        if !doc.loadXML(FileRead(f, "UTF-8"))
            throw Error("Roblox settings XML could not be read: " doc.parseError.reason)
        props := doc.selectSingleNode("//Item[@class='UserGameSettings']/Properties")
        if !props
            throw Error("The UserGameSettings section was not found in the Roblox settings file.")

        SetXmlSetting(doc, props, "token", "SavedQualityLevel", "1")
        SetXmlSetting(doc, props, "float", "PreferredTransparency", "0")
        SetXmlSetting(doc, props, "token", "PreferredTextSize", "4")

        temp := f ".ifh-tmp"
        try FileDelete(temp)
        FileAppend(doc.xml, temp, "UTF-8-RAW")
        if !FileExist(temp)
            throw Error("Temporary Roblox settings file was not written.")
        FileMove(temp, f, 1)
        if cbLock.Value || wasLocked
            FileSetAttrib("+R", f)
        MsgBox("Applied: graphics quality 1, fully opaque background preference, and largest text size.`n`nThe settings apply when Roblox next starts.", "Item Factory Helper")
    } catch as e {
        if cbLock.Value || wasLocked
            try FileSetAttrib("+R", f)
        MsgBox("Couldn't update Roblox settings:`n" e.Message, "Item Factory Helper")
    }
}

SetXmlSetting(doc, props, tag, name, value) {
    node := props.selectSingleNode(tag "[@name='" name "']")
    if !node {
        node := doc.createElement(tag)
        node.setAttribute("name", name)
        props.appendChild(node)
    }
    node.text := value
}

; ====================================================================
