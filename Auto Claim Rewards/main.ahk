#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"
SendMode "Event"

; ---------------- TIMING ----------------
global GATE_MS := 100
global ACTION_SLEEP_MS := 150
global TIMER_MS := 100
global STEP8_SETTLE_MS := 500

; ---------------- TOLERANCE ----------------
global TOL := 10            ; everything except Step 2

; ---------------- STEP 2 TARGET ----------------
global STEP2_X := 1122
global STEP2_Y := 259
global STEP2_COLOR := 0x9C9C9C
global STEP2_TOL := 15
global STEP2_TIMEOUT_MS := 5000     ; 0 = wait forever
; old target was: 863, 229, 0xEFEFEF

; ---------------- GATE ----------------
global GATE_X := 116
global GATE_Y := 724
global GATE_COLOR := 0x210000

; ---------------- STATE ----------------
global rewardsTimerRunning := false
global sequenceRunning := false

; ---------------- STEP 3 RGB TABLE ----------------
global RGB_CHECKS := [
    { label: "RGB1", cx: 1134, cy: 396, col: 0xE50101, kx: 1090, ky: 485 },
    { label: "RGB2", cx: 1288, cy: 402, col: 0xCF0101, kx: 1239, ky: 485 },
    { label: "RGB3", cx: 1431, cy: 393, col: 0xEA0101, kx: 1393, ky: 485 },
    { label: "RGB4", cx: 1137, cy: 545, col: 0xEB0101, kx: 1090, ky: 630 },
    { label: "RGB5", cx: 1285, cy: 547, col: 0xE50101, kx: 1239, ky: 630 },
    { label: "RGB6", cx: 1433, cy: 546, col: 0xE40101, kx: 1393, ky: 630 },
    { label: "RGB7", cx: 1138, cy: 695, col: 0xEA0101, kx: 1090, ky: 780 },
    { label: "RGB8", cx: 1288, cy: 694, col: 0xDE0101, kx: 1239, ky: 780 },
    { label: "RGB9", cx: 1436, cy: 697, col: 0xE40101, kx: 1393, ky: 780 }
]

; ============================================================
;  GUI
; ============================================================
global MainGui := Gui("+AlwaysOnTop", "Rewards")
MainGui.SetFont("s10", "Segoe UI")

global ChkEnable := MainGui.AddCheckbox("xm w220 vEnableGate", "Enable")
ChkEnable.OnEvent("Click", OnToggle)

global TxtStatus := MainGui.AddText("xm w220 h20", "Status: idle")
global TxtGate   := MainGui.AddText("xm w220 h20", "Gate pixel: --")

MainGui.OnEvent("Close", GuiClose)
MainGui.OnEvent("Escape", GuiClose)
MainGui.Show()


; ============================================================
;  GUI EVENTS / HELPERS
; ============================================================
GuiClose(*)
{
    ExitApp()
}

OnToggle(ctrl, *)
{
    global rewardsTimerRunning, sequenceRunning, TIMER_MS
    if (ctrl.Value)
    {
        SetTimer(RewardsTimer, TIMER_MS)
        rewardsTimerRunning := true
        SetStatus(sequenceRunning ? "running" : "watching gate")
    }
    else
    {
        SetTimer(RewardsTimer, 0)
        rewardsTimerRunning := false
        SetStatus("idle")
        SetGateText("--")
    }
}

IsEnabled()
{
    global ChkEnable
    return ChkEnable.Value = 1
}

Aborted(where)
{
    if (IsEnabled())
        return false
    return true
}

SetStatus(txt)
{
    global TxtStatus
    try
        TxtStatus.Text := "Status: " txt
}

SetGateText(txt)
{
    global TxtGate
    try
        if (TxtGate.Text != "Gate pixel: " txt)
            TxtGate.Text := "Gate pixel: " txt
}


