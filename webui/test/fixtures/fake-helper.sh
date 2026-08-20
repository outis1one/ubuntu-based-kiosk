#!/bin/bash
# webui/test/fixtures/fake-helper.sh - stands in for the real, root-owned
# kiosk-webui-helper (menus/addon_webui.sh) in webui/test/jobs.test.js,
# so the job/SSE system can be tested without real root or a real addon
# install. Echoes what it received, sleeps briefly (long enough for the
# "another job is already running" test to reliably observe it), then
# exits with a controllable code.
echo "fake-helper: action=$1"
stdin_content=$(cat)
echo "fake-helper: stdin-bytes=${#stdin_content}"
sleep 0.2
echo "fake-helper: done"
exit "${FAKE_HELPER_EXIT_CODE:-0}"
