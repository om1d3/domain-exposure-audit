#!/usr/bin/env bash
#
# domain-exposure-audit – a tool that finds the public data about your domains
#
# The tool answers two questions each time you run it:
#   1. What can an unknown person find out about you from this domain today?
#   2. What is different from the last time?
#
# The tool only reads. It queries public services only. It makes no change to a
# zone, a registration, or a server.
#
# docs/CHECKS.md tells you what each check does and how to read the results.
# docs/STE-COMPLIANCE.md tells you about the language rules for this project.
#
# SPDX-License-Identifier: MIT
#
# 1.3.1 CHANGES
#   - No change to the tool. docs/INTENT.md is new, and the language checker
#     had three faults. See CHANGELOG.md.
#
# 1.3.0 CHANGES
#   - The cache moved out of the state directory. Therefore "rm -rf state" no
#     longer deletes the Certificate Transparency cache. That cache is the only
#     protection against a crt.sh outage.
#   - --baseline refuses to write a baseline from a run that did not see all
#     the data. Use --force-baseline to write it anyway.
#   - CT-UNAVAILABLE names the HTTP code of each service, and it separates a
#     transport failure from an answer that holds no certificate.
#   - The retry delay for crt.sh is longer, because 502 and 503 mean that the
#     service has too much work.
#   - SOA-PROVIDER is a new result. The tool no longer says that the SOA
#     contact of your DNS provider is possibly your own mailbox.
#   - Check 3b gives a correct message when Certificate Transparency gave no
#     data.
#   - The notify command works. An unconditional "return 0" made the code
#     unreachable in every version up to 1.2.1.
#   - The tool stops if bash is older than version 4.2.

set -uo pipefail

# The tool uses mapfile, associative arrays, and ${var: -3}. Bash 4.2 or a
# later version gives all three. macOS gives bash 3.2 as its system bash.
if [ -z "${BASH_VERSINFO:-}" ] \
   || [ "${BASH_VERSINFO[0]}" -lt 4 ] \
   || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
  printf 'This tool needs bash 4.2 or a later version. This bash is %s.\n' \
    "${BASH_VERSION:-unknown}" >&2
  printf 'On macOS, install a later version with: brew install bash\n' >&2
  exit 8
fi

VERSION="1.3.1"
PROGNAME="${0##*/}"

# ---------------------------------------------------------------------------
# Default values. Flags and environment variables can change them.
# ---------------------------------------------------------------------------

: "${DEA_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/domain-exposure-audit}"
: "${DEA_REPORT_DIR:=$DEA_STATE_DIR/reports}"
# 1.3.0: The cache is NOT under the state directory. The documented way to make
# a new baseline is "rm -rf state". When the cache was inside that directory,
# the command also deleted the answers from crt.sh. The tool then had no stale
# answer to fall back on, and crt.sh fails often.
: "${DEA_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/domain-exposure-audit}"
: "${DEA_CONFIG:=}"
: "${DEA_TIMEOUT:=20}"
: "${DEA_CT_CACHE_HOURS:=168}"
: "${DEA_PARALLEL:=8}"
: "${DEA_HARVEST_SOURCES:=bing,duckduckgo,crtsh,otx,urlscan,rapiddns}"
: "${DEA_NOTIFY_CMD:=}"
: "${DEA_USER_AGENT:=domain-exposure-audit/$VERSION (+self-audit)}"
: "${SHODAN_API_KEY:=}"

DOMAINS=()
WORDLIST=""
DO_HTTP=1
DO_CT=1
DO_ARCHIVE=1
DO_EXIF=0
DO_ENRICH=1
DO_HARVEST=0
ENRICH_ALL=""
SET_BASELINE=0
FORCE_BASELINE=0
DIFF_ONLY=0
EMIT_JSON=0
QUIET=0
COLOR=1

# Possible subdomain names. The tool uses this list together with the names
# from Certificate Transparency. Certificate Transparency is the better source.
# This list finds only the names that have no certificate in a public log.
DEFAULT_WORDS=(
  www mail smtp imap pop webmail mx mx1 mx2 autodiscover autoconfig
  ftp sftp files share cloud nextcloud owncloud drive
  cpanel whm plesk webmin direct origin direct-connect real
  server host host1 vps box gateway gw edge
  vpn wg wireguard ssh remote rdp tailscale ts
  dev devel staging stage test testing qa beta preview next
  admin adminer panel dashboard portal manage
  api api-dev graphql ws socket
  git gitlab gitea forge ci jenkins drone build
  home nas synology unraid truenas proxmox pve esxi
  router gateway modem printer cam camera nvr doorbell
  plex jellyfin emby sonarr radarr transmission qbit
  pass vault bitwarden vaultwarden passbolt keycloak auth sso
  status uptime monitor grafana prometheus metrics logs kibana
  db database mysql postgres pg redis mongo
  backup backups old legacy archive tmp temp staging2
  blog shop store cdn static assets img media
  mail-in mailgun smtp-relay relay
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ ! -t 1 ]; then COLOR=0; fi
c() { # c COLOR TEXT
  if [ "$COLOR" -eq 1 ]; then
    case "$1" in
      red)    printf '\033[31m%s\033[0m' "$2" ;;
      green)  printf '\033[32m%s\033[0m' "$2" ;;
      yellow) printf '\033[33m%s\033[0m' "$2" ;;
      blue)   printf '\033[34m%s\033[0m' "$2" ;;
      dim)    printf '\033[2m%s\033[0m'  "$2" ;;
      bold)   printf '\033[1m%s\033[0m'  "$2" ;;
      *)      printf '%s' "$2" ;;
    esac
  else
    printf '%s' "$2"
  fi
}
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
head1() { [ "$QUIET" -eq 1 ] || { printf '\n'; c bold "$*"; printf '\n'; }; }
warn() { printf '%s %s\n' "$(c yellow '[warn]')" "$*" >&2; }
die()  { printf '%s %s\n' "$(c red '[fatal]')" "$*" >&2; exit 8; }

usage() {
  cat <<EOF
$PROGNAME $VERSION – find the public data about domains that you own

USAGE
  $PROGNAME [options] [domain ...]

DOMAIN SELECTION
  -d, --domain DOMAIN     examine DOMAIN. Use this flag more than one time
                          to examine more than one domain.
  -c, --config FILE       read the domains from FILE. Put one domain on each
                          line. The tool ignores a line that starts with #.
                          Default: ./domains.conf, then
                          \$XDG_CONFIG_HOME/domain-exposure-audit/domains.conf

BASELINE AND CHANGES
      --baseline          keep this run as the baseline. The tool refuses if a
                          service gave no data in this run, because the next
                          run then shows the recovery of that service as a
                          change to your domain.
      --force-baseline    write the baseline even if a service gave no data
      --diff-only         show only the changes from the baseline
  -s, --state-dir DIR     the directory for the snapshots
                          Default: $DEA_STATE_DIR
      --cache-dir DIR     the directory for the answers from crt.sh and the
                          other services. This is NOT under the state
                          directory, therefore "rm -rf state" keeps the cache.
                          Default: $DEA_CACHE_DIR

WHICH CHECKS TO RUN
      --no-http           do not send HTTP requests
      --no-ct             do not query Certificate Transparency (crt.sh)
      --no-archive        do not query the Wayback Machine
      --no-enrich         do not use subfinder, even if it is installed
      --enrich-all        tell subfinder to use every source. Some sources
                          need an API key in the subfinder configuration.
      --harvest           use theHarvester to search for email addresses and
                          hostnames. This sends many requests to search
                          engines, and a search engine can stop them.
      --exif              get the images from the home page. Look for GPS data.
      --wordlist FILE     more possible subdomain names. One name on each line.

OUTPUT
  -o, --report-dir DIR    write one report file for each domain
      --json              write the snapshot JSON to stdout
  -q, --quiet             show no messages. Use this flag with cron. The exit
                          code gives you the result.
      --no-color          do not use colour
      --notify CMD        send a short summary to CMD if the results change

OTHER
      --timeout SEC       the network timeout for each request
                          Default: $DEA_TIMEOUT seconds
      --parallel N        how many DNS queries the tool sends at the same time
                          Default: $DEA_PARALLEL. Use 1 for one query at a time.
  -V, --version
  -h, --help

ENVIRONMENT VARIABLES
  DEA_STATE_DIR       the same as --state-dir
  DEA_CACHE_DIR       the same as --cache-dir
  DEA_REPORT_DIR      the same as --report-dir
  DEA_CONFIG          the same as --config
  DEA_TIMEOUT         the same as --timeout
  DEA_PARALLEL        the same as --parallel
  DEA_CT_CACHE_HOURS  how many hours an answer stays in the cache. Default 168.
  DEA_NOTIFY_CMD      the same as --notify
  DEA_USER_AGENT      the User-Agent header for each request
  DEA_HARVEST_SOURCES the sources for theHarvester
  SHODAN_API_KEY      turns on check 8

The EXIT CODE is a bitmask. One number can show you more than one result.
    0  no results, and no change
    1  the tool found MEDIUM results
    2  the tool found HIGH results
    4  the tool found a change from the baseline
    8  the tool failed. A tool is absent, or the tool cannot write to the
       state directory.
For example, the code 6 shows HIGH results and a change from the baseline.

The tool writes a WARNING and no baseline if a service gave no data during a
run with --baseline. The exit code does not change, because the condition is a
fault of the service and not a result about your domain.

EXAMPLES
  $PROGNAME example.com
  $PROGNAME -c domains.conf --baseline
  $PROGNAME -c domains.conf -q || notify-send "the domain data changed"
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--domain)     DOMAINS+=("$2"); shift 2 ;;
    -c|--config)     DEA_CONFIG="$2"; shift 2 ;;
    -s|--state-dir)  DEA_STATE_DIR="$2"; shift 2 ;;
    -o|--report-dir) DEA_REPORT_DIR="$2"; shift 2 ;;
    --baseline)      SET_BASELINE=1; shift ;;
    --force-baseline) SET_BASELINE=1; FORCE_BASELINE=1; shift ;;
    --cache-dir)     DEA_CACHE_DIR="$2"; shift 2 ;;
    --diff-only)     DIFF_ONLY=1; shift ;;
    --no-http)       DO_HTTP=0; shift ;;
    --no-ct)         DO_CT=0; shift ;;
    --no-archive)    DO_ARCHIVE=0; shift ;;
    --exif)          DO_EXIF=1; shift ;;
    --no-enrich)     DO_ENRICH=0; shift ;;
    --enrich-all)    DO_ENRICH=1; ENRICH_ALL=1; shift ;;
    --harvest)       DO_HARVEST=1; shift ;;
    --wordlist)      WORDLIST="$2"; shift 2 ;;
    --json)          EMIT_JSON=1; shift ;;
    --notify)        DEA_NOTIFY_CMD="$2"; shift 2 ;;
    --timeout)       DEA_TIMEOUT="$2"; shift 2 ;;
    --parallel)      DEA_PARALLEL="$2"; shift 2 ;;
    -q|--quiet)      QUIET=1; COLOR=0; shift ;;
    --no-color)      COLOR=0; shift ;;
    -V|--version)    printf '%s %s\n' "$PROGNAME" "$VERSION"; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; while [ $# -gt 0 ]; do DOMAINS+=("$1"); shift; done ;;
    -*)              die "unknown option: $1 (try --help)" ;;
    *)               DOMAINS+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

