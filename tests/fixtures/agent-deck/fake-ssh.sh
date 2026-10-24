#!/bin/sh
# Stands in for ssh: runs the remote command through sh, as sshd would, inside
# a fake remote HOME whose agent-deck is the fake CLI and whose hostname is fixed.
for last; do :; done
if [ -f "$FAKE_REMOTE_DIR/offline" ]; then echo 'ssh: connect to host: Connection refused' >&2; exit 255; fi
printf '%s\n' "$last" >> "$FAKE_REMOTE_DIR/commands.log"
HOME="$FAKE_REMOTE_HOME" PATH="$FAKE_REMOTE_HOME/bin:$PATH" FAKE_DECK_DIR="$FAKE_REMOTE_DIR" exec sh -c "$last"
