# App Lock Lifecycle MVP Plan

## Current implementation in this round

1. Flutter listens to app lifecycle changes.
2. On `paused` / `inactive` / `hidden`, the app records background timestamp.
3. On `resumed`, it compares elapsed time with `auto_lock_seconds` from settings.
4. If elapsed time reaches threshold, session is locked again.

## Current limitations

1. Android recent-task thumbnail protection is still a placeholder bridge only.
2. No dedicated obscuring overlay has been implemented yet.
3. iOS lifecycle-specific behavior has not been tuned.

## Next native steps

1. Add a secure overlay view on background transition.
2. Hide sensitive content when app enters recents screen.
3. Coordinate overlay state with Flutter lock session state.
