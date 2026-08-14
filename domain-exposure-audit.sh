#!/usr/bin/env bash
#
# domain-exposure-audit — a tool that finds the public data about your domains
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

set -uo pipefail

VERSION="1.0.0"
PROGNAME="${0##*/}"

# ---------------------------------------------------------------------------
# Default values. Flags and environment variables can change them.
# ---------------------------------------------------------------------------

: "${DEA_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/domain-exposure-audit}"
: "${DEA_REPORT_DIR:=$DEA_STATE_DIR/reports}"
: "${DEA_CONFIG:=}"
: "${DEA_TIMEOUT:=20}"
: "${DEA_CT_CACHE_HOURS:=6}"
: "${DEA_NOTIFY_CMD:=}"
: "${DEA_USER_AGENT:=domain-exposure-audit/$VERSION (+self-audit)}"
: "${SHODAN_API_KEY:=}"

DOMAINS=()
WORDLIST=""
DO_HTTP=1
DO_CT=1
DO_ARCHIVE=1
DO_EXIF=0
SET_BASELINE=0
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
$PROGNAME $VERSION — find the public data about domains that you own

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
      --baseline          keep this run as the baseline, then stop with code 0
      --diff-only         show only the changes from the baseline
  -s, --state-dir DIR     the directory for the snapshots
                          Default: $DEA_STATE_DIR

WHICH CHECKS TO RUN
      --no-http           do not send HTTP requests
      --no-ct             do not query Certificate Transparency (crt.sh)
      --no-archive        do not query the Wayback Machine
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
  -V, --version
  -h, --help

The EXIT CODE is a bitmask. One number can show you more than one result.
    0  no results, and no change
    1  the tool found MEDIUM results
    2  the tool found HIGH results
    4  the tool found a change from the baseline
    8  the tool failed. A tool is absent, or the tool cannot write to the
       state directory.
For example, the code 6 shows HIGH results and a change from the baseline.

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
    --diff-only)     DIFF_ONLY=1; shift ;;
    --no-http)       DO_HTTP=0; shift ;;
    --no-ct)         DO_CT=0; shift ;;
    --no-archive)    DO_ARCHIVE=0; shift ;;
    --exif)          DO_EXIF=1; shift ;;
    --wordlist)      WORDLIST="$2"; shift 2 ;;
    --json)          EMIT_JSON=1; shift ;;
    --notify)        DEA_NOTIFY_CMD="$2"; shift 2 ;;
    --timeout)       DEA_TIMEOUT="$2"; shift 2 ;;
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

CACHE="$DEA_STATE_DIR/cache"
mkdir -p "$CACHE"

EXIT_MASK=0

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

