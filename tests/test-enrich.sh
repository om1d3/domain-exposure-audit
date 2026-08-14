#!/usr/bin/env bash
#
# tests/test-enrich.sh: tests for the enrichment layer and for the resolver.
#
# The tests use no network. The file makes fake copies of dig, subfinder, and
# theHarvester, then it puts them first in PATH. Therefore the tests read the
# real functions of the tool, but the functions get data that this file
# controls.
#
# The file takes each function out of domain-exposure-audit.sh with awk. It does
# not hold a copy of the code. Therefore a change in the tool changes the test.
#
# Run:  ./tests/test-enrich.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../domain-exposure-audit.sh"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '  \033[2m- %s\033[0m\n' "$1"; }
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dea-enrich.XXXXXX")"
BIN="$TMP/bin"; mkdir -p "$BIN"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

[ -r "$TOOL" ] || { printf 'the tool file is not readable at %s\n' "$TOOL"; exit 1; }

# ---------------------------------------------------------------------------
# Take the functions out of the tool
# ---------------------------------------------------------------------------

extract_fn() { # extract_fn NAME
  awk -v n="$1" 'BEGIN{p="^"n"\\(\\) \\{$"} $0 ~ p {f=1} f {print} f && /^\}$/ {exit}' "$TOOL"
}
extract_heredoc() { # extract_heredoc TAG
  awk -v t="$1" 'index($0,"<<\x27"t"\x27"){f=1;next} $0==t{f=0} f' "$TOOL"
}

RESOLVER="$TMP/resolve1.sh"
extract_heredoc RESOLVER > "$RESOLVER"
if [ -s "$RESOLVER" ]; then ok "the tool holds the resolver helper"; else
  bad "the tool does not hold the resolver helper"; fi

LIB="$TMP/fns.sh"
{
  printf 'set -uo pipefail\n'
  printf 'DEA_TIMEOUT=20\nDEA_HARVEST_SOURCES="bing"\nENRICH_ALL=""\n'
  printf 'WORK="%s"\nR_FILE="$WORK/results.tsv"\n: > "$R_FILE"\n' "$TMP"
  printf 'add_result() { printf "%%s\\t%%s\\t%%s\\n" "$1" "$2" "$3" >> "$R_FILE"; }\n'
  extract_fn enrich_subfinder
  extract_fn enrich_harvester
} > "$LIB"
for fn in enrich_subfinder enrich_harvester; do
  if grep -q "^$fn() {" "$LIB"; then ok "the tool holds $fn"; else bad "the tool does not hold $fn"; fi
done
# shellcheck disable=SC1090
. "$LIB"

# ---------------------------------------------------------------------------
# Fake programs
# ---------------------------------------------------------------------------

cat > "$BIN/dig" <<'FAKE'
#!/usr/bin/env bash
q=""; t=""
for a in "$@"; do
  case "$a" in -*|+*) ;; A|AAAA|SOA|NS|MX|TXT|CAA|DS) t="$a" ;; *) q="$a" ;; esac
done
if [ "$t" = "AAAA" ]; then
  case "$q" in
    two.example.com) echo "2001:db8::1"; echo "2001:db8::2" ;;
    slow.example.com) echo ";; connection timed out; no servers could be reached" ;;
  esac
  exit 0
fi
case "$q" in
  two.example.com)
    printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n'
    printf 'two.example.com.\t300\tIN\tCNAME\talias.example.net.\n'
    printf 'alias.example.net.\t300\tIN\tA\t203.0.113.8\n'
    printf 'alias.example.net.\t300\tIN\tA\t203.0.113.7\n' ;;
  gone.example.com)
    printf ';; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 2\n' ;;
  slow.example.com)
    printf ';; connection timed out; no servers could be reached\n' ;;
esac
FAKE

cat > "$BIN/subfinder" <<'FAKE'
#!/usr/bin/env bash
# The output holds the forms that a real program gives: uppercase letters, a
# dot at the end, spaces, a name outside the domain, a wildcard, and junk.
cat <<'D'
WWW.example.com
vault.example.com.
  mail.example.com  
evil.attacker.com
example.com
*.example.com
notadomain
sub.deep.example.com
VAULT.example.com
D
FAKE

cat > "$BIN/theHarvester" <<'FAKE'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-f" ] && out="$a"; prev="$a"; done
cat > "${out}.json" <<'J'
{"emails":["horia@example.com","admin@example.com","horia@example.com"],
 "hosts":["Portal.example.com:203.0.113.9","old.example.com","x.other.net","example.com"],
 "ips":["203.0.113.9"]}
J
FAKE

