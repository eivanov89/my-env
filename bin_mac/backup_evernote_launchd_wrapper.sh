#!/bin/bash
set -u

LOG="/Users/eivanov89/Library/Logs/launchd_wrapper.log"
ALT="/tmp/launchd_wrapper.$(id -u).log"

# Always try to create a proof-of-life file
/usr/bin/touch "/tmp/launchd_wrapper_ran.$(id -u)" 2>/dev/null

# Ensure log dirs exist
/bin/mkdir -p "/Users/eivanov89/Library/Logs" 2>>"$ALT"

# Append to ALT no matter what
{
  echo "=== wrapper start $(/bin/date) ==="
  /usr/bin/id
  echo "HOME=$HOME"
  echo "PATH=$PATH"
  echo "Trying to append to $LOG ..."
} >>"$ALT" 2>&1

# Now try to append to the main LOG and record success/failure in ALT
if echo "=== wrapper start $(/bin/date) ===" >>"$LOG" 2>>"$ALT"; then
  echo "OK: appended to $LOG" >>"$ALT"
else
  echo "FAIL: could not append to $LOG" >>"$ALT"
fi

# Make brew visible
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Cron does not inherit the SSH agent socket used by Skotty.
export SSH_AUTH_SOCK="/Users/eivanov89/.skotty/sock/default.sock"

# Run the real script, append everything to ALT so we see it even if LOG fails
/bin/bash /Users/eivanov89/bin/backup_evernote.sh >>"$ALT" 2>&1
rc=$?

echo "rc=$rc" >>"$ALT"
echo "=== wrapper end $(/bin/date) ===" >>"$ALT"
exit $rc