need() { command -v "$1" >/dev/null 2>&1; }

MISSING=()
need curl || MISSING+=(curl)
need jq   || MISSING+=(jq)
need dig  || MISSING+=("dig (bind/dnsutils/bind-tools)")
if [ ${#MISSING[@]} -gt 0 ]; then
  printf 'These tools are necessary, but they are absent: %s\n\n' "${MISSING[*]}" >&2
  cat >&2 <<'EOF'
Install them with one of these commands:
  Arch and CachyOS   sudo pacman -S curl jq bind
  Debian and Ubuntu  sudo apt install curl jq dnsutils
  Fedora             sudo dnf install curl jq bind-utils
  Alpine             doas apk add curl jq bind-tools
  macOS              brew install curl jq bind

These two tools are not necessary, but they add more checks:
  whois     Finds the owner of an IP address. The RIRs keep port 43 open.
  exiftool  Finds GPS data in the images on your site.
            On Arch, the package name is perl-image-exiftool.
EOF
  exit 8
fi

HAVE_WHOIS=0;    need whois    && HAVE_WHOIS=1
HAVE_EXIFTOOL=0; need exiftool && HAVE_EXIFTOOL=1

# ---------------------------------------------------------------------------
# Classification library
# ---------------------------------------------------------------------------
# lib/classify.sh holds the decisions of the tool. Two examples: is this field
# redacted, and is this IP address in a data center or in a home? These
# functions use no network, therefore the unit tests can test them.
# See tests/test-classify.sh.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
for libdir in "$SCRIPT_DIR/lib" "$SCRIPT_DIR/../lib/domain-exposure-audit" \
              /usr/local/lib/domain-exposure-audit /usr/lib/domain-exposure-audit; do
  if [ -r "$libdir/classify.sh" ]; then
    # shellcheck source=lib/classify.sh
    . "$libdir/classify.sh"
    LIB_FOUND=1
    break
  fi
done
[ "${LIB_FOUND:-0}" -eq 1 ] || die "lib/classify.sh is absent. The tool looked in $SCRIPT_DIR and in the system directories."

# ---------------------------------------------------------------------------
# Domain list
# ---------------------------------------------------------------------------

if [ ${#DOMAINS[@]} -eq 0 ]; then
  for cand in "$DEA_CONFIG" ./domains.conf \
              "${XDG_CONFIG_HOME:-$HOME/.config}/domain-exposure-audit/domains.conf"; do
    [ -n "$cand" ] && [ -f "$cand" ] || continue
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [ -n "$line" ] && DOMAINS+=("$line")
    done < "$cand"
    say "$(c dim "The tool reads the domains from $cand")"
    break
  done
fi

[ ${#DOMAINS[@]} -gt 0 ] || { usage >&2; die "no domains given"; }

mkdir -p "$DEA_STATE_DIR" 2>/dev/null || die "cannot create state dir: $DEA_STATE_DIR"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dea.XXXXXX")" || die "cannot create temp dir"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

CACHE="$DEA_CACHE_DIR"
mkdir -p "$CACHE" 2>/dev/null || die "cannot create cache dir: $CACHE"

EXIT_MASK=0

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

# fetch URL OUTFILE [accept] -> prints HTTP status, 000 on transport failure
fetch() {
  local url="$1" out="$2" accept="${3:-*/*}"
  curl -sS -L --max-time "$DEA_TIMEOUT" \
       -A "$DEA_USER_AGENT" -H "Accept: $accept" \
       -o "$out" -w '%{http_code}' "$url" 2>/dev/null
  # curl writes the code and also stops with a code that is not 0 when the
  # connection fails. Do not add a second value here. See http_code().
}

# http_code COMMAND... -> the HTTP code, or 000 if there was no answer
# The function gives one value only. An empty answer becomes 000.
http_code() {
  local out
  out="$("$@" 2>/dev/null)"
  case "$out" in
    ""|*[!0-9]*) printf '000' ;;
    *)           printf '%s' "${out: -3}" ;;
  esac
}

# cache_fetch URL OUTFILE MAX_AGE_HOURS [accept]
cache_fetch() {
  local url="$1" out="$2" hours="$3" accept="${4:-*/*}"
  local key; key="$(printf '%s' "$url" | tr -c '[:alnum:]' '_' | cut -c1-120)"
  local cf="$CACHE/$key"
  if [ -f "$cf" ] && [ -n "$(find "$cf" -mmin "-$((hours * 60))" 2>/dev/null)" ]; then
    cp "$cf" "$out"; printf '200(cached)'; return 0
  fi
  local code; code="$(fetch "$url" "$out" "$accept")"
  case "$code" in
    2*) cp "$out" "$cf" ;;
    *)  [ -f "$cf" ] && { cp "$cf" "$out"; code="$code(stale-cache)"; } ;;
  esac
  printf '%s' "$code"
}

dig_short() { dig +short +time=3 +tries=2 "$1" "$2" 2>/dev/null | sed 's/\r$//' | grep -v '^$' | sort -u; }
dig_status() { dig +noall +comment +time=3 +tries=2 "$1" 2>/dev/null | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1; }

json_lines() { # stdin: lines -> JSON array of strings
  jq -R -s 'split("\n") | map(select(length > 0))'
}


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------
# The tool writes one result on each line: severity, code, and message. A tab
# character separates the three fields.
#
# The three severity values are:
#   HIGH    Your location or a secret is public now. Correct this today.
#   MEDIUM  Your position is weaker, or the tool could not get an answer.
#           A person must look at this result.
#   LOW     The result is correct and useful. It is not a problem. Many LOW
#           results are permanent facts that you cannot change.

add_result() {
  local sev="$1" code="$2" msg="$3"
  printf '%s\t%s\t%s\n' "$sev" "$code" "$(printf '%s' "$msg" | tr '\t\n' '  ')" >> "$R_FILE"
}

# ---------------------------------------------------------------------------
# Cloudflare address ranges
# ---------------------------------------------------------------------------

CF4=(); CF6=()
load_cloudflare_ranges() {
  local f4="$WORK/cf4" f6="$WORK/cf6" code
  code="$(cache_fetch 'https://www.cloudflare.com/ips-v4' "$f4" 168)"
  case "$code" in 2*) mapfile -t CF4 < <(grep -E '^[0-9]+\.' "$f4" 2>/dev/null) ;; esac
  code="$(cache_fetch 'https://www.cloudflare.com/ips-v6' "$f6" 168)"
  case "$code" in 2*) mapfile -t CF6 < <(grep -E '^[0-9a-fA-F]*:' "$f6" 2>/dev/null) ;; esac
  if [ ${#CF4[@]} -eq 0 ]; then
    # If the request failed, use the list of ranges that Cloudflare has kept
    # for many years.
    CF4=(173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
         141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
         197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
         104.24.0.0/14 172.64.0.0/13 131.0.72.0/22)
  fi
}

is_cloudflare_ip() {
  local ip="$1" r
  case "$ip" in
    *:*) for r in "${CF6[@]}"; do
           [ "$(v6_prefix "$ip")" = "$(v6_prefix "${r%/*}")" ] && return 0
         done; return 1 ;;
    *)   for r in "${CF4[@]}"; do in_cidr4 "$ip" "$r" && return 0; done; return 1 ;;
  esac
}

# The tool keeps the RIR answer for each address. Many hostnames share one
# address, therefore this prevents a second whois query for the same address.
declare -A IP_DESC_CACHE=()
declare -A IP_RESULT_DONE=()
# The addresses of each network, and the group of each network. The tool writes
# one result for each network, and not one result for each address.
declare -A NET_ADDRS=()
declare -A NET_CLASS=()
declare -A NET_HOST=()
# Each address that the tool saw, so that it counts an address one time only.
declare -A ADDR_SEEN=()

# ip_network_desc IP -> the organization name and the network name from the RIR
ip_network_desc() {
  [ "$HAVE_WHOIS" -eq 1 ] || { printf ''; return; }
  if [ -n "${IP_DESC_CACHE[$1]+x}" ]; then printf '%s' "${IP_DESC_CACHE[$1]}"; return; fi
  local d
  d="$(_ip_network_desc_query "$1")"
  IP_DESC_CACHE[$1]="$d"
  printf '%s' "$d"
}

_ip_network_desc_query() {
  whois "$1" 2>/dev/null \
    | grep -iE '^(orgname|org-name|organization|netname|descr|owner|customer):' \
    | head -3 | cut -d: -f2- | tr -s ' \t' ' ' | sed 's/^ //' \
    | tr '\n' ';' | sed 's/;$//; s/;/; /g' | cut -c1-200
}

# ---------------------------------------------------------------------------
# CHECK 1 – Registration data (RDAP, with port-43 WHOIS as fallback)
# ---------------------------------------------------------------------------

rdap_base_for_tld() {
  local tld="$1" boot="$WORK/rdap-bootstrap.json" code
  code="$(cache_fetch 'https://data.iana.org/rdap/dns.json' "$boot" 168 'application/json')"
  case "$code" in
    2*) jq -r --arg tld "$tld" '
          .services[]? | select((.[0] // []) | index($tld)) | .[1][0] // empty
        ' "$boot" 2>/dev/null | head -1 ;;
    *)  printf '' ;;
  esac
}

# assess_contact SOURCE ROLES KEY VALUE
# The function writes a result if the value holds personal data. SOURCE is the
# name of the service that gave the value, for example RDAP or WHOIS.
#
# The function sets these variables in the caller:
#   AC_PII       1 if the function found personal data
#   AC_REGION    the region, if the value holds one
#   AC_COUNTRY   the country, if the value holds one
assess_contact() {
  local source="$1" roles="$2" key="$3" value="$4"

  case "$roles" in *registrant*|*administrative*|*technical*|*abuse*) ;; *) return 0 ;; esac

  case "$key" in
    adr)
      # The parts of a vCard address are in this order: post office box,
      # extension, street, city, region, postal code, and country.
      local _pobox _ext street city reg_ post country_
      IFS='|' read -r _pobox _ext street city reg_ post country_ <<< "$value"
      [ -n "${reg_:-}" ] && AC_REGION="$reg_"
      [ -n "${country_:-}" ] && AC_COUNTRY="$country_"
      if ! is_redacted "$street"; then
        add_result HIGH PII-STREET "$source shows the street address of the $roles. Any person can read it."
        AC_PII=1
      fi
      if ! is_redacted "$city"; then
        add_result HIGH PII-CITY "$source shows the city of the $roles. Any person can find your city."
        AC_PII=1
      fi
      if ! is_redacted "$post"; then
        add_result HIGH PII-POSTCODE "$source shows the postal code of the $roles. A postal code gives an attacker a small group of streets."
        AC_PII=1
      fi
      ;;
    street)
      if ! is_redacted "$value"; then
        add_result HIGH PII-STREET "$source shows the street address of the $roles. Any person can read it."
        AC_PII=1
      fi
      ;;
    city)
      if ! is_redacted "$value"; then
        add_result HIGH PII-CITY "$source shows the city of the $roles. Any person can find your city."
        AC_PII=1
      fi
      ;;
    postcode)
      if ! is_redacted "$value"; then
        add_result HIGH PII-POSTCODE "$source shows the postal code of the $roles. A postal code gives an attacker a small group of streets."
        AC_PII=1
      fi
      ;;
    region)
      [ -n "$value" ] && AC_REGION="$value"
      ;;
    country)
      [ -n "$value" ] && AC_COUNTRY="$value"
      ;;
    fn|org|name)
      case "$roles" in
        *registrant*)
          if ! is_redacted "$value"; then
            add_result MEDIUM PII-NAME "$source shows the name or the organization of the $roles. This gives your identity, but not your location."
            AC_PII=1
          fi ;;
      esac
      ;;
    email)
      if is_contact_uri "$value"; then
        # The registry publishes the address of a contact form, and no email
        # address of any type. This is the best possible condition.
        AC_FORM=1
      elif is_relay_email "$value"; then
        # The registrar publishes its own relay address. This is the
        # correct condition, therefore the tool writes a LOW result to show
        # that it made the check.
        AC_RELAY=1
      elif ! is_redacted "$value"; then
        add_result MEDIUM PII-EMAIL "$source shows the email address of the $roles. Programs will collect it. You will get false messages about your domain."
        AC_PII=1
      fi
      ;;
    tel|phone)
      # The telephone number of the registrar is normal. It is not your number.
      if ! is_redacted "$value"; then
        add_result LOW RDAP-TEL "$source shows this telephone number for the $roles: $value. Make sure that the number belongs to the registrar and not to you."
      fi
      ;;
  esac
  return 0
}

# check_registration_whois DOMAIN -> read the contact fields from port 43
# The tool uses this function when RDAP has no server for the TLD. Many ccTLDs
# are not in the IANA RDAP list.
check_registration_whois() {
  local domain="$1" w="$WORK/whois-fallback.txt"
  [ "$HAVE_WHOIS" -eq 1 ] || return 1
  timeout "$DEA_TIMEOUT" whois "$domain" > "$w" 2>/dev/null || true
  [ -s "$w" ] || return 1
  grep -qiE 'registrar|registrant|creation date|registry domain id|domain name' "$w" || return 1

  local line label value roles key
  while IFS= read -r line; do
    label="$(printf '%s' "$line" | cut -d: -f1 | tr '[:upper:]' '[:lower:]' | tr -s ' ' ' ')"
    value="$(printf '%s' "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$value" ] || continue

    case "$label" in
      *registrant*)     roles="registrant" ;;
      *admin*)          roles="administrative" ;;
      *tech*)           roles="technical" ;;
      *)                continue ;;
    esac
    case "$label" in
      *street*|*address*)             key="street" ;;
      *city*)                         key="city" ;;
      *postal*|*post\ code*|*zip*)    key="postcode" ;;
      *state*|*province*)             key="region" ;;
      *country*)                      key="country" ;;
      *email*|*e-mail*)               key="email" ;;
      *phone*|*tel*|*fax*)            key="phone" ;;
      *name*|*organi*)                key="name" ;;
      *)                              continue ;;
    esac
    assess_contact WHOIS "$roles" "$key" "$value"
  done < "$w"
  return 0
}

check_registration() {
  local domain="$1"
  local tld="${domain##*.}"
  local reg="$WORK/rdap-registry.json" rar="$WORK/rdap-registrar.json"
  local base url code

  head1 "1. Registration data (RDAP)"

  base="$(rdap_base_for_tld "$tld")"
  if [ -n "$base" ]; then
    url="${base%/}/domain/$domain"
  else
    url="https://rdap.org/domain/$domain"
    say "$(c dim "  The IANA list is not available. The tool uses rdap.org.")"
  fi

  code="$(fetch "$url" "$reg" 'application/rdap+json')"
  say "  registry RDAP  $url  -> $code"

  AC_PII=0; AC_RELAY=0; AC_FORM=0; AC_REGION=""; AC_COUNTRY=""

  # The tool reads the HTTP code first. An RDAP server that does not hold a TLD
  # answers 404, and the body of that answer is often not JSON. Therefore a test
  # for valid JSON must come after this step.
  case "$code" in
    404)
      # A 404 has two possible meanings. The domain has no registration, or the
      # RDAP server does not hold this TLD. The tool asks WHOIS on port 43.
      if check_registration_whois "$domain"; then
        add_result LOW RDAP-NO-SERVER "RDAP has no server for .$tld. WHOIS on port 43 answers, therefore the domain has a registration. The tool read the contact fields from WHOIS, therefore this check is complete."
        say "  RDAP has no server for .$tld. The tool reads WHOIS on port 43."
        [ "$AC_RELAY" -eq 1 ] && add_result LOW RELAY-EMAIL "The registration record holds a relay address from your registrar, and not your own address. A message to that address goes to you. This is the correct condition."
        [ "$AC_FORM" -eq 1 ] && add_result LOW CONTACT-FORM "The registration record holds the address of a contact form, and no email address. A person can send you a message through that form. This is the best possible condition."
        if [ "$AC_PII" -eq 0 ]; then
          add_result LOW WHOIS-REDACTED "WHOIS on port 43 shows no personal data in the contact fields."
        fi
        [ -n "$AC_REGION" ] && ! is_redacted "$AC_REGION" && \
          add_result LOW RDAP-REGION "WHOIS shows this region: $AC_REGION. ICANN rules make this necessary. No registrar can hide it."
        [ -n "$AC_COUNTRY" ] && ! is_redacted "$AC_COUNTRY" && \
          add_result LOW RDAP-COUNTRY "WHOIS shows this country: $AC_COUNTRY. ICANN rules make this necessary."
        jq -n --argjson pii "$AC_PII" --arg region "$AC_REGION" --arg country "$AC_COUNTRY" \
          '{registered: true, source: "whois", statuses: [], expires: "",
            region: $region, country: $country, registrar_rdap: "",
            pii_published: ($pii == 1)}' > "$WORK/registration.json"
      else
        add_result LOW RDAP-NOTFOUND "The registry says that this domain has no registration."
        printf '{"registered":false}' > "$WORK/registration.json"
      fi
      return ;;
    *)   : ;;
  esac

  # A failure gives one result only. If the body is not JSON, the tool writes
  # RDAP-UNREADABLE. If the body is JSON but the code is not 2xx, the tool
  # writes RDAP-HTTP.
  if ! jq -e . "$reg" >/dev/null 2>&1; then
    add_result MEDIUM RDAP-UNREADABLE "The registry RDAP server gave no valid JSON. The HTTP code was $code. This run did not check your registration data."
    printf '{}' > "$WORK/registration.json"
    return
  fi
  case "$code" in
    2*) : ;;
    *)  add_result MEDIUM RDAP-HTTP "The registry RDAP server gave the HTTP code $code. The registration data from this run is not reliable." ;;
  esac

  # The registrar RDAP server holds the contact records. The registry holds
  # almost no data. The tool follows the related link to get the correct answer.
  local rar_url
  rar_url="$(jq -r '(.links // [])[] | select(.rel == "related") | .href // empty' "$reg" 2>/dev/null | head -1)"
  local have_rar=0
  if [ -n "$rar_url" ]; then
    local rcode; rcode="$(fetch "$rar_url" "$rar" 'application/rdap+json')"
    say "  registrar RDAP $rar_url -> $rcode"
    if jq -e . "$rar" >/dev/null 2>&1; then have_rar=1; else
      add_result MEDIUM RDAP-REGISTRAR "The registrar RDAP server at $rar_url gave no valid JSON. The HTTP code was $rcode."
    fi
  else
    add_result LOW RDAP-NO-RELATED "The registry RDAP data has no link to the registrar. The tool cannot check your contact data at the registrar."
  fi

  local src="$reg"; [ "$have_rar" -eq 1 ] && src="$rar"

  # --- contact fields ---
  # The output holds the role, the key, and the value. A tab character
  # separates them. A vertical bar separates the parts of an address.
  jq -r '
    (.entities // [])[]
    | ((.roles // ["unknown"]) | join(",")) as $roles
    | ((.vcardArray[1]) // [])[]
    | select(type == "array")
    | [ $roles,
        (.[0] | tostring),
        (.[3] // "" | if type == "array" then map(tostring) | join("|") else tostring end)
      ] | @tsv
  ' "$src" 2>/dev/null > "$WORK/vcards.tsv"

  local registrant_seen=0
  while IFS=$'\t' read -r roles key value; do
    case "$roles" in *registrant*) registrant_seen=1 ;; esac
    assess_contact RDAP "$roles" "$key" "$value"
  done < "$WORK/vcards.tsv"

  if [ "$registrant_seen" -eq 0 ]; then
    add_result LOW RDAP-NO-REGISTRANT "RDAP shows no registrant record. This is the best possible result."
  elif [ "$AC_PII" -eq 0 ]; then
    add_result LOW RDAP-REDACTED "RDAP shows a registrant record. All the personal fields hold redacted data."
  fi

  [ "$AC_RELAY" -eq 1 ] && add_result LOW RELAY-EMAIL "The registration record holds a relay address from your registrar, and not your own address. A message to that address goes to you. This is the correct condition."
  [ "$AC_FORM" -eq 1 ] && add_result LOW CONTACT-FORM "The registration record holds the address of a contact form, and no email address. A person can send you a message through that form. This is the best possible condition."
  [ -n "$AC_REGION" ] && ! is_redacted "$AC_REGION" && \
    add_result LOW RDAP-REGION "RDAP shows this region: $AC_REGION. ICANN rules make this necessary. No registrar can hide it."
  [ -n "$AC_COUNTRY" ] && ! is_redacted "$AC_COUNTRY" && \
    add_result LOW RDAP-COUNTRY "RDAP shows this country: $AC_COUNTRY. ICANN rules make this necessary."
  local pii_found="$AC_PII" region="$AC_REGION" country="$AC_COUNTRY"

  # --- lock status and expiry ---
  local statuses statuses_flat expiry
  statuses="$(jq -r '(.status // [])[]' "$src" 2>/dev/null | sort -u | paste -sd, -)"
  say "  status: ${statuses:-the registry publishes no status}"

  # RFC 9083 writes a status in lowercase with spaces, for example
  # "client transfer prohibited". The EPP name for the same status is
  # "clientTransferProhibited". The tool removes the spaces and makes the text
  # lowercase, therefore it can compare the two forms.
  statuses_flat="$(printf '%s' "$statuses" | tr -d ' _-' | lc)"
  case "$statuses_flat" in
    *clienttransferprohibited*|*servertransferprohibited*) : ;;
    *) add_result MEDIUM NO-TRANSFER-LOCK "The status clientTransferProhibited is absent. A person can move your domain to another registrar more easily." ;;
  esac
  case "$statuses_flat" in
    *clientupdateprohibited*|*serverupdateprohibited*) : ;;
    *) add_result LOW NO-UPDATE-LOCK "The status clientUpdateProhibited is absent. A person can change your contact data without a second step." ;;
  esac

  expiry="$(jq -r '(.events // [])[] | select(.eventAction == "expiration") | .eventDate // empty' "$src" 2>/dev/null | head -1)"
  if [ -n "$expiry" ]; then
    say "  expires: $expiry"
    local now_s exp_s days
    now_s="$(date -u +%s)"
    exp_s="$(date -u -d "$expiry" +%s 2>/dev/null || printf '')"
    if [ -n "$exp_s" ]; then
      days=$(( (exp_s - now_s) / 86400 ))
      [ "$days" -lt 45 ] && add_result MEDIUM EXPIRY-SOON "The registration stops in $days days. If it stops, any person can register the domain and use your name."
      [ "$days" -lt 0 ]  && add_result HIGH EXPIRED "The registration stopped $(( -days )) days before today. Renew it now."
    fi
  fi

  # Most gTLD registries stopped the WHOIS service on port 43 in 2025. The tool
  # queries it one time only, to record if the service answers. If the service
  # answers, it sometimes shows fields that RDAP hides.
  if [ "$HAVE_WHOIS" -eq 1 ]; then
    local w="$WORK/whois.txt"
    timeout "$DEA_TIMEOUT" whois "$domain" > "$w" 2>/dev/null
    if grep -qiE 'tld is not supported|no whois server|not supported' "$w" 2>/dev/null; then
      say "  WHOIS on port 43: stopped for .$tld. This is correct after January 2025."
    elif grep -qiE 'registrant|registry domain id' "$w" 2>/dev/null; then
      say "  WHOIS on port 43: the service answers"
      local w43_field w43_value w43_pii=0
      while IFS= read -r w43_field; do
        w43_value="$(printf '%s' "$w43_field" | cut -d: -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        is_redacted "$w43_value" || w43_pii=1
      done < <(grep -iE '^[[:space:]]*(registrant|admin|tech)[[:space:]]*(street|city|postal ?code|state|province)' "$w" 2>/dev/null)
      if [ "$w43_pii" -eq 1 ]; then
        add_result HIGH WHOIS43-PII "The old WHOIS service on port 43 shows address fields, but RDAP hides them. The two services do not agree."
      fi
    fi
  fi

  jq -n \
    --argjson statuses "$(printf '%s' "$statuses" | tr ',' '\n' | json_lines)" \
    --arg expiry "$expiry" \
    --arg region "$region" \
    --arg country "$country" \
    --arg registrar_rdap "$rar_url" \
    --argjson pii "$pii_found" \
    '{registered: true, statuses: $statuses, expires: $expiry,
      region: $region, country: $country,
      registrar_rdap: $registrar_rdap, pii_published: ($pii == 1)}' \
    > "$WORK/registration.json"
}

# ---------------------------------------------------------------------------
# CHECK 2 – DNS posture
# ---------------------------------------------------------------------------

check_dns() {
  local domain="$1"
  head1 "2. DNS records"

  local ns soa a aaaa mx txt caa ds spf dmarc
  ns="$(dig_short NS "$domain")"
  soa="$(dig_short SOA "$domain")"
  a="$(dig_short A "$domain" | grep -E '^[0-9]+\.' || true)"
  aaaa="$(dig_short AAAA "$domain" | grep -E '^[0-9a-fA-F]*:[0-9a-fA-F:]*$' || true)"
  mx="$(dig_short MX "$domain")"
  txt="$(dig_short TXT "$domain")"
  caa="$(dig_short CAA "$domain")"
  ds="$(dig_short DS "$domain")"
  dmarc="$(dig_short TXT "_dmarc.$domain")"

  local t
  for t in NS SOA A AAAA MX TXT CAA DS; do
    local var
    case "$t" in
      NS) var="$ns" ;; SOA) var="$soa" ;; A) var="$a" ;; AAAA) var="$aaaa" ;;
      MX) var="$mx" ;; TXT) var="$txt" ;; CAA) var="$caa" ;; DS) var="$ds" ;;
    esac
    printf '  %-5s %s\n' "$t" "$(printf '%s' "$var" | paste -sd' ' - | cut -c1-160)"
  done
  [ -n "$dmarc" ] && printf '  %-5s %s\n' DMARC "$(printf '%s' "$dmarc" | cut -c1-160)"

  [ -z "$ns" ] && add_result MEDIUM DNS-NO-NS "The domain has no NS records. The zone has a fault, or the domain has no registration."

  # The second field of the SOA record is an email address. The first dot in
  # the field takes the place of the @ character. It is often a real mailbox.
  if [ -n "$soa" ]; then
    local rname; rname="$(printf '%s' "$soa" | awk '{print $2}' | sed 's/\.$//')"
    # 1.3.0: lib/classify.sh holds the list of providers, therefore a test can
    # test it. The list now holds Gandi. The tool gives a result in each case,
    # because a person must know that the tool made this decision.
    if [ -z "$rname" ]; then
      :
    elif is_provider_soa_contact "$rname"; then
      add_result LOW SOA-PROVIDER "The SOA record holds this contact: $rname. The address belongs to your DNS provider or your registrar, therefore it is not your own mailbox. This is the correct condition."
    else
      add_result LOW SOA-RNAME "The SOA record holds this contact: $rname. The tool does not recognise the address of a DNS provider. If this is your personal mailbox, all persons who query your zone can read it."
    fi
  fi

  spf="$(printf '%s' "$txt" | grep -i 'v=spf1' | head -1 || true)"
  if [ -z "$spf" ]; then
    add_result MEDIUM NO-SPF "The domain has no SPF record. Any person can send mail that shows your domain as the sender."
  elif printf '%s' "$spf" | grep -qE '[~?]all'; then
    add_result LOW SPF-SOFT "The SPF record ends with a soft fail. Use -all if no other host sends mail for this domain."
  fi

  if [ -z "$dmarc" ]; then
    add_result MEDIUM NO-DMARC "The domain has no DMARC record at _dmarc.$domain. You have no rule for false mail that shows your domain."
  else
    case "$dmarc" in
      *p=reject*) : ;;
      *p=quarantine*) add_result LOW DMARC-QUARANTINE "The DMARC policy is quarantine. The policy reject is stronger." ;;
      *p=none*) add_result MEDIUM DMARC-NONE "The DMARC policy is p=none. This policy only makes reports. It stops no mail." ;;
    esac
  fi

  [ -z "$caa" ] && add_result MEDIUM NO-CAA "The domain has no CAA record. Any certificate authority can make certificates for this domain."
  [ -z "$ds" ]  && add_result LOW NO-DNSSEC "The parent zone has no DS record. Therefore DNSSEC does not protect your DNS answers."

  # The tool asks your nameservers for a zone transfer. A public zone transfer
  # gives all your records to any person. This includes the internal names that
  # have no certificate in a public log.
  local nsx axfr_open=0
  while IFS= read -r nsx; do
    [ -n "$nsx" ] || continue
    if dig +time=4 +tries=1 AXFR "$domain" "@${nsx%.}" 2>/dev/null | grep -qE "^${domain}\.[[:space:]]+[0-9]+[[:space:]]+IN[[:space:]]+SOA"; then
      add_result HIGH AXFR-OPEN "The nameserver ${nsx%.} permits a zone transfer to any person. Therefore any person can copy all your DNS records."
      axfr_open=1
    fi
  done <<< "$ns"
  [ "$axfr_open" -eq 0 ] && [ -n "$ns" ] && say "  Zone transfer: all nameservers refuse. This is correct."

  jq -n \
    --argjson ns "$(printf '%s' "$ns" | json_lines)" \
    --argjson a "$(printf '%s' "$a" | json_lines)" \
    --argjson aaaa "$(printf '%s' "$aaaa" | json_lines)" \
    --argjson mx "$(printf '%s' "$mx" | json_lines)" \
    --argjson txt "$(printf '%s' "$txt" | json_lines)" \
    --argjson caa "$(printf '%s' "$caa" | json_lines)" \
    --argjson ds "$(printf '%s' "$ds" | json_lines)" \
    --arg soa "$soa" --arg spf "$spf" --arg dmarc "$dmarc" \
    --argjson axfr "$axfr_open" \
    '{ns: $ns, soa: $soa, a: $a, aaaa: $aaaa, mx: $mx, txt: $txt,
      caa: $caa, ds: $ds, spf: $spf, dmarc: $dmarc, axfr_open: ($axfr == 1)}' \
    > "$WORK/dns.json"
}

# ---------------------------------------------------------------------------
# CHECK 3 – Certificate Transparency
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Enrichment: more hostnames from other programs
# ---------------------------------------------------------------------------
# Certificate Transparency is the best source of hostnames, but it is one
# service. A run on three domains showed that crt.sh gave no answer three times
# out of three. Therefore the tool can also use subfinder, which reads about 30
# passive sources.
#
# Each program here is passive. It sends no traffic to your hosts. The tool does
# not do an active scan. See docs/CHECKS.md, Check 10.

# enrich_subfinder DOMAIN -> write hostnames to stdout
enrich_subfinder() {
  local domain="$1"
  # -silent gives the names only. The tool does not use -all, because -all uses
  # the sources that need an API key.
  # -disable-update-check stops one request to the servers of the program.
  timeout "$(( DEA_TIMEOUT * 6 ))" subfinder -d "$domain" -silent \
    -timeout 10 -disable-update-check ${ENRICH_ALL:+-all} 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/\.$//' \
    | grep -E "^[a-z0-9._-]+\.${domain//./\\.}$" \
    | sort -u
}

# enrich_harvester DOMAIN -> write hostnames to stdout, and write results for
# each email address that it finds.
enrich_harvester() {
  local domain="$1" base="$WORK/harvest"
  # Remove the file from an earlier domain. theHarvester writes the file itself,
  # therefore the tool must remove it. Without this step, the data of one domain
  # becomes a result for the next domain.
  rm -f "$base" "$base".* 2>/dev/null || true
  # theHarvester writes the file <base>.json. The name of each key changed
  # between versions, therefore the tool reads more than one name.
  timeout "$(( DEA_TIMEOUT * 12 ))" theHarvester \
    -d "$domain" -b "$DEA_HARVEST_SOURCES" -f "$base" >/dev/null 2>&1 || true

  local jf=""
  for cand in "$base.json" "${base}.json" "$base"; do
    [ -f "$cand" ] && jq -e . "$cand" >/dev/null 2>&1 && { jf="$cand"; break; }
  done
  [ -n "$jf" ] || return 1

  # Email addresses. This is the reason to use this program.
  local mail
  while IFS= read -r mail; do
    [ -n "$mail" ] || continue
    add_result MEDIUM HARVEST-EMAIL "A public search found this email address for your domain: $mail. Programs collect an address from a search engine, therefore you will get false messages."
  done < <(jq -r '((.emails // .email // []) | if type == "array" then .[] else . end) // empty' "$jf" 2>/dev/null | sort -u | head -25)

  jq -r '((.hosts // .host // []) | if type == "array" then .[] else . end) // empty' "$jf" 2>/dev/null \
    | cut -d: -f1 | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/\.$//' \
    | grep -E "^[a-z0-9._-]+\.${domain//./\\.}$" \
    | sort -u
  return 0
}

# check_enrich DOMAIN -> write the extra hostnames to $WORK/enrich-names.txt
check_enrich() {
  local domain="$1"
  : > "$WORK/enrich-names.txt"
  : > "$WORK/enrich-sources.txt"

  if [ "$DO_ENRICH" -eq 0 ] && [ "$DO_HARVEST" -eq 0 ]; then
    printf '{"used":[],"names":0}' > "$WORK/enrich.json"
    return
  fi

  # Is any program available?
  local have_any=0
  [ "$DO_ENRICH" -eq 1 ] && need subfinder && have_any=1
  [ "$DO_HARVEST" -eq 1 ] && need theHarvester && have_any=1
  if [ "$have_any" -eq 0 ]; then
    # This is a message and not a result. It describes the programs on your
    # computer, and not the public data about your domain. A result would make a
    # change in the list of results each time you install or remove a program.
    say "$(c dim "  No program for more hostnames is installed. Install subfinder to make Check 4 more reliable.")"
    printf '{"used":[],"names":0}' > "$WORK/enrich.json"
    return
  fi

  head1 "3b. More hostnames from other programs"

  if [ "$DO_ENRICH" -eq 1 ]; then
    if need subfinder; then
      local n
      enrich_subfinder "$domain" >> "$WORK/enrich-names.txt"
      n="$(sort -u "$WORK/enrich-names.txt" | grep -c . || true)"
      say "  subfinder found $n name(s)"
      printf 'subfinder\n' >> "$WORK/enrich-sources.txt"
    fi
  fi

  if [ "$DO_HARVEST" -eq 1 ]; then
    if need theHarvester; then
      local before after
      before="$(grep -c . "$WORK/enrich-names.txt" || true)"
      if enrich_harvester "$domain" >> "$WORK/enrich-names.txt"; then
        after="$(grep -c . "$WORK/enrich-names.txt" || true)"
        say "  theHarvester added $(( after - before )) name(s)"
        printf 'theHarvester\n' >> "$WORK/enrich-sources.txt"
      else
        say "  theHarvester gave no data that the tool can read."
        add_result LOW HARVEST-UNREADABLE "theHarvester gave no JSON file that the tool can read. A search engine possibly stopped the requests. This is not a result about your domain."
      fi
    fi
  fi

  sort -u "$WORK/enrich-names.txt" -o "$WORK/enrich-names.txt"
  local total; total="$(grep -c . "$WORK/enrich-names.txt" || true)"

  # Which names did the other programs find that Certificate Transparency did
  # not? This is the value that the enrichment adds.
  # The tool names each hostname in the result. A name that does not point to
  # an address is absent from Check 4, therefore a result with a number only
  # hides the names that tell an attacker which software you use.
  if [ "$total" -gt 0 ]; then
    local only_list only_n advice
    if [ -s "$WORK/ct-plain.txt" ]; then
      only_list="$(LC_ALL=C comm -23 <(LC_ALL=C sort -u "$WORK/enrich-names.txt") \
                                     <(LC_ALL=C sort -u "$WORK/ct-plain.txt") 2>/dev/null || true)"
    else
      only_list="$(cat "$WORK/enrich-names.txt")"
    fi
    # The apex name and the name www are public by design. They tell an attacker
    # nothing, therefore the tool removes them from the result.
    only_list="$(printf '%s\n' "$only_list" | grep -v '^$' \
                 | grep -vxF "$domain" | grep -vxF "www.$domain" || true)"
    only_n="$(printf '%s' "$only_list" | grep -c . || true)"
    if [ "$only_n" -gt 0 ]; then
      if printf '%s\n' "$only_list" | any_reveals_software; then
        advice="One name or more names a program that you use. That tells an attacker which faults to try, and which login page to copy."
      else
        advice="No name in this list gives the name of a program. Therefore the names give an attacker very little."
      fi
      add_result LOW ENRICH-HOSTNAMES "The other programs found $only_n hostname(s) that Certificate Transparency does not hold: $(printf '%s' "$only_list" | tr '\n' ' ' | sed 's/ $//' | cut -c1-300). $advice A name is in this list even if it points to no address."
      say "  $only_n of them are not in Certificate Transparency:"
      local nm
      while IFS= read -r nm; do [ -n "$nm" ] && say "    $nm"; done <<< "$only_list"
    # 1.3.0: Say the true reason for a count of zero. When Certificate
    # Transparency gave no data, the tool holds no list to compare against, and
    # "already in Certificate Transparency" is then false.
    elif [ ! -s "$WORK/ct-plain.txt" ]; then
      say "  Certificate Transparency gave no name, therefore the tool cannot compare the two lists."
    else
      say "  Each name is already in Certificate Transparency."
    fi
  fi

  jq -n --argjson names "$total" \
    --argjson used "$(cat "$WORK/enrich-sources.txt" | json_lines)" \
    '{used: $used, names: $names}' > "$WORK/enrich.json"
}

check_ct() {
  local domain="$1"
  head1 "3. Certificate Transparency (crt.sh)"

  if [ "$DO_CT" -eq 0 ]; then
    say "  The tool did not run this check. You used --no-ct."
    printf '{"skipped":true,"names":[],"wildcards":[]}' > "$WORK/ct.json"
    return
  fi

  local out="$WORK/ct.json.raw" code attempt=0 ct_source=""
  : > "$WORK/ct-names.txt"

  # Try crt.sh three times. It often limits requests, and it answers 502 or 503
  # when it has too much work.
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    code="$(cache_fetch "https://crt.sh/?q=%25.${domain}&output=json" "$out" "$DEA_CT_CACHE_HOURS" 'application/json')"
    say "  crt.sh try number $attempt -> $code"
    if jq -e 'type == "array"' "$out" >/dev/null 2>&1; then
      ct_source="crt.sh"
      jq -r '.[].name_value' "$out" 2>/dev/null | tr ',' '\n' | lc \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u > "$WORK/ct-names.txt"
      break
    fi
    # 1.3.0: A longer delay. 502 and 503 mean that crt.sh has too much work,
    # and three seconds is not enough time for the load to fall. The delays are
    # 5 seconds and then 15 seconds, therefore a run costs at most 20 seconds
    # more than version 1.2.1. The values are explicit, because an arithmetic
    # form gave 5 and 20, and the documents said 5 and 15.
    case "$attempt" in
      1) sleep 5 ;;
      2) sleep 15 ;;
    esac
  done

  # The second service. SSLMate CertSpotter reads the same public logs. It needs
  # no key for a small number of requests each hour.
  local cscode="not queried" cs_reason=""
  if [ -z "$ct_source" ]; then
    local cs="$WORK/certspotter.json"
    cscode="$(cache_fetch "https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names&expand=issuer" \
              "$cs" "$DEA_CT_CACHE_HOURS" 'application/json')"
    say "  certspotter -> $cscode"
    # An empty list is not an answer. The service gives an empty list when it
    # holds no current certificate, and a domain almost always has one. The tool
    # must not accept an empty list, because a stale answer from the cache of
    # crt.sh is better.
    if jq -e 'type == "array" and length > 0' "$cs" >/dev/null 2>&1; then
      ct_source="certspotter"
      jq -r '.[].dns_names[]?' "$cs" 2>/dev/null | lc \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u > "$WORK/ct-names.txt"
      cp "$cs" "$out"
    # 1.3.0: Say which of the two conditions happened. An empty list and a
    # broken answer need different actions from you. A later run repairs a
    # broken answer. A later run does not repair an empty list.
    elif jq -e 'type == "array" and length == 0' "$cs" >/dev/null 2>&1; then
      cs_reason="certspotter answered, and the answer holds no certificate. That service shows only a certificate that is valid now. A later run gives the same answer."
    elif jq -e 'type == "object"' "$cs" >/dev/null 2>&1; then
      cs_reason="certspotter answered with a message and not with a list. The service possibly limits the number of requests. Run the tool again later."
    else
      cs_reason="certspotter gave no valid JSON."
    fi
  fi

  if [ -z "$ct_source" ]; then
    # 1.3.0: Name the HTTP code of each service. Version 1.2.1 showed the code
    # from crt.sh only. A person then read "502" when certspotter had in fact
    # answered 200 with a list that holds no certificate.
    add_result MEDIUM CT-UNAVAILABLE "Certificate Transparency gave no usable data. crt.sh answered $code after 3 tries. certspotter answered $cscode. ${cs_reason:+$cs_reason }Check 3 found no name, and check 4 used the word list only, therefore it possibly missed some hostnames."
    printf '{"error":true,"names":[],"wildcards":[]}' > "$WORK/ct.json"
    return
  fi
  say "  the tool used $ct_source"
  if [ "$ct_source" != "crt.sh" ]; then
    add_result LOW CT-SECOND-SOURCE "crt.sh gave no data, therefore the tool used $ct_source. That service shows the certificates that are valid now. It does not show each certificate from the past. The list of names is possibly shorter than the true list."
  fi

  local total wild plain
  total="$(wc -l < "$WORK/ct-names.txt" | tr -d ' ')"
  grep '^\*\.' "$WORK/ct-names.txt" > "$WORK/ct-wild.txt" 2>/dev/null || : > "$WORK/ct-wild.txt"
  grep -v '^\*\.' "$WORK/ct-names.txt" > "$WORK/ct-plain.txt" 2>/dev/null || : > "$WORK/ct-plain.txt"
  wild="$(wc -l < "$WORK/ct-wild.txt" | tr -d ' ')"
  plain="$(wc -l < "$WORK/ct-plain.txt" | tr -d ' ')"

  say "  The logs hold $total names. $wild are wildcard names and $plain are single names."
  local n
  while IFS= read -r n; do say "    $n"; done < <(head -40 "$WORK/ct-names.txt")
  [ "$total" -gt 40 ] && say "    and $(( total - 40 )) more names"

  # A certificate for one host makes that hostname public for all time.
  local revealing
  revealing="$(grep -vxF "$domain" "$WORK/ct-plain.txt" 2>/dev/null | grep -vx "www.$domain" || true)"
  if [ -n "$revealing" ]; then
    local count advice; count="$(printf '%s' "$revealing" | grep -c . || true)"
    if printf '%s\n' "$revealing" | any_reveals_software; then
      advice="One name or more names a program that you use. That tells an attacker which faults to try, and which login page to copy."
    else
      advice="No name in this list gives the name of a program. Therefore the names give an attacker very little."
    fi
    add_result LOW CT-HOSTNAMES "Certificate Transparency holds a permanent record of $count hostname(s): $(printf '%s' "$revealing" | tr '\n' ' ' | sed 's/ $//' | cut -c1-300). $advice"
  fi
  [ "$wild" -gt 0 ] && [ "$plain" -gt 2 ] && \
    add_result LOW CT-MIXED "You have a wildcard certificate, but you also make a certificate for each host. Use only the wildcard certificate. Then no new hostname goes into a public log."

  local issuers latest
  if [ "$ct_source" = "crt.sh" ]; then
    issuers="$(jq -r '.[].issuer_name // empty' "$out" 2>/dev/null | sed 's/.*O=\([^,]*\).*/\1/' | sort -u | tr '\n' ';' | sed 's/;$//; s/;/; /g' | cut -c1-200)"
    latest="$(jq -r '.[].not_after // empty' "$out" 2>/dev/null | sort -r | head -1)"
  else
    issuers="$(jq -r '.[].issuer.name // empty' "$out" 2>/dev/null | sed 's/.*O=\([^,]*\).*/\1/' | sort -u | tr '\n' ';' | sed 's/;$//; s/;/; /g' | cut -c1-200)"
    latest="$(jq -r '.[].not_after // empty' "$out" 2>/dev/null | sort -r | head -1)"
  fi
  [ -n "$issuers" ] && say "  issuers: $issuers"

  jq -n \
    --argjson names "$(cat "$WORK/ct-names.txt" | json_lines)" \
    --argjson wildcards "$(cat "$WORK/ct-wild.txt" | json_lines)" \
    --arg issuers "$issuers" --arg latest "$latest" --arg source "$ct_source" \
    '{names: $names, wildcards: $wildcards, issuers: $issuers,
      latest_not_after: $latest, source: $source}' \
    > "$WORK/ct.json"
}

# ---------------------------------------------------------------------------
# CHECK 4 – Hostname resolution and origin classification
# ---------------------------------------------------------------------------

check_hosts() {
  local domain="$1"
  head1 "4. Hostnames and their addresses"

  : > "$WORK/candidates.txt"
  printf '%s\n' "$domain" >> "$WORK/candidates.txt"
  # The names from Certificate Transparency are real. The word list only adds
  # possible names.
  if [ -s "$WORK/ct-plain.txt" ]; then
    grep -E "(^|\.)${domain//./\\.}$" "$WORK/ct-plain.txt" >> "$WORK/candidates.txt" 2>/dev/null || true
  fi
  # The names from the other programs are real names, the same as the names
  # from Certificate Transparency.
  if [ -s "$WORK/enrich-names.txt" ]; then
    cat "$WORK/enrich-names.txt" >> "$WORK/candidates.txt"
  fi
  local w
  for w in "${DEFAULT_WORDS[@]}"; do printf '%s.%s\n' "$w" "$domain" >> "$WORK/candidates.txt"; done
  if [ -n "$WORDLIST" ] && [ -f "$WORDLIST" ]; then
    while IFS= read -r w; do
      w="${w%%#*}"; w="$(printf '%s' "$w" | tr -d '[:space:]')"
      [ -n "$w" ] && printf '%s.%s\n' "$w" "$domain" >> "$WORK/candidates.txt"
    done < "$WORDLIST"
  fi
  sort -u "$WORK/candidates.txt" | grep -v '^\*' > "$WORK/candidates.uniq"
  local ncand; ncand="$(wc -l < "$WORK/candidates.uniq" | tr -d ' ')"
  say "  The tool queries $ncand possible names. The names come from the logs, the other programs, and the word list."

  # The helper resolves one name. xargs starts many copies of it at the same
  # time. Each copy writes one line, and the line is short. Therefore the writes
  # do not mix with each other.
  cat > "$WORK/resolve1.sh" <<'RESOLVER'
#!/usr/bin/env bash
# resolve1.sh HOST OUTFILE
# The output holds the hostname, the DNS status, the A records, and the AAAA
# records. A tab character separates the four fields. A comma separates the
# addresses in one field.
host="$1"; out="$2"
a_out="$(dig +noall +comment +answer +time=3 +tries=2 A "$host" 2>/dev/null)"
status="$(printf '%s' "$a_out" | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1)"
a="$(printf '%s' "$a_out" | awk '$4 == "A" { print $5 }' | sort -u | paste -sd, -)"
aaaa="$(dig +short +time=3 +tries=2 AAAA "$host" 2>/dev/null | grep -E '^[0-9a-fA-F]*:[0-9a-fA-F:]*$' | sort -u | paste -sd, -)"
printf '%s\t%s\t%s\t%s\n' "$host" "${status:-NOANSWER}" "$a" "$aaaa" >> "$out"
RESOLVER
  chmod +x "$WORK/resolve1.sh"

  : > "$WORK/resolved.raw"
  xargs -a "$WORK/candidates.uniq" -P "$DEA_PARALLEL" -I{} \
    bash "$WORK/resolve1.sh" {} "$WORK/resolved.raw" 2>/dev/null || true
  sort "$WORK/resolved.raw" > "$WORK/resolved.tsv"

  : > "$WORK/hosts.ndjson"
  : > "$WORK/live-hosts.txt"
  local host status a_csv aaaa_csv ips ip6s allips ip desc cls cf_count=0 origin_count=0

  while IFS=$'\t' read -r host status a_csv aaaa_csv; do
    [ -n "$host" ] || continue
    ips="$(printf '%s' "$a_csv" | tr ',' '\n' | grep -E '^[0-9]+\.' || true)"
    ip6s="$(printf '%s' "$aaaa_csv" | tr ',' '\n' | grep -E '^[0-9a-fA-F]*:[0-9a-fA-F:]*$' || true)"
    allips="$(printf '%s\n%s' "$ips" "$ip6s" | grep -v '^$' || true)"

    if [ -z "$allips" ]; then
      # A CT name with the answer NXDOMAIN is a good result. The certificate
      # is present, but no person can reach the host from the internet.
      if [ "$status" = "NXDOMAIN" ] && grep -qxF "$host" "$WORK/ct-plain.txt" 2>/dev/null && [ "$host" != "$domain" ]; then
        say "    $(c green '·') $host  NXDOMAIN. A certificate is present, but the name is not in public DNS."
      fi
      continue
    fi

    printf '%s\n' "$host" >> "$WORK/live-hosts.txt"
    local host_cls="cloudflare" networks=""
    while IFS= read -r ip; do
      [ -n "$ip" ] || continue
      if is_cloudflare_ip "$ip"; then
        if [ -z "${ADDR_SEEN[$ip]:-}" ]; then
          cf_count=$((cf_count + 1)); ADDR_SEEN[$ip]=1
        fi
        say "    $(c green '·') $host -> $ip $(c dim '[cloudflare proxy]')"
      else
        desc="$(ip_network_desc "$ip")"
        cls="$(classify_network "$desc")"
        networks="$networks${networks:+; }$desc"
        [ -z "${ADDR_SEEN[$ip]:-}" ] && { origin_count=$((origin_count + 1)); ADDR_SEEN[$ip]=1; }
        # The tool writes a result for an address one time only. It shows each
        # hostname on the screen, but the result names the address.
        local first_for_ip=1
        [ -n "${IP_RESULT_DONE[$ip]+x}" ] && first_for_ip=0
        IP_RESULT_DONE[$ip]=1
        # The tool collects the addresses of each network here. It writes the
        # results after the loop.
        local netkey="$cls|${desc:-no-description}"
        if [ "$first_for_ip" -eq 1 ]; then
          NET_ADDRS[$netkey]="${NET_ADDRS[$netkey]:-}${NET_ADDRS[$netkey]:+ }$ip"
          NET_CLASS[$netkey]="$cls"
          [ -z "${NET_HOST[$netkey]:-}" ] && NET_HOST[$netkey]="$host"
        fi
        case "$cls" in
          consumer|home-hint)
            host_cls="home"
            say "    $(c red '!') $host -> $ip $(c red "[$cls: ${desc:-the RIR gives no description}]")"
            ;;
          datacenter)
            [ "$host_cls" = "cloudflare" ] && host_cls="datacenter"
            say "    $(c yellow '·') $host -> $ip $(c dim "[data center: ${desc}]")"
            ;;
          *)
            [ "$host_cls" = "cloudflare" ] && host_cls="unknown"
            say "    $(c yellow '?') $host -> $ip $(c yellow '[the tool cannot classify this network]')"
            ;;
        esac
      fi
    done <<< "$allips"

    jq -n --arg host "$host" --arg cls "$host_cls" --arg net "$networks" \
      --argjson a "$(printf '%s' "$ips" | json_lines)" \
      --argjson aaaa "$(printf '%s' "$ip6s" | json_lines)" \
      '{host: $host, a: $a, aaaa: $aaaa, classification: $cls, networks: $net}' \
      >> "$WORK/hosts.ndjson"
  done < "$WORK/resolved.tsv"

  # One result for each network. The addresses of one company are the same
  # infrastructure, therefore one result gives you the same information as many.
  local netkey netcls netdesc addrs naddr
  for netkey in "${!NET_ADDRS[@]}"; do
    netcls="${NET_CLASS[$netkey]}"
    netdesc="${netkey#*|}"
    addrs="${NET_ADDRS[$netkey]}"
    naddr="$(printf '%s' "$addrs" | wc -w | tr -d ' ')"
    case "$netcls" in
      consumer|home-hint)
        add_result HIGH ORIGIN-RESIDENTIAL "$naddr address(es) are on a home internet service: $netdesc. The addresses are: $(printf '%s' "$addrs" | cut -c1-200). An attacker can find your house from an address on that network. The addresses do not use a proxy."
        ;;
      datacenter)
        add_result LOW ORIGIN-DATACENTER "$naddr address(es) are at $netdesc. The addresses are: $(printf '%s' "$addrs" | cut -c1-200). This is not a home address. These are your origin servers, and they do not use a proxy."
        ;;
      *)
        if [ "$HAVE_WHOIS" -eq 1 ]; then
          add_result MEDIUM ORIGIN-UNKNOWN "$naddr address(es) have no clear RIR description: $(printf '%s' "$addrs" | cut -c1-200). Check the network yourself. It can be a data center or a home."
        else
          add_result MEDIUM ORIGIN-NOWHOIS "$naddr address(es) are not in the Cloudflare ranges: $(printf '%s' "$addrs" | cut -c1-200). The whois tool is absent, therefore the tool cannot find the owner of the network. Install whois."
        fi
        ;;
    esac
  done

  if [ ! -s "$WORK/live-hosts.txt" ]; then
    say "  $(c green 'No name points to an address.')"
    add_result LOW NO-ADDRESS-RECORDS "No name under this domain points to an IP address. Therefore an attacker can find no origin server."
  else
    say "  $cf_count address(es) use a proxy. $origin_count address(es) are direct. The tool found ${#NET_ADDRS[@]} network(s)."
  fi

  jq -s '.' "$WORK/hosts.ndjson" > "$WORK/hosts.json" 2>/dev/null || printf '[]' > "$WORK/hosts.json"
}