cat > "$BIN/theHarvester_broken" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
chmod +x "$BIN"/*
PATH="$BIN:$PATH"

# ---------------------------------------------------------------------------
# 1. The resolver
# ---------------------------------------------------------------------------

printf '\n\033[1mThe resolver – one name at a time\033[0m\n'
OUT="$TMP/r.tsv"; : > "$OUT"
bash "$RESOLVER" two.example.com "$OUT"
bash "$RESOLVER" gone.example.com "$OUT"
bash "$RESOLVER" slow.example.com "$OUT"

get() { awk -F'\t' -v h="$1" -v f="$2" '$1 == h { print $f }' "$OUT"; }

assert_eq "the status of a name that exists"  NOERROR  "$(get two.example.com 2)"
assert_eq "the status of a name that is gone" NXDOMAIN "$(get gone.example.com 2)"
# The tool must follow a CNAME and give the addresses in a fixed order.
assert_eq "two A records, in order"  "203.0.113.7,203.0.113.8" "$(get two.example.com 3)"
assert_eq "two AAAA records"         "2001:db8::1,2001:db8::2" "$(get two.example.com 4)"
assert_eq "no A record"              ""       "$(get gone.example.com 3)"
assert_eq "no AAAA record"           ""       "$(get gone.example.com 4)"

# A message about a timeout holds a colon. The old filter accepted any line with
# a colon, therefore the message became an address.
assert_eq "a timeout message is not an address" "" "$(get slow.example.com 4)"
assert_eq "a timeout gives no A record"         "" "$(get slow.example.com 3)"

printf '\n\033[1mThe resolver – many names at the same time\033[0m\n'
: > "$TMP/names.txt"
for i in $(seq 1 60); do printf 'two.example.com\n' >> "$TMP/names.txt"; done
CONC="$TMP/conc.tsv"; : > "$CONC"
xargs -a "$TMP/names.txt" -P 8 -I{} bash "$RESOLVER" {} "$CONC" 2>/dev/null
assert_eq "60 lines for 60 names" 60 "$(wc -l < "$CONC" | tr -d ' ')"
assert_eq "each line holds four fields" 60 "$(awk -F'\t' 'NF == 4' "$CONC" | wc -l | tr -d ' ')"
assert_eq "the lines do not mix with each other" 1 "$(sort -u "$CONC" | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
# 2. subfinder
# ---------------------------------------------------------------------------

printf '\n\033[1msubfinder – the tool keeps only the names in the domain\033[0m\n'
NAMES="$(enrich_subfinder example.com)"
assert_eq "the number of names" 4 "$(printf '%s\n' "$NAMES" | grep -c . || true)"
for want in www.example.com vault.example.com mail.example.com sub.deep.example.com; do
  if printf '%s\n' "$NAMES" | grep -qx "$want"; then ok "the list holds $want"
  else bad "the list does not hold $want"; fi
done
for bad_name in evil.attacker.com notadomain '*.example.com' example.com; do
  if printf '%s\n' "$NAMES" | grep -qx -- "$bad_name"; then
    bad "the list must not hold $bad_name"
  else ok "the list does not hold $bad_name"; fi
done
# The fake program gives VAULT.example.com and vault.example.com.
assert_eq "the tool writes each name one time" 1 \
  "$(printf '%s\n' "$NAMES" | grep -cx vault.example.com || true)"

# ---------------------------------------------------------------------------
# 3. theHarvester
# ---------------------------------------------------------------------------

printf '\n\033[1mtheHarvester\033[0m\n'
if command -v jq >/dev/null 2>&1; then
  : > "$R_FILE"
  HNAMES="$(enrich_harvester example.com)"
  assert_eq "the tool keeps two hostnames" 2 "$(printf '%s\n' "$HNAMES" | grep -c . || true)"
  if printf '%s\n' "$HNAMES" | grep -qx portal.example.com; then
    ok "the tool removes the address after the hostname"
  else bad "the tool does not remove the address after the hostname"; fi
  if printf '%s\n' "$HNAMES" | grep -qx x.other.net; then
    bad "the list must not hold a name outside the domain"
  else ok "the list does not hold a name outside the domain"; fi

  assert_eq "one result for each email address" 2 \
    "$(grep -c 'HARVEST-EMAIL' "$R_FILE" || true)"
  if grep -q 'horia@example.com' "$R_FILE"; then ok "the result names the email address"
  else bad "the result does not name the email address"; fi
  assert_eq "the same address gives one result only" 1 \
    "$(grep -c 'horia@example.com' "$R_FILE" || true)"

  # A program that writes no file must not stop the tool.
  cp "$BIN/theHarvester_broken" "$BIN/theHarvester"
  : > "$R_FILE"
  if enrich_harvester example.com >/dev/null 2>&1; then
    bad "a broken program must give a code that is not 0"
  else ok "a broken program gives a code that is not 0"; fi
  assert_eq "a broken program writes no result" 0 "$(grep -c . "$R_FILE" || true)"
else
  skip "jq is absent, therefore the tool did not run the theHarvester tests"
fi

# ---------------------------------------------------------------------------
# 4. The tool must keep the correct order and the correct flags
# ---------------------------------------------------------------------------

printf '\n\033[1mThe tool file\033[0m\n'
# The 404 branch must come before the test for valid JSON. An RDAP server that
# does not hold a TLD answers 404 with a body that is not JSON.
line_404="$(grep -n '^    404)' "$TOOL" | head -1 | cut -d: -f1)"
line_jq="$(grep -n 'jq -e . "\$reg"' "$TOOL" | head -1 | cut -d: -f1)"
if [ -n "$line_404" ] && [ -n "$line_jq" ] && [ "$line_404" -lt "$line_jq" ]; then
  ok "the branch for 404 comes before the test for valid JSON"
else
  bad "the branch for 404 must come before the test for valid JSON (404 at ${line_404:-?}, JSON at ${line_jq:-?})"
fi

if grep -q "grep ':' | sort -u | paste" "$TOOL"; then
  bad "the tool still accepts any line with a colon as an IPv6 address"
else
  ok "the tool does not accept any line with a colon as an IPv6 address"
fi

if grep -q -- '-P "\$DEA_PARALLEL"' "$TOOL"; then
  ok "the tool resolves the names at the same time"
else
  bad "the tool does not resolve the names at the same time"
fi

if grep -q 'certspotter' "$TOOL"; then
  ok "the tool has a second service for Certificate Transparency"
else
  bad "the tool has one service only for Certificate Transparency"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m%s passed, 0 failed' "$PASS"
  [ "$SKIP" -gt 0 ] && printf ', %s skipped' "$SKIP"
  printf '\033[0m\n\n'; exit 0
else
  printf '\033[31m%s passed, %s FAILED\033[0m\n\n' "$PASS" "$FAIL"; exit 1
fi
