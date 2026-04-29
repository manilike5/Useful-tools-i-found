#NoEnv
#SingleInstance, Force
SetBatchLines, -1
#Persistent
SetTimer, CheckMemory, 1000  ; check delay

; --- CONFIG ---
targetName := "RobloxPlayerBeta.exe"
memoryLimitMB := 100        ; threshold
flushCooldownMS := 100    ; delay cooldown between flushes
; ----------------

; access flags
PROCESS_QUERY_INFORMATION := 0x0400
PROCESS_SET_QUOTA := 0x0100
PROCESS_VM_READ := 0x0010

DllCall("LoadLibrary", "Str", "psapi.dll")  ; ensure psapi loaded
lastFlush := 0

CheckMemory:
{
    pids := []
    for proc in ComObjGet("winmgmts:").ExecQuery("Select ProcessId from Win32_Process where Name='" targetName "'")
        pids.Push(proc.ProcessId)

    if (pids.Length() = 0) {
        return
    }

    totalMB := 0
    perProc := {}  ; store per-process working set
    for index, pid in pids {
        ws := GetWorkingSet(pid)
        if (ws >= 0) {
            perProc[pid] := ws
            totalMB += ws
        }
    }

    ; decide to flush
    if (totalMB > memoryLimitMB) {
        if (A_TickCount - lastFlush < flushCooldownMS) {
            ; still in cooldown
            return
        }

        flushed := 0
        ; attempt to flush each chrome.exe process
        for pid, ws in perProc {
            hProc := DllCall("OpenProcess", "UInt", PROCESS_QUERY_INFORMATION|PROCESS_SET_QUOTA, "Int", 0, "UInt", pid, "Ptr")
            if (hProc) {
                ok := DllCall("psapi\EmptyWorkingSet", "Ptr", hProc) ; returns non-zero on success
                DllCall("CloseHandle", "Ptr", hProc)
                if (ok)
                    flushed++
            }
            ; else: couldn't open process (likely permission); skip
        }
        lastFlush := A_TickCount
    }
}
return

; --- helper: returns working set in MB, or -1 on failure
GetWorkingSet(pid)
{
    PROCESS_QUERY_INFORMATION := 0x0400
    PROCESS_VM_READ := 0x0010

    h := DllCall("OpenProcess", "UInt", PROCESS_QUERY_INFORMATION|PROCESS_VM_READ, "Int", 0, "UInt", pid, "Ptr")
    if (!h)
        return -1

    size := (A_PtrSize = 8) ? 72 : 44
    VarSetCapacity(pm, size, 0)
    ok := DllCall("psapi\GetProcessMemoryInfo", "Ptr", h, "Ptr", &pm, "UInt", size)
    if (!ok) {
        DllCall("CloseHandle", "Ptr", h)
        return -1
    }
    workingSet := NumGet(pm, 8, "UPtr")  ; WorkingSetSize offset
    DllCall("CloseHandle", "Ptr", h)
    return workingSet / 1024 / 1024  ; MB
}