# ---------------------------------------------------------------------------
# CHECK 5 – HTTP surface
# ---------------------------------------------------------------------------

SENSITIVE_PATHS=(
  /.git/HEAD /.git/config /.env /.env.local /.env.production
  /config.php.bak /wp-config.php.bak /.DS_Store
  /server-status /server-info /status /nginx_status
  /wp-json/wp/v2/users "/?author=1" /author-sitemap.xml
  /.well-known/security.txt /robots.txt /sitemap.xml /humans.txt
  /phpinfo.php /info.php /adminer.php /.svn/entries /.hg/store
  /backup.sql /dump.sql /db.sql /.aws/credentials /.ssh/id_rsa
)

check_http() {
  local domain="$1"
  head1 "5. HTTP paths and headers"

  if [ "$DO_HTTP" -eq 0 ]; then
    say "  The tool did not run this check. You used --no-http."; printf '[]' > "$WORK/http.json"; return
  fi
  if [ ! -s "$WORK/live-hosts.txt" ]; then
    say "  No name points to an address. Therefore the tool sends no HTTP request."
    printf '[]' > "$WORK/http.json"; return
  fi

  : > "$WORK/http.ndjson"
  local host code hdrs server exposed p

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    hdrs="$WORK/hdr.txt"
    code="$(http_code curl -skI --max-time "$DEA_TIMEOUT" -A "$DEA_USER_AGENT" \
            -o "$hdrs" -w '%{http_code}' "https://$host")"
    if [ "$code" = "000" ]; then
      say "  $host  gives no HTTPS answer"
      jq -n --arg h "$host" '{host: $h, code: 0, server: "", exposed: []}' >> "$WORK/http.ndjson"
      continue
    fi

    server="$(grep -i '^server:' "$hdrs" 2>/dev/null | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ //')"
    say "  $host  HTTP $code  ${server:+server: $server}"

    # A version number in the Server header tells an attacker which faults
    # to try.
    if printf '%s' "$server" | grep -qE '[0-9]+\.[0-9]+'; then
      add_result LOW HTTP-SERVER-VERSION "$host sends a Server header with a version number: $server. Remove the version number. It helps an attacker to find faults."
    fi
    local leaky
    leaky="$(grep -iE '^(x-real-ip|x-served-by|x-backend|x-origin|x-forwarded-server|via):' "$hdrs" 2>/dev/null | tr -d '\r' | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
    [ -n "$leaky" ] && add_result MEDIUM HTTP-ORIGIN-HEADER "$host sends headers that can give the name of your origin server: $leaky"

    exposed=""
    for p in "${SENSITIVE_PATHS[@]}"; do
      local pc
      pc="$(http_code curl -sk -o /dev/null --max-time 10 -A "$DEA_USER_AGENT" \
            -w '%{http_code}' "https://$host$p")"
      case "$p:$pc" in
        /robots.txt:200|/sitemap.xml:200|/.well-known/security.txt:200|/humans.txt:200)
          say "    $(c dim "$p -> $pc. This path is public for a good reason.")" ;;
        *:200)
          exposed="$exposed${exposed:+ }$p"
          say "    $(c red "$p -> 200")"
          case "$p" in
            /.git/*|/.env*|*/credentials|*id_rsa|*.sql)
              add_result HIGH HTTP-EXPOSED "$host gives the path $p with the HTTP code 200. Any person can possibly get your source code, your secrets, or a copy of your database." ;;
            /wp-json/wp/v2/users|"/?author=1")
              add_result MEDIUM HTTP-AUTHORS "$host gives the path $p. This path shows the WordPress user names and the display names." ;;
            *)
              add_result MEDIUM HTTP-EXPOSED-MINOR "$host gives the path $p with the HTTP code 200. Make sure that you want this path to be public." ;;
          esac ;;
      esac
    done

    jq -n --arg h "$host" --argjson code "$code" --arg server "$server" \
      --argjson exposed "$(printf '%s' "$exposed" | tr ' ' '\n' | json_lines)" \
      '{host: $h, code: $code, server: $server, exposed: $exposed}' >> "$WORK/http.ndjson"
  done < "$WORK/live-hosts.txt"

  jq -s '.' "$WORK/http.ndjson" > "$WORK/http.json" 2>/dev/null || printf '[]' > "$WORK/http.json"
}

