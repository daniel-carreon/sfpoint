"""macOS Input Monitoring (TCC) — check, request, and repair.

pynput listens with a listen-only CGEventTap, which macOS gates behind
kTCCServiceListenEvent = System Settings > Privacy & Security > Input Monitoring.

WHY THIS FILE EXISTS: when the permission is missing (or, worse, when its stored
code requirement no longer matches the app's signature after a rebuild), the tap
is denied SILENTLY. The app looks alive and is completely deaf. Never again:
we preflight, we tell the user, and we offer the one-shot repair.
"""

import subprocess

# Deep link straight to the Input Monitoring list
SETTINGS_PANE = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"


def has_input_monitoring() -> bool:
    """True if this process may listen to global key events."""
    try:
        from Quartz import CGPreflightListenEventAccess
        return bool(CGPreflightListenEventAccess())
    except Exception:
        # Can't tell (old macOS / missing framework) — assume yes, never block.
        return True


def request_input_monitoring() -> bool:
    """Trigger the native prompt. Returns True if already/now granted.

    macOS only shows this prompt ONCE per app signature. If it was denied
    before (or the TCC record is stale), this returns False without any UI —
    which is exactly when the app must speak up on its own.
    """
    try:
        from Quartz import CGRequestListenEventAccess
        return bool(CGRequestListenEventAccess())
    except Exception:
        return False


def open_settings_pane():
    """Open System Settings directly on Privacy > Input Monitoring."""
    try:
        subprocess.Popen(["open", SETTINGS_PANE])
    except Exception:
        pass


def repair_command(bundle_id: str) -> str:
    """The exact command that clears a stale TCC record for this app."""
    return f"tccutil reset ListenEvent {bundle_id}"