# fetch URL OUTFILE [accept] -> prints HTTP status, 000 on transport failure
fetch() {
  local url="$1" out="$2" accept="${3:-*/*}"
  curl -sS -L --max-time "$DEA_TIMEOUT" \
       -A "$DEA_USER_AGENT" -H "Accept: $accept" \
       -o "$out" -w '%{http_code}' "$url" 2>/dev/null || printf '000'
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

# ip_network_desc IP -> the organization name and the network name from the RIR
ip_network_desc() {
  [ "$HAVE_WHOIS" -eq 1 ] || { printf ''; return; }
  whois "$1" 2>/dev/null \
    | grep -iE '^(orgname|org-name|organization|netname|descr|owner|customer):' \
    | head -3 | cut -d: -f2- | tr -s ' \t' ' ' | sed 's/^ //' \
    | tr '\n' ';' | sed 's/;$//' | cut -c1-200
}

# ---------------------------------------------------------------------------
# CHECK 1 — Registration data (RDAP, with port-43 WHOIS as fallback)
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

  if ! jq -e . "$reg" >/dev/null 2>&1; then
    add_result MEDIUM RDAP-UNREADABLE "The registry RDAP server gave no valid JSON. The HTTP code was $code. This run did not check your registration data."
    printf '{}' > "$WORK/registration.json"
    return
  fi

  case "$code" in
    404) add_result LOW RDAP-NOTFOUND "The registry says that this domain has no registration."
         printf '{"registered":false}' > "$WORK/registration.json"; return ;;
    2*)  : ;;
    *)   add_result MEDIUM RDAP-HTTP "The registry RDAP server gave the HTTP code $code. The registration data from this run is not reliable." ;;
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

  local pii_found=0 registrant_seen=0 region="" country=""
  while IFS=$'\t' read -r roles key value; do
    case "$roles" in *registrant*|*administrative*|*technical*|*abuse*) ;; *) continue ;; esac
    case "$roles" in *registrant*) registrant_seen=1 ;; esac

    case "$key" in
      adr)
        # The parts of a vCard address are in this order: post office box,
        # extension, street, city, region, postal code, and country.
        local _pobox _ext street city reg_ post country_
        IFS='|' read -r _pobox _ext street city reg_ post country_ <<< "$value"
        region="${reg_:-$region}"; country="${country_:-$country}"
        if ! is_redacted "$street"; then
          add_result HIGH PII-STREET "RDAP shows the street address of the $roles. Any person can read it."
          pii_found=1
        fi
        if ! is_redacted "$city"; then
          add_result HIGH PII-CITY "RDAP shows the city of the $roles. Any person can find your city."
          pii_found=1
        fi
        if ! is_redacted "$post"; then
          add_result HIGH PII-POSTCODE "RDAP shows the postal code of the $roles. A postal code gives an attacker a small group of streets."
          pii_found=1
        fi
        ;;
      fn|org)
        if ! is_redacted "$value"; then
          case "$roles" in
            *registrant*) add_result MEDIUM PII-NAME "RDAP shows the name or the organization of the $roles. This gives your identity, but not your location." ; pii_found=1 ;;
          esac
        fi
        ;;
      email)
        if ! is_redacted "$value"; then
          add_result MEDIUM PII-EMAIL "RDAP shows the email address of the $roles. Programs will collect it. You will get false messages about your domain."
          pii_found=1
        fi
        ;;
      tel)
        # The telephone number of the registrar is normal. It is not your
        # number.
        if ! is_redacted "$value"; then
          add_result LOW RDAP-TEL "RDAP shows this telephone number for the $roles: $value. Make sure that the number belongs to the registrar and not to you."
        fi
        ;;
    esac
  done < "$WORK/vcards.tsv"

  if [ "$registrant_seen" -eq 0 ]; then
    add_result LOW RDAP-NO-REGISTRANT "RDAP shows no registrant record. This is the best possible result."
  elif [ "$pii_found" -eq 0 ]; then
    add_result LOW RDAP-REDACTED "RDAP shows a registrant record. All the personal fields hold redacted data."
  fi

  [ -n "$region" ] && ! is_redacted "$region" && \
    add_result LOW RDAP-REGION "RDAP shows this region: $region. ICANN rules make this necessary. No registrar can hide it."
  [ -n "$country" ] && ! is_redacted "$country" && \
    add_result LOW RDAP-COUNTRY "RDAP shows this country: $country. ICANN rules make this necessary."

  # --- lock status and expiry ---
  local statuses expiry
  statuses="$(jq -r '(.status // [])[]' "$src" 2>/dev/null | sort -u | paste -sd, -)"
  say "  status: ${statuses:-the registry publishes no status}"
  case "$statuses" in
    *clientTransferProhibited*) : ;;
    *) add_result MEDIUM NO-TRANSFER-LOCK "The status clientTransferProhibited is absent. A person can move your domain to another registrar more easily." ;;
  esac
  case "$statuses" in
    *clientUpdateProhibited*|*serverUpdateProhibited*) : ;;
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
      if grep -iE '^[[:space:]]*(registrant|admin) (street|city|postal)' "$w" \
         | cut -d: -f2- | grep -qvE "$REDACTION_PATTERNS" 2>/dev/null; then
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
# CHECK 2 — DNS posture
# ---------------------------------------------------------------------------