# ---------------------------------------------------------------------------
# CHECK 6 – Archived copies
# ---------------------------------------------------------------------------

check_archive() {
  local domain="$1"
  head1 "6. Copies in the archive (Wayback Machine)"

  if [ "$DO_ARCHIVE" -eq 0 ]; then
    say "  The tool did not run this check. You used --no-archive."; printf '{"skipped":true}' > "$WORK/archive.json"; return
  fi

  local out="$WORK/cdx.json" code
  code="$(cache_fetch "https://web.archive.org/cdx/search/cdx?url=${domain}&matchType=domain&output=json&fl=timestamp,original&collapse=urlkey&limit=2000" \
          "$out" 24 'application/json')"

  if ! jq -e 'type == "array"' "$out" >/dev/null 2>&1; then
    say "  The Wayback CDX service gave no answer. The HTTP code was $code."
    add_result LOW ARCHIVE-UNAVAILABLE "The Wayback CDX service gave no answer. The HTTP code was $code. This run did not check the archives."
    printf '{"error":true}' > "$WORK/archive.json"; return
  fi

  local n first last
  n="$(jq 'length' "$out" 2>/dev/null || printf 0)"
  [ "$n" -gt 0 ] && n=$(( n - 1 ))   # first row is the CDX header
  first="$(jq -r '.[1:] | map(.[0]) | sort | first // ""' "$out" 2>/dev/null)"
  last="$(jq -r '.[1:] | map(.[0]) | sort | last // ""' "$out" 2>/dev/null)"

  if [ "$n" -le 0 ]; then
    say "  The archive holds no copy of this domain."
    add_result LOW ARCHIVE-NONE "The Wayback Machine holds no copy of this domain."
  else
    say "  The archive holds $n address(es). The first is from $first. The last is from $last."
    add_result MEDIUM ARCHIVE-PRESENT "The Wayback Machine holds $n address(es) for this domain. The first is from $first and the last is from $last. An archived page can still show contact data that you removed. Read the pages at https://web.archive.org/web/*/$domain/*"
  fi

  jq -n --argjson n "$n" --arg first "$first" --arg last "$last" \
    '{snapshots: $n, first: $first, last: $last}' > "$WORK/archive.json"
}

