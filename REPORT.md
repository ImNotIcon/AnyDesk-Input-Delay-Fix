# Investigation: closed-lid AnyDesk input delay

## Evidence

On an Ubuntu X11 laptop, remote pointer movement slowed when the lid closed,
while keyboard input and clicks stayed responsive. XInput traces showed motion
injected through `Virtual core XTEST pointer`:

| Lid state | Event interval | Effective rate |
| --- | ---: | ---: |
| Open | 8.89 ms average | 112.55 Hz |
| Closed | approximately 100–112 ms | approximately 9–10 Hz |

RawMotion and Motion timestamps matched. The reduced arrival rate points to
delay before Xorg receives injected motion; it does not establish which internal
AnyDesk component causes it. Removing the ACPI lid input device eliminated the
observed delay. This is evidence from one system, not a universal diagnosis.

Changing 60 Hz to 40 Hz, disabling the touchpad, using VKMS, changing an AMD
display-core debug mask, changing Mutter fractional scaling, and restarting
desktop components did not resolve the symptom.

## Session tracking

The Bash watcher validates backend log PIDs against live `/proc` process start
times. It reconstructs sessions from the trace at startup, then reads only new
bytes using an open descriptor. Incomplete lines are retained between polls.
File replacement or detectable truncation reopens the trace. States survive log
rotation until a disconnect marker or backend exit clears them. A truncate and
regrow beyond the old offset between polls cannot reliably be detected.

`Session started (ok).` activates the workaround. `Session count: 0` clears that
backend's state. The switch remains detached while any tracked backend has an
active session. Backend exits also clear state, including after crashes.
Shutdown recovery is owned by systemd's `ExecStopPost`, so it also covers a
watcher crash or forced exit without duplicate shell-trap recovery.

## Restoring lid and display state

Opening the lid while the device is detached produces no normal input event.
Rebinding alone initially left UPower reporting closed while ACPI reported open.
This stale state corresponded to the desktop display problem.

The helper temporarily selects the ACPI driver's `method` initialization mode
when rebinding, then restores the previous setting. After one second it compares
ACPI with UPower. On disagreement it restarts UPower; this was observed to clear
the stale cache. This recovery briefly refreshes desktop power information.

The internal panel may remain connected in RandR with the lid closed. Connector
presence, lid state, display configuration, and panel illumination are distinct.
The workaround creates no virtual monitor.
