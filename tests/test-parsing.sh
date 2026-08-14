#!/usr/bin/env bash
#
# tests/test-parsing.sh — tests for the parts of the tool that read the answers
# of other servers.
#
# Version 1.0.1 corrected two faults that a run on three real domains found.
# Each test below holds the real data from that run.
#
# The functions under test are inside domain-exposure-audit.sh, and that file
# runs a full audit when you call it. Therefore this file holds a copy of the
# logic, and it tests the copy. A comment in each section names the lines in the
# tool that the copy comes from. If you change the tool, change the copy.
#
# Run:  ./tests/test-parsing.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../domain-exposure-audit.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

lc() { tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------------------
# 1. RDAP status values
# ---------------------------------------------------------------------------
# RFC 9083 writes a status in lowercase with spaces:
#     "client transfer prohibited"
# The EPP name for the same status is:
#     "clientTransferProhibited"
# Version 1.0.0 compared the RDAP answer against the EPP name. The two never
# matched, therefore NO-TRANSFER-LOCK fired for every domain in the world. The
# run on horia.wtf showed "client transfer prohibited" one line above the wrong
# result.
#
# From check_registration() in domain-exposure-audit.sh.

flatten_status() { printf '%s' "$1" | tr -d ' _-' | lc; }

has_transfer_lock() {
  case "$(flatten_status "$1")" in
    *clienttransferprohibited*|*servertransferprohibited*) printf 'yes' ;;
    *) printf 'no' ;;
  esac
}
has_update_lock() {
  case "$(flatten_status "$1")" in
    *clientupdateprohibited*|*serverupdateprohibited*) printf 'yes' ;;
    *) printf 'no' ;;
  esac
}

printf '\n\033[1mRDAP status values — the form with spaces (RFC 9083)\033[0m\n'
assert_eq "the real answer from horia.wtf" yes \
  "$(has_transfer_lock 'client transfer prohibited')"
assert_eq "two statuses"                   yes \
  "$(has_transfer_lock 'client delete prohibited,client transfer prohibited')"
assert_eq "a server status"                yes \
  "$(has_transfer_lock 'server transfer prohibited')"
assert_eq "an update lock with spaces"     yes \
  "$(has_update_lock 'client update prohibited')"

printf '\n\033[1mRDAP status values — the EPP form\033[0m\n'
assert_eq "the EPP name"                   yes "$(has_transfer_lock 'clientTransferProhibited')"
assert_eq "the EPP name in a list"         yes \
  "$(has_transfer_lock 'clientDeleteProhibited,clientTransferProhibited')"
assert_eq "an EPP update lock"             yes "$(has_update_lock 'clientUpdateProhibited')"

printf '\n\033[1mRDAP status values — a lock that is truly absent\033[0m\n'
assert_eq "no status at all"               no  "$(has_transfer_lock '')"
assert_eq "another status only"            no  "$(has_transfer_lock 'active')"
assert_eq "a delete lock only"             no  "$(has_transfer_lock 'client delete prohibited')"
assert_eq "no update lock"                 no  "$(has_update_lock 'client transfer prohibited')"

# ---------------------------------------------------------------------------
# 2. The HTTP code from curl
# ---------------------------------------------------------------------------
# Version 1.0.0 used this form:
#     code="$(curl ... -w '%{http_code}' url || printf '000')"
# When the connection fails, curl writes 000 from -w AND stops with a code that
# is not 0. Therefore the shell also ran printf, and the result was "000000".
# That value is not valid JSON for --argjson, and the test for "000" never
# matched, therefore the branch for "no answer" never ran.
#
# From http_code() in domain-exposure-audit.sh.

http_code() {
  local out
  out="$("$@" 2>/dev/null)"
  case "$out" in
    ""|*[!0-9]*) printf '000' ;;
    *)           printf '%s' "${out: -3}" ;;
  esac
}

# These commands imitate curl. They do not use the network.
fake_ok()        { printf '200'; return 0; }
fake_redirect()  { printf '301'; return 0; }
fake_notfound()  { printf '404'; return 0; }
fake_fail()      { printf '000'; return 7; }    # curl code 7: cannot connect
fake_timeout()   { printf '000'; return 28; }   # curl code 28: too slow
fake_silent()    { return 6; }                  # no output at all
fake_multi()     { printf '301200'; return 0; } # two codes, after a redirect

printf '\n\033[1mThe HTTP code from curl — a normal answer\033[0m\n'
assert_eq "code 200" 200 "$(http_code fake_ok)"
assert_eq "code 301" 301 "$(http_code fake_redirect)"
assert_eq "code 404" 404 "$(http_code fake_notfound)"

printf '\n\033[1mThe HTTP code from curl — a failure gives 000 one time\033[0m\n'
assert_eq "the connection failed" 000 "$(http_code fake_fail)"
assert_eq "the request was too slow" 000 "$(http_code fake_timeout)"
assert_eq "curl wrote nothing" 000 "$(http_code fake_silent)"

printf '\n\033[1mThe HTTP code from curl — the value is always three digits\033[0m\n'
# This is the fault: the old code gave 000000 here.
assert_eq "the length is 3, not 6" 3 "$(printf '%s' "$(http_code fake_fail)" | wc -c | tr -d ' ')"
assert_eq "the last code after a redirect" 200 "$(http_code fake_multi)"

printf '\n\033[1mThe HTTP code from curl — the value is valid JSON\033[0m\n'
if command -v jq >/dev/null 2>&1; then
  for f in fake_ok fake_fail fake_silent fake_multi; do
    c="$(http_code $f)"
    if printf '{"code":%s}' "$c" | jq -e . >/dev/null 2>&1; then
      ok "'$c' from $f is valid JSON"
    else
      bad "'$c' from $f is not valid JSON"
    fi
  done
else
  printf '  \033[2m- jq is absent, therefore the tool did not run this test\033[0m\n'
fi

# ---------------------------------------------------------------------------
# 3. The tool must not hold the old faults
# ---------------------------------------------------------------------------

printf '\n\033[1mThe tool file must not hold the old code\033[0m\n'
if [ -r "$TOOL" ]; then
  if grep -q "|| printf '000'" "$TOOL"; then
    bad "domain-exposure-audit.sh still holds the form that gives 000000"
  else
    ok "domain-exposure-audit.sh does not hold the form that gives 000000"
  fi
  if grep -qE '\*clientTransferProhibited\*\)' "$TOOL"; then
    bad "domain-exposure-audit.sh still compares against the EPP name only"
  else
    ok "domain-exposure-audit.sh compares both forms of a status"
  fi
  if grep -q 'grep -qvE "\$REDACTION_PATTERNS"' "$TOOL"; then
    bad "domain-exposure-audit.sh still inverts a text search for WHOIS on port 43"
  else
    ok "domain-exposure-audit.sh uses is_redacted for WHOIS on port 43"
  fi
else
  bad "the tool file is not readable at $TOOL"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m%s passed, 0 failed\033[0m\n\n' "$PASS"; exit 0
else
  printf '\033[31m%s passed, %s FAILED\033[0m\n\n' "$PASS" "$FAIL"; exit 1
fi