# ---------------------------------------------------------------------------
# CHECK 7 – EXIF GPS in published images (opt-in)
# ---------------------------------------------------------------------------

check_exif() {
  local domain="$1"
  [ "$DO_EXIF" -eq 1 ] || { printf '{"skipped":true}' > "$WORK/exif.json"; return; }
  head1 "7. GPS data in the images on your site"

  if [ "$HAVE_EXIFTOOL" -eq 0 ]; then
    say "  The exiftool program is absent. On Arch, install perl-image-exiftool."
    printf '{"skipped":true}' > "$WORK/exif.json"; return
  fi
  if [ ! -s "$WORK/live-hosts.txt" ]; then
    say "  No host answers, therefore the tool can get no image."
    printf '{"skipped":true}' > "$WORK/exif.json"; return
  fi

  # Remove the images of an earlier domain, for the same reason as above.
  local imgdir="$WORK/img"; rm -rf "$imgdir"; mkdir -p "$imgdir"
  local page="$WORK/page.html" host
  host="$(head -1 "$WORK/live-hosts.txt")"
  curl -sk --max-time "$DEA_TIMEOUT" -A "$DEA_USER_AGENT" "https://$host" -o "$page" 2>/dev/null

  local u url count=0
  while IFS= read -r u; do
    [ "$count" -ge 15 ] && break
    case "$u" in
      http*) url="$u" ;;
      //*)   url="https:$u" ;;
      /*)    url="https://$host$u" ;;
      *)     url="https://$host/$u" ;;
    esac
    curl -sk --max-time 15 -A "$DEA_USER_AGENT" -o "$imgdir/img$count.bin" "$url" 2>/dev/null
    count=$((count + 1))
  done < <(grep -oiE 'src="[^"]+\.(jpe?g|png|tiff?|heic|webp)"' "$page" 2>/dev/null | cut -d'"' -f2 | sort -u)

  local gps
  gps="$(exiftool -q -q -gps:all -n "$imgdir" 2>/dev/null | grep -i 'gps' || true)"
  if [ -n "$gps" ]; then
    add_result HIGH EXIF-GPS "The tool got $count image(s) from $host. One image or more holds GPS data. The picture shows the place where a person made it."
    say "  $(c red 'The images on your site hold GPS data.')"
  else
    say "  The tool read $count image(s). It found no GPS data."
  fi
  jq -n --argjson n "$count" --argjson gps "$([ -n "$gps" ] && echo true || echo false)" \
    '{images_checked: $n, gps_found: $gps}' > "$WORK/exif.json"
}

# ---------------------------------------------------------------------------
# CHECK 8 – Shodan (opt-in, needs SHODAN_API_KEY)
# ---------------------------------------------------------------------------

check_shodan() {
  [ -n "$SHODAN_API_KEY" ] || { printf '{"skipped":true}' > "$WORK/shodan.json"; return; }
  head1 "8. Shodan records for the origin servers"

  local ips ip out code found=0
  ips="$(jq -r '.[] | select(.classification != "cloudflare") | (.a + .aaaa)[]' "$WORK/hosts.json" 2>/dev/null | sort -u)"
  if [ -z "$ips" ]; then
    say "  All addresses use a proxy, therefore the tool queries nothing."
    printf '{"checked":0}' > "$WORK/shodan.json"; return
  fi

  while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    out="$WORK/shodan-$ip.json"
    code="$(fetch "https://api.shodan.io/shodan/host/${ip}?key=${SHODAN_API_KEY}" "$out" 'application/json')"
    case "$code" in
      2*) local ports org
          ports="$(jq -r '(.ports // []) | map(tostring) | join(",")' "$out" 2>/dev/null)"
          org="$(jq -r '.org // ""' "$out" 2>/dev/null)"
          say "  $ip  ports: ${ports:-none}  org: $org"
          [ -n "$ports" ] && add_result MEDIUM SHODAN-INDEXED "Shodan has a record of $ip with these open ports: $ports. The network is $org. This address and its services are in a public database."
          found=$((found + 1)) ;;
      404) say "  $ip  is not in Shodan" ;;
      *)   say "  $ip  the query failed. The HTTP code was $code." ;;
    esac
  done <<< "$ips"

  jq -n --argjson n "$found" '{indexed: $n}' > "$WORK/shodan.json"
}

# ---------------------------------------------------------------------------
# Snapshots, changes, and reports
# ---------------------------------------------------------------------------

build_snapshot() {
  local domain="$1"
  jq -n \
    --arg schema "1" \
    --arg domain "$domain" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg tool_version "$VERSION" \
    --slurpfile registration "$WORK/registration.json" \
    --slurpfile dns "$WORK/dns.json" \
    --slurpfile ct "$WORK/ct.json" \
    --slurpfile hosts "$WORK/hosts.json" \
    --slurpfile http "$WORK/http.json" \
    --slurpfile archive "$WORK/archive.json" \
    --slurpfile exif "$WORK/exif.json" \
    --slurpfile shodan "$WORK/shodan.json" \
    --slurpfile enrich "$WORK/enrich.json" \
    --argjson results "$(json_results)" \
    '{schema: ($schema | tonumber), domain: $domain, generated_at: $generated_at,
      tool_version: $tool_version,
      registration: ($registration[0] // {}), dns: ($dns[0] // {}),
      ct: ($ct[0] // {}), hosts: ($hosts[0] // []), http: ($http[0] // []),
      archive: ($archive[0] // {}), exif: ($exif[0] // {}),
      shodan: ($shodan[0] // {}), enrich: ($enrich[0] // {}),
      results: $results}'
}

# num VALUE -> the value if it is a number, and 0 if it is not
num() { case "${1:-}" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }

# 1.3.0: These result codes mean that a service gave no data, therefore the run
# did not see everything. A baseline from such a run is a trap: the next run
# shows the recovery of the service as though it were news about your domain.
# CT-SECOND-SOURCE is NOT in this list. crt.sh fails often, and certspotter
# gives a good answer. That condition gives a warning only.
INCOMPLETE_CODES="CT-UNAVAILABLE ARCHIVE-UNAVAILABLE RDAP-UNREADABLE HARVEST-UNREADABLE"

# incomplete_reasons -> the codes from this run that show missing data
incomplete_reasons() {
  local code found=""
  for code in $INCOMPLETE_CODES; do
    if cut -f2 "$R_FILE" 2>/dev/null | grep -qxF "$code"; then
      found="$found${found:+ }$code"
    fi
  done
  printf '%s' "$found"
}

json_results() {
  if [ -s "$R_FILE" ]; then
    jq -R -s '
      split("\n") | map(select(length > 0) | split("\t")
      | {severity: .[0], code: .[1], message: (.[2] // "")})
    ' "$R_FILE"
  else
    printf '[]'
  fi
}

# The tool compares the fields that show your public data.
diff_snapshots() { # diff_snapshots OLD NEW
  jq -n --slurpfile old "$1" --slurpfile new "$2" '
    def setdiff($a; $b): (($a // []) - ($b // []));
    ($old[0] // {}) as $o | ($new[0] // {}) as $n
    | {
        ct_added:        setdiff($n.ct.names; $o.ct.names),
        ct_removed:      setdiff($o.ct.names; $n.ct.names),
        a_added:         setdiff($n.dns.a; $o.dns.a),
        a_removed:       setdiff($o.dns.a; $n.dns.a),
        aaaa_added:      setdiff($n.dns.aaaa; $o.dns.aaaa),
        aaaa_removed:    setdiff($o.dns.aaaa; $n.dns.aaaa),
        ns_added:        setdiff($n.dns.ns; $o.dns.ns),
        ns_removed:      setdiff($o.dns.ns; $n.dns.ns),
        mx_added:        setdiff($n.dns.mx; $o.dns.mx),
        mx_removed:      setdiff($o.dns.mx; $n.dns.mx),
        txt_added:       setdiff($n.dns.txt; $o.dns.txt),
        txt_removed:     setdiff($o.dns.txt; $n.dns.txt),
        hosts_added:     setdiff([$n.hosts[]?.host]; [$o.hosts[]?.host]),
        hosts_removed:   setdiff([$o.hosts[]?.host]; [$n.hosts[]?.host]),
        results_added:  setdiff([$n.results[]? | .code + ": " + .message];
                                 [$o.results[]? | .code + ": " + .message]),
        results_cleared: setdiff([$o.results[]? | .code + ": " + .message];
                                  [$n.results[]? | .code + ": " + .message]),
        spf_changed:     ($o.dns.spf != $n.dns.spf),
        dmarc_changed:   ($o.dns.dmarc != $n.dns.dmarc),
        pii_changed:     ($o.registration.pii_published != $n.registration.pii_published)
      } | with_entries(select(
            (.value | type) == "boolean" and .value == true
            or ((.value | type) == "array" and (.value | length) > 0)))
  '
}

print_diff() { # print_diff DIFFJSON
  local d="$1" keys
  keys="$(jq -r 'keys[]' "$d" 2>/dev/null)"
  [ -z "$keys" ] && { say "  $(c green 'Nothing is different from the baseline.')"; return 1; }
  local k
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$(jq -r --arg k "$k" '.[$k] | type' "$d")" in
      boolean) say "  $(c yellow '~') $k" ;;
      array)
        say "  $(c yellow '~') $k:"
        jq -r --arg k "$k" '.[$k][] | "      " + .' "$d" | while IFS= read -r line; do say "$line"; done ;;
    esac
  done <<< "$keys"
  return 0
}

write_report() { # write_report DOMAIN SNAPSHOT DIFF
  local domain="$1" snap="$2" dj="$3"
  mkdir -p "$DEA_REPORT_DIR" 2>/dev/null || return 0
  local rf="$DEA_REPORT_DIR/${domain}-$(date -u +%Y%m%dT%H%M%SZ).md"
  {
    printf '# Public data report: %s\n\n' "$domain"
    printf -- '- generated: `%s`\n' "$(jq -r '.generated_at' "$snap")"
    printf -- '- tool: `domain-exposure-audit %s`\n\n' "$VERSION"

    printf '## Results\n\n'
    local sev
    for sev in HIGH MEDIUM LOW; do
      local n; n="$(num "$(jq --arg s "$sev" '[.results[] | select(.severity == $s)] | length' "$snap" 2>/dev/null)")"
      [ "$n" -eq 0 ] && continue
      printf '### %s (%s)\n\n' "$sev" "$n"
      jq -r --arg s "$sev" '.results[] | select(.severity == $s)
        | "- **" + .code + "**: " + .message' "$snap"
      printf '\n'
    done
    [ "$(num "$(jq '.results | length' "$snap" 2>/dev/null)")" -eq 0 ] && printf 'No results.\n\n'

    printf '## Registration\n\n```json\n'
    jq '.registration' "$snap"
    printf '```\n\n## DNS\n\n```json\n'
    jq '.dns' "$snap"
    printf '```\n\n## Certificate Transparency\n\n```json\n'
    jq '{count: (.ct.names | length), names: .ct.names, issuers: .ct.issuers}' "$snap"
    printf '```\n\n## Hosts\n\n```json\n'
    jq '.hosts' "$snap"
    printf '```\n\n## Changes from the baseline\n\n```json\n'
    cat "$dj" 2>/dev/null || printf '{}'
    printf '\n```\n'
  } > "$rf"
  say "  The tool wrote the report to $rf"
}

# ---------------------------------------------------------------------------
# Per-domain driver
# ---------------------------------------------------------------------------

audit_domain() {
  local domain="$1"
  local sdir="$DEA_STATE_DIR/$domain"
  mkdir -p "$sdir"

  R_FILE="$WORK/results.tsv"
  IP_DESC_CACHE=()
  IP_RESULT_DONE=()
  NET_ADDRS=()
  NET_CLASS=()
  NET_HOST=()
  ADDR_SEEN=()
  : > "$R_FILE"
  : > "$WORK/ct-plain.txt"
  : > "$WORK/enrich-names.txt"
  printf '{"used":[],"names":0}' > "$WORK/enrich.json"

  [ "$QUIET" -eq 1 ] || { printf '\n'; c bold "════ $domain ════"; printf '\n'; }

  check_registration "$domain"
  check_dns "$domain"
  check_ct "$domain"
  check_enrich "$domain"
  check_hosts "$domain"
  check_http "$domain"
  check_archive "$domain"
  check_exif "$domain"
  check_shodan

  local snap="$WORK/snapshot.json"
  build_snapshot "$domain" > "$snap"

  local nc nw ni
  nc="$(jq '[.results[] | select(.severity == "HIGH")]   | length' "$snap" 2>/dev/null)"
  nw="$(jq '[.results[] | select(.severity == "MEDIUM")] | length' "$snap" 2>/dev/null)"
  ni="$(jq '[.results[] | select(.severity == "LOW")]    | length' "$snap" 2>/dev/null)"
  nc="$(num "$nc")"; nw="$(num "$nw")"; ni="$(num "$ni")"

  # --- diff against baseline ---
  local baseline="$sdir/baseline.json" dj="$WORK/diff.json" changed=0
  if [ -f "$baseline" ]; then
    diff_snapshots "$baseline" "$snap" > "$dj" 2>/dev/null || printf '{}' > "$dj"
    [ "$(num "$(jq 'length' "$dj" 2>/dev/null)")" -gt 0 ] && changed=1
  else
    printf '{}' > "$dj"
  fi

  if [ "$DIFF_ONLY" -eq 0 ]; then
    head1 "Summary"
    say "  $(c red "HIGH: $nc")   $(c yellow "MEDIUM: $nw")   $(c dim "LOW: $ni")"
    local sev code msg
    while IFS=$'\t' read -r sev code msg; do
      case "$sev" in
        HIGH) say "  $(c red '✖') $(c bold "$code") $msg" ;;
        MEDIUM)   say "  $(c yellow '▲') $code $msg" ;;
        LOW)      say "  $(c dim "· $code $msg")" ;;
      esac
    done < "$R_FILE"
  fi

  head1 "Changes from the baseline"
  if [ ! -f "$baseline" ]; then
    say "  There is no baseline. Use --baseline to keep this run as the baseline."
  else
    print_diff "$dj" || true
  fi

  # --- persist ---
  cp "$snap" "$sdir/latest.json"
  mkdir -p "$sdir/history"
  cp "$snap" "$sdir/history/$(date -u +%Y%m%dT%H%M%SZ).json"
  # The tool keeps the last 120 snapshots.
  ls -1t "$sdir/history" 2>/dev/null | tail -n +121 | while IFS= read -r old; do
    rm -f "$sdir/history/$old"
  done

  if [ "$SET_BASELINE" -eq 1 ]; then
    # 1.3.0: Do not make a baseline from a run that did not see all the data.
    local missing; missing="$(incomplete_reasons)"
    if [ -n "$missing" ] && [ "$FORCE_BASELINE" -eq 0 ]; then
      warn "$domain: the tool did NOT write a baseline. These services gave no data: $missing."
      warn "$domain: a baseline from this run makes the next run show the recovery of the service as a change."
      warn "$domain: run the tool again later, or use --force-baseline to write the baseline now."
    else
      cp "$snap" "$baseline"
      say "  The tool wrote the baseline to $baseline"
      [ -n "$missing" ] && warn "$domain: the baseline holds incomplete data, because you used --force-baseline. These services gave no data: $missing."
      changed=0
    fi
  fi

  [ -n "$DEA_REPORT_DIR" ] && write_report "$domain" "$snap" "$dj"
  [ "$EMIT_JSON" -eq 1 ] && cat "$snap"

  # --- notify ---
  # 1.3.0: This block comes BEFORE the exit mask. Up to version 1.2.1 an
  # unconditional "return 0" was above it, therefore the notify command never
  # ran in any version. tests/test-parsing.sh now guards the order.
  if [ -n "$DEA_NOTIFY_CMD" ] && { [ "$changed" -eq 1 ] || [ "$nc" -gt 0 ]; }; then
    {
      printf '%s: %s HIGH, %s MEDIUM' "$domain" "$nc" "$nw"
      [ "$changed" -eq 1 ] && printf ', and the data changed from the baseline'
      printf '\n'
      jq -r '.results[] | select(.severity == "HIGH") | "  ! " + .code + " " + .message' "$snap"
      jq -r 'to_entries[] | "  ~ " + .key' "$dj" 2>/dev/null
    } | sh -c "$DEA_NOTIFY_CMD" || warn "the notify command failed"
  fi

  # --- exit mask contribution ---
  # A LOW result sets no bit. Every domain publishes its region for all time.
  # If a LOW result set a bit, the exit code would give you no information.
  [ "$nw" -gt 0 ]      && EXIT_MASK=$(( EXIT_MASK | 1 ))
  [ "$nc" -gt 0 ]      && EXIT_MASK=$(( EXIT_MASK | 2 ))
  [ "$changed" -eq 1 ] && EXIT_MASK=$(( EXIT_MASK | 4 ))
  # The last test is false when nothing changed, therefore the function needs
  # an explicit success. Keep this line LAST.
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# The lock stops two runs at the same time. Therefore a cron job cannot start
# while you run the tool yourself.
LOCK="$DEA_STATE_DIR/.lock"
if need flock; then
  exec 9>"$LOCK" || die "cannot open lock file $LOCK"
  flock -n 9 || die "the tool is already in use. The lock file is $LOCK"
fi

load_cloudflare_ranges

for d in "${DOMAINS[@]}"; do
  d="$(printf '%s' "$d" | lc | sed 's#^https\?://##; s#/.*##; s/\.$//')"
  case "$d" in
    ""|*[!a-z0-9.-]*) warn "this domain name is not valid: $d"; continue ;;
  esac
  audit_domain "$d"
done

[ "$QUIET" -eq 1 ] || printf '\n%s exit code %s\n' "$(c dim 'The tool is ready.')" "$EXIT_MASK"
exit "$EXIT_MASK"