check_dns() {
  local domain="$1"
  head1 "2. DNS records"

  local ns soa a aaaa mx txt caa ds spf dmarc
  ns="$(dig_short NS "$domain")"
  soa="$(dig_short SOA "$domain")"
  a="$(dig_short A "$domain" | grep -E '^[0-9]+\.' || true)"
  aaaa="$(dig_short AAAA "$domain" | grep ':' || true)"
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
    case "$rname" in
      *cloudflare.com|*awsdns*|*azure*|*googledomains*|*nsone*|*dnsimple*|*registrar*) : ;;
      "") : ;;
      *) add_result LOW SOA-RNAME "The SOA record holds this contact: $rname. If this is your personal mailbox, all persons who query your zone can read it." ;;
    esac
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
# CHECK 3 — Certificate Transparency
# ---------------------------------------------------------------------------

check_ct() {
  local domain="$1"
  head1 "3. Certificate Transparency (crt.sh)"

  if [ "$DO_CT" -eq 0 ]; then
    say "  The tool did not run this check. You used --no-ct."
    printf '{"skipped":true,"names":[],"wildcards":[]}' > "$WORK/ct.json"
    return
  fi

  local out="$WORK/ct.json.raw" code
  code="$(cache_fetch "https://crt.sh/?q=%25.${domain}&output=json" "$out" "$DEA_CT_CACHE_HOURS" 'application/json')"
  say "  crt.sh -> $code"

  if ! jq -e 'type == "array"' "$out" >/dev/null 2>&1; then
    add_result MEDIUM CT-UNAVAILABLE "crt.sh gave no valid JSON. The HTTP code was $code. crt.sh often limits requests. Run the tool again later."
    printf '{"error":true,"names":[],"wildcards":[]}' > "$WORK/ct.json"
    return
  fi

  jq -r '.[].name_value' "$out" 2>/dev/null | tr ',' '\n' | lc \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u > "$WORK/ct-names.txt"

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
    local count; count="$(printf '%s' "$revealing" | grep -c . || true)"
    add_result LOW CT-HOSTNAMES "Certificate Transparency holds a permanent record of $count hostname(s): $(printf '%s' "$revealing" | paste -sd' ' - | cut -c1-300). A name such as pass, vault, nas, or status tells an attacker which software you use."
  fi
  [ "$wild" -gt 0 ] && [ "$plain" -gt 2 ] && \
    add_result LOW CT-MIXED "You have a wildcard certificate, but you also make a certificate for each host. Use only the wildcard certificate. Then no new hostname goes into a public log."

  local issuers latest
  issuers="$(jq -r '.[].issuer_name' "$out" 2>/dev/null | sed 's/.*O=\([^,]*\).*/\1/' | sort -u | paste -sd'; ' - | cut -c1-200)"
  latest="$(jq -r '.[].not_after' "$out" 2>/dev/null | sort -r | head -1)"
  [ -n "$issuers" ] && say "  issuers: $issuers"

  jq -n \
    --argjson names "$(cat "$WORK/ct-names.txt" | json_lines)" \
    --argjson wildcards "$(cat "$WORK/ct-wild.txt" | json_lines)" \
    --arg issuers "$issuers" --arg latest "$latest" \
    '{names: $names, wildcards: $wildcards, issuers: $issuers, latest_not_after: $latest}' \
    > "$WORK/ct.json"
}