; ============================================================
;  GATE TIMER
; ============================================================
RewardsTimer()
{
    global rewardsTimerRunning, sequenceRunning, TIMER_MS, TOL
    global GATE_X, GATE_Y, GATE_COLOR

    if (!IsEnabled())
    {
        SetTimer(RewardsTimer, 0)
        rewardsTimerRunning := false
        return
    }
    if (sequenceRunning)
        return

    color := PixelGetColor(GATE_X, GATE_Y, "RGB")
    SetGateText(Format("0x{:06X}", color))
    if (!ColorMatches(color, GATE_COLOR, TOL))
        return

    SetTimer(RewardsTimer, 0)
    rewardsTimerRunning := false

    sequenceRunning := true
    try
        RunSequence()
    finally
    {
        sequenceRunning := false
        if (IsEnabled())
        {
            SetTimer(RewardsTimer, TIMER_MS)
            rewardsTimerRunning := true
            SetStatus("watching gate")
        }
        else
        {
            SetStatus("idle")
        }
    }
}


; ============================================================
;  SEQUENCE — STEPS 1-8
; ============================================================
RunSequence()
{
    global GATE_MS, ACTION_SLEEP_MS, STEP8_SETTLE_MS, TOL, RGB_CHECKS
    global STEP2_X, STEP2_Y, STEP2_COLOR, STEP2_TOL, STEP2_TIMEOUT_MS

    SetStatus("running")
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 1 ----------
    ReopenRewards()
    if (Aborted("Step 1"))
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 2 ----------
    step2Start := A_TickCount
    step2Found := false
    Loop
    {
        if (Aborted("Step 2"))
            return
        color := PixelGetColor(STEP2_X, STEP2_Y, "RGB")
        if (ColorMatches(color, STEP2_COLOR, STEP2_TOL))
        {
            step2Found := true
            break
        }
        if (STEP2_TIMEOUT_MS > 0 && A_TickCount - step2Start >= STEP2_TIMEOUT_MS)
            break
        Sleep(GATE_MS)
    }
    if (!step2Found)
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 3 ----------
    globalMonitorActive := false
    for idx, chk in RGB_CHECKS
    {
        if (Aborted("Step 3"))
            return
        clicked := ClickUntilGoneWithMonitor(chk.cx, chk.cy, chk.col, chk.kx, chk.ky, &globalMonitorActive, chk.label)
        if (idx = 9 && clicked)
        {
            Rejoin()
            return
        }
    }
    if (globalMonitorActive && GlobalCheckerFails())
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 4 ----------
    Loop
    {
        if (Aborted("Step 4"))
            return
        if (globalMonitorActive && GlobalCheckerFails())
            return
        if (RewardsMonitorFails())
            return
        color := PixelGetColor(1122, 467, "RGB")
        if (ColorMatches(color, 0x363636, TOL))
            break
        Click(615, 281)
        Sleep(ACTION_SLEEP_MS)
    }
    if (globalMonitorActive && GlobalCheckerFails())
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 5 ----------
    Loop
    {
        if (Aborted("Step 5"))
            return
        if (globalMonitorActive && GlobalCheckerFails())
            return
        if (RewardsMonitorFails())
            return
        color := PixelGetColor(1447, 441, "RGB")
        if (!ColorMatches(color, 0x3FCB5B, TOL))
            break
        Click(1273, 440)
        Sleep(ACTION_SLEEP_MS)
    }
    if (globalMonitorActive && GlobalCheckerFails())
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 6 ----------
    Loop
    {
        if (Aborted("Step 6"))
            return
        if (globalMonitorActive && GlobalCheckerFails())
            return
        if (RewardsMonitorFails())
            return
        color := PixelGetColor(1451, 626, "RGB")
        if (!ColorMatches(color, 0x3FCC5C, TOL))
            break
        Click(1273, 624)
        Sleep(ACTION_SLEEP_MS)
    }
    if (globalMonitorActive && GlobalCheckerFails())
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 7 ----------
    Loop
    {
        if (Aborted("Step 7"))
            return
        if (globalMonitorActive && GlobalCheckerFails())
            return
        if (RewardsMonitorFails())
            return
        color := PixelGetColor(1455, 812, "RGB")
        if (!ColorMatches(color, 0x3FCB5C, TOL))
            break
        Click(1273, 808)
        Sleep(ACTION_SLEEP_MS)
    }
    if (globalMonitorActive && GlobalCheckerFails())
        return
    Sleep(ACTION_SLEEP_MS)

    ; ---------- STEP 8 (LAST) ----------
    Loop
    {
        if (Aborted("Step 8"))
            return
        if (globalMonitorActive && GlobalCheckerFails())
            return
        color := PixelGetColor(1456, 274, "RGB")
        if (!ColorMatches(color, 0xB7393C, TOL))
            break
        Click(1450, 289)
        Sleep(ACTION_SLEEP_MS)
    }

    Sleep(STEP8_SETTLE_MS)
    SetStatus("cycle done")
}


