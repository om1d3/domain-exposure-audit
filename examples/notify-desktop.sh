#!/usr/bin/env bash
# An example command for the --notify flag. It shows a desktop message with
# libnotify.
#
#   ./domain-exposure-audit.sh -q -c domains.conf --notify examples/notify-desktop.sh
#
# The tool sends a short text summary to stdin. The tool runs this command only
# for a HIGH result, or for a change from the baseline.
set -uo pipefail
body="$(cat)"
[ -n "$body" ] || exit 0
notify-send -u critical -i dialog-warning "The public data for your domain changed" "$body"