# ---------------------------------------------------------------------------
# CHECK 4 — Hostname resolution and origin classification
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
  say "  The tool queries $ncand possible names from the logs and the word list."

  : > "$WORK/hosts.ndjson"
  : > "$WORK/live-hosts.txt"
  local host status ips ip6s allips ip desc cls cf_count=0 origin_count=0

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    status="$(dig_status "$host")"
    ips="$(dig_short A "$host" | grep -E '^[0-9]+\.' || true)"
    ip6s="$(dig_short AAAA "$host" | grep ':' || true)"
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
        cf_count=$((cf_count + 1))
        say "    $(c green '·') $host -> $ip $(c dim '[cloudflare proxy]')"
      else
        desc="$(ip_network_desc "$ip")"
        cls="$(classify_network "$desc")"
        networks="$networks${networks:+; }$desc"
        origin_count=$((origin_count + 1))
        case "$cls" in
          consumer|home-hint)
            host_cls="home"
            say "    $(c red '!') $host -> $ip $(c red "[$cls: ${desc:-the RIR gives no description}]")"
            add_result HIGH ORIGIN-RESIDENTIAL "$host points to $ip. This network is a home internet service: ${desc:-the RIR gives no description}. An attacker can find your house from this IP address. The address does not use a proxy."
            ;;
          datacenter)
            [ "$host_cls" = "cloudflare" ] && host_cls="datacenter"
            say "    $(c yellow '·') $host -> $ip $(c dim "[data center: ${desc}]")"
            add_result LOW ORIGIN-DATACENTER "$host points to $ip at ${desc}. This is not a home address. It is your origin server, and it does not use a proxy."
            ;;
          *)
            [ "$host_cls" = "cloudflare" ] && host_cls="unknown"
            say "    $(c yellow '?') $host -> $ip $(c yellow '[the tool cannot classify this network]')"
            if [ "$HAVE_WHOIS" -eq 1 ]; then
              add_result MEDIUM ORIGIN-UNKNOWN "$host points to $ip. The RIR description of this network is not clear. Check the network yourself. It can be a data center or a home."
            else
              add_result MEDIUM ORIGIN-NOWHOIS "$host points to $ip. This address is not in the Cloudflare ranges. The whois tool is absent, therefore the tool cannot find the owner of the network. Install whois."
            fi
            ;;
        esac
      fi
    done <<< "$allips"

    jq -n --arg host "$host" --arg cls "$host_cls" --arg net "$networks" \
      --argjson a "$(printf '%s' "$ips" | json_lines)" \
      --argjson aaaa "$(printf '%s' "$ip6s" | json_lines)" \
      '{host: $host, a: $a, aaaa: $aaaa, classification: $cls, networks: $net}' \
      >> "$WORK/hosts.ndjson"
  done < "$WORK/candidates.uniq"

  if [ ! -s "$WORK/live-hosts.txt" ]; then
    say "  $(c green 'No name points to an address.')"
    add_result LOW NO-ADDRESS-RECORDS "No name under this domain points to an IP address. Therefore an attacker can find no origin server."
  else
    say "  $cf_count address(es) use a proxy. $origin_count address(es) are direct."
  fi

  jq -s '.' "$WORK/hosts.ndjson" > "$WORK/hosts.json" 2>/dev/null || printf '[]' > "$WORK/hosts.json"
}

