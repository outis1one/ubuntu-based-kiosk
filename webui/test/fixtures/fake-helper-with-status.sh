#!/bin/bash
# Variant of fake-helper.sh that also implements status_all with real,
# minimally stateful JSON (tracked via marker files alongside itself),
# for browser/manual smoke testing of the Addons page's pills/buttons
# actually flipping after a real install - not just that a job reports
# success. jobs.test.js intentionally uses the plainer fake-helper.sh
# instead, to exercise the malformed-status-response error path.
STATE_DIR="$(dirname "$0")/.fake-state"
mkdir -p "$STATE_DIR"

if [[ "$1" == "status_all" ]]; then
    state() { [[ -f "$STATE_DIR/$1" ]] && echo true || echo false; }
    echo "{\"cups\":$(state cups),\"lms\":$(state lms),\"squeezelite\":$(state squeezelite),\"asterisk_intercom\":$(state asterisk_intercom)}"
    exit 0
fi

echo "fake-helper: action=$1"
stdin_content=$(cat)
echo "fake-helper: stdin-bytes=${#stdin_content}"
sleep 0.3

case "$1" in
    action_install_cups | action_reconfigure_cups) touch "$STATE_DIR/cups" ;;
    action_install_lms) touch "$STATE_DIR/lms" ;;
    action_install_squeezelite) touch "$STATE_DIR/squeezelite" ;;
    action_configure_asterisk_intercom) touch "$STATE_DIR/asterisk_intercom" ;;
esac

echo "fake-helper: done"
exit "${FAKE_HELPER_EXIT_CODE:-0}"