; ============================================================
;  MONITORS / CHECKERS / SUPPORT
; ============================================================
RewardsMonitorFails()
{
    global TOL
    color := PixelGetColor(1124, 248, "RGB")
    if (!ColorMatches(color, 0x9C9C9C, TOL))
        return true
    return false
}

GlobalCheckerFails()
{
    global TOL
    color := PixelGetColor(1137, 253, "RGB")
    if (!ColorMatches(color, 0x9E9E9E, TOL))
        return true
    return false
}

ClickUntilGoneWithMonitor(checkX, checkY, targetColor, clickX, clickY, &monitorActive, label := "")
{
    global ACTION_SLEEP_MS, TOL
    clicked := false
    Loop
    {
        if (Aborted(label))
            return clicked
        if (!monitorActive)
        {
            initColor := PixelGetColor(checkX, checkY, "RGB")
            if (ColorMatches(initColor, targetColor, TOL))
                monitorActive := true
        }
        if (monitorActive && GlobalCheckerFails())
            return clicked
        if (RewardsMonitorFails())
            return clicked
        color := PixelGetColor(checkX, checkY, "RGB")
        if (!ColorMatches(color, targetColor, TOL))
            break
        Click(clickX, clickY)
        clicked := true
        Sleep(ACTION_SLEEP_MS)
    }
    return clicked
}

ReopenRewards()
{
    global GATE_MS, ACTION_SLEEP_MS, TOL, GATE_X, GATE_Y, GATE_COLOR
    Loop
    {
        if (Aborted("ReopenRewards (gate wait)"))
            return
        color := PixelGetColor(GATE_X, GATE_Y, "RGB")
        if (ColorMatches(color, GATE_COLOR, TOL))
            break
        Sleep(GATE_MS)
    }
    attempts := 0
    Loop
    {
        if (Aborted("ReopenRewards"))
            return
        checkColor := PixelGetColor(1504, 461, "RGB")
        if (ColorMatches(checkColor, 0x2B2B2B, TOL))
            return
        if (attempts >= 3)
        {
            Rejoin()
            return
        }
        Click(124, 722)
        attempts++
        Sleep(ACTION_SLEEP_MS)
    }
}

Rejoin()
{
    SetStatus("rejoin")
    MsgBox("Rejoin")
}


; ============================================================
;  COLOR
; ============================================================
ColorMatches(actual, target, tolerance := 10)
{
    actualR := (actual >> 16) & 0xFF
    actualG := (actual >> 8) & 0xFF
    actualB := actual & 0xFF
    targetR := (target >> 16) & 0xFF
    targetG := (target >> 8) & 0xFF
    targetB := target & 0xFF
    return (
        Abs(actualR - targetR) <= tolerance
        && Abs(actualG - targetG) <= tolerance
        && Abs(actualB - targetB) <= tolerance
    )
}