# ---------------------------------------------------------------------------
# CHECK 5 — HTTP surface
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
  head1 "5. HTTP surface"

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
    code="$(curl -skI --max-time "$DEA_TIMEOUT" -A "$DEA_USER_AGENT" \
            -o "$hdrs" -w '%{http_code}' "https://$host" 2>/dev/null || printf '000')"
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
    leaky="$(grep -iE '^(x-real-ip|x-served-by|x-backend|x-origin|x-forwarded-server|via):' "$hdrs" 2>/dev/null | tr -d '\r' | paste -sd'; ' -)"
    [ -n "$leaky" ] && add_result MEDIUM HTTP-ORIGIN-HEADER "$host sends headers that can give the name of your origin server: $leaky"

    exposed=""
    for p in "${SENSITIVE_PATHS[@]}"; do
      local pc
      pc="$(curl -sk -o /dev/null --max-time 10 -A "$DEA_USER_AGENT" \
            -w '%{http_code}' "https://$host$p" 2>/dev/null || printf '000')"
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
# CHECK 6 — Archived copies
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
# CHECK 7 — EXIF GPS in published images (opt-in)
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

  local imgdir="$WORK/img"; mkdir -p "$imgdir"
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
# CHECK 8 — Shodan (opt-in, needs SHODAN_API_KEY)
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
    --argjson results "$(json_results)" \
    '{schema: ($schema | tonumber), domain: $domain, generated_at: $generated_at,
      tool_version: $tool_version,
      registration: ($registration[0] // {}), dns: ($dns[0] // {}),
      ct: ($ct[0] // {}), hosts: ($hosts[0] // []), http: ($http[0] // []),
      archive: ($archive[0] // {}), exif: ($exif[0] // {}),
      shodan: ($shodan[0] // {}), results: $results}'
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
      local n; n="$(jq --arg s "$sev" '[.results[] | select(.severity == $s)] | length' "$snap")"
      [ "$n" -eq 0 ] && continue
      printf '### %s (%s)\n\n' "$sev" "$n"
      jq -r --arg s "$sev" '.results[] | select(.severity == $s)
        | "- **" + .code + "** — " + .message' "$snap"
      printf '\n'
    done
    [ "$(jq '.results | length' "$snap")" -eq 0 ] && printf 'No results.\n\n'

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
  : > "$R_FILE"
  : > "$WORK/ct-plain.txt"

  [ "$QUIET" -eq 1 ] || { printf '\n'; c bold "════ $domain ════"; printf '\n'; }

  check_registration "$domain"
  check_dns "$domain"
  check_ct "$domain"
  check_hosts "$domain"
  check_http "$domain"
  check_archive "$domain"
  check_exif "$domain"
  check_shodan

  local snap="$WORK/snapshot.json"
  build_snapshot "$domain" > "$snap"

  local nc nw ni
  nc="$(jq '[.results[] | select(.severity == "HIGH")] | length' "$snap")"
  nw="$(jq '[.results[] | select(.severity == "MEDIUM")]     | length' "$snap")"
  ni="$(jq '[.results[] | select(.severity == "LOW")]     | length' "$snap")"

  # --- diff against baseline ---
  local baseline="$sdir/baseline.json" dj="$WORK/diff.json" changed=0
  if [ -f "$baseline" ]; then
    diff_snapshots "$baseline" "$snap" > "$dj" 2>/dev/null || printf '{}' > "$dj"
    [ "$(jq 'length' "$dj" 2>/dev/null || printf 0)" -gt 0 ] && changed=1
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
    cp "$snap" "$baseline"
    say "  The tool wrote the baseline to $baseline"
    changed=0
  fi

  [ -n "$DEA_REPORT_DIR" ] && write_report "$domain" "$snap" "$dj"
  [ "$EMIT_JSON" -eq 1 ] && cat "$snap"

  # --- exit mask contribution ---
  # A LOW result sets no bit. Every domain publishes its region for all time.
  # If a LOW result set a bit, the exit code would give you no information.
  [ "$nw" -gt 0 ]      && EXIT_MASK=$(( EXIT_MASK | 1 ))
  [ "$nc" -gt 0 ]      && EXIT_MASK=$(( EXIT_MASK | 2 ))
  [ "$changed" -eq 1 ] && EXIT_MASK=$(( EXIT_MASK | 4 ))
  return 0

  # --- notify ---
  if [ -n "$DEA_NOTIFY_CMD" ] && { [ "$changed" -eq 1 ] || [ "$nc" -gt 0 ]; }; then
    {
      printf '%s: %s critical, %s warn' "$domain" "$nc" "$nw"
      [ "$changed" -eq 1 ] && printf ' — changed since baseline'
      printf '\n'
      jq -r '.results[] | select(.severity == "HIGH") | "  ! " + .code + " " + .message' "$snap"
      jq -r 'to_entries[] | "  ~ " + .key' "$dj" 2>/dev/null
    } | sh -c "$DEA_NOTIFY_CMD" || warn "the notify command failed"
  fi
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
