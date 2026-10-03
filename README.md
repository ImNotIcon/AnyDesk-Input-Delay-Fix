# AnyDesk closed-lid pointer delay on Linux

## Summary

Some Linux laptops exhibit severe remote pointer delay in AnyDesk when the
physical lid is closed. Keyboard input and mouse-button clicks remain immediate,
but pointer motion is delivered at a much lower frequency. Opening the lid
immediately restores normal movement.

This project provides a connection-scoped workaround. It temporarily detaches
the kernel ACPI lid-switch device while an AnyDesk remote session is active and
reattaches it after the final session disconnects. Normal lid detection remains
available outside AnyDesk sessions.

## Observed behavior and diagnosis

The problem can look like video latency, display refresh trouble, or slow input
processing. XInput event timing distinguishes those cases.

In one reproducible case, `xinput test-xi2 --root` measured:

| Lid state | Mean interval | Effective pointer rate |
| --- | ---: | ---: |
| Open | 8.89 ms | 112.55 Hz |
| Closed | approximately 100-112 ms | approximately 9-10 Hz |

The events originated from `Virtual core XTEST pointer`, the path used by
AnyDesk to inject remote input. Each event was processed by Xorg immediately
after arrival. This showed that the delay occurred before Xorg received the
motion event; it was not delayed cursor rendering.

The following experiments did not resolve the issue:

- switching the internal panel between 60 Hz and 40 Hz;
- disabling the physical touchpad;
- using a VKMS virtual display instead of the internal panel;
- changing an AMD display-core debug mask;
- changing Mutter's fractional-scaling experiment;
- restarting AnyDesk and related desktop components.

Unbinding the ACPI lid switch while it reported the open state restored the
normal XTEST event rate after physically closing the lid. This isolates the
trigger to the lid state visible through the Linux input/ACPI stack.

## How the workaround operates

The installation contains three components:

- `anydesk-input-delay-fix` binds or unbinds one ACPI lid device;
- `anydesk-input-delay-fix-watcher` follows the AnyDesk trace and invokes the
  helper at session lifecycle boundaries;
- `anydesk-input-delay-fix.service` runs the watcher under systemd.

The watcher responds to these AnyDesk trace markers:

- `Session started (ok).` - unbind the lid switch;
- `Session count: 0` - rebind the lid switch.

The helper is idempotent. Restarting or stopping the service restores the lid
switch, and `ExecStopPost` provides an additional recovery path. The watcher
also examines the latest lifecycle marker when starting, so a service restart
during an existing session restores the appropriate state.

## Requirements and configuration

The installer detects the desktop account and ACPI lid device, then writes them
to `/etc/default/anydesk-input-delay-fix`. A typical configuration looks like:

```text
LID_DEVICE=PNP0C0D:00
ANYDESK_TRACE_FILE=/home/USERNAME/.anydesk/anydesk.trace
```

Different systems should identify their lid device with:

```sh
grep -l 'Lid Switch' /sys/class/input/input*/name
readlink -f /sys/class/input/inputN/device
```

Either value can be overridden in `/etc/default/anydesk-input-delay-fix`:

```sh
LID_DEVICE=PNP0C0D:00
ANYDESK_TRACE_FILE=/home/USERNAME/.anydesk/anydesk.trace
```

The current implementation targets AnyDesk's X11 backend and trace format. A
future AnyDesk release may change its lifecycle messages or trace location.

## Installation

From this repository, run the detection-based installer:

```sh
sudo ./install.sh
```

When installing from a root shell rather than through `sudo`, specify the
desktop account explicitly:

```sh
sudo ANYDESK_USER=USERNAME ./install.sh
```

## Verification

Check the watcher:

```sh
systemctl status anydesk-input-delay-fix.service
```

Check the current lid-driver state:

```sh
sudo /usr/local/sbin/anydesk-input-delay-fix status
```

Expected behavior:

- without a remote session: `Lid switch is bound`;
- during a remote session: `Lid switch is unbound`;
- after disconnecting: it returns to `bound` within a few seconds.

## Limitations and safety

While a remote session is active, all applications temporarily lose lid-state
events because the kernel device is system-wide. The isolation is temporal,
not per-process. Closing the lid during that interval will not trigger suspend,
blanking, or other lid actions.

The approach intentionally depends on AnyDesk trace text because AnyDesk does
not expose a stable public Linux connection-state interface suitable for this
purpose. Confirm behavior again after major AnyDesk upgrades.

## Disable or uninstall

Stopping the service immediately restores normal lid detection:

```sh
sudo systemctl stop anydesk-input-delay-fix.service
```

Remove the installation completely with:

```sh
sudo systemctl disable --now anydesk-input-delay-fix.service
sudo rm /etc/systemd/system/anydesk-input-delay-fix.service
sudo rm /usr/local/sbin/anydesk-input-delay-fix-watcher
sudo rm /usr/local/sbin/anydesk-input-delay-fix
sudo rm /etc/default/anydesk-input-delay-fix
sudo systemctl daemon-reload
```

Rebooting also restores the kernel binding if the service is disabled or
removed.
