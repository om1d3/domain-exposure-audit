#!/usr/bin/env bash
#
# tests/test-classify.sh — unit tests for lib/classify.sh
#
# Run:  ./tests/test-classify.sh
#
# The tests use no network and need no special permissions. The exit code is not
# 0 if one test fails. Therefore you can use this file as a git hook or as a
# step in a build system.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/classify.sh
. "$HERE/../lib/classify.sh"

PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

# assert_true DESC command...
assert_true()  { if "${@:2}"; then ok "$1"; else bad "$1"; fi; }
assert_false() { if "${@:2}"; then bad "$1"; else ok "$1"; fi; }
# assert_eq DESC EXPECTED ACTUAL
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

printf '\n\033[1mis_redacted — the placeholder text that the tool must find\033[0m\n'
for v in \
  "DATA REDACTED" \
  "REDACTED FOR PRIVACY" \
  "Redacted for privacy" \
  "Data Redacted" \
  "NOT DISCLOSED" \
  "Non-Public Data" \
  "Withheld for Privacy ehf" \
  "Privacy service provided by Withheld for Privacy ehf" \
  "Domains By Proxy, LLC" \
  "Contact Privacy Inc." \
  "Identity Protect Limited" \
  "GDPR Masked" \
  "statutory masking enabled" \
  "N/A" "n/a" "none" "-" "" "   " "null" "XXXXX"
do
  assert_true "'$v' -> redacted" is_redacted "$v"
done

printf '\n\033[1mis_redacted — real data that the tool must keep\033[0m\n'
for v in \
  "101 Townsend St" \
  "Strada Lipscani 12" \
  "San Francisco" \
  "Bucharest" \
  "94107" \
  "horia@example.com" \
  "+40.721234567" \
  "Acme Holdings SRL" \
  "Apartment 4, 17 Bridge Road"
do
  assert_false "'$v' -> real data" is_redacted "$v"
done

printf '\n\033[1mclassify_network\033[0m\n'
assert_eq "Cloudflare -> data center"    datacenter  "$(classify_network 'CLOUDFLARENET, Cloudflare, Inc.')"
assert_eq "Hetzner -> data center"           datacenter  "$(classify_network 'Hetzner Online GmbH')"
assert_eq "OVH -> data center"               datacenter  "$(classify_network 'OVH SAS / OVH-CUST-12345')"
assert_eq "DigitalOcean -> data center"      datacenter  "$(classify_network 'DigitalOcean, LLC')"
assert_eq "AWS -> data center"               datacenter  "$(classify_network 'Amazon Technologies Inc. / AMAZON-EC2')"
assert_eq "generic datacentre -> data center" datacenter "$(classify_network 'Some Colocation Data Center Ltd')"
assert_eq "Comcast -> consumer"          consumer "$(classify_network 'Comcast Cable Communications, LLC')"
assert_eq "RCS-RDS -> consumer"          consumer "$(classify_network 'RCS & RDS SA')"
assert_eq "Digi Romania -> consumer"     consumer "$(classify_network 'DIGI ROMANIA S.A.')"
assert_eq "Vodafone -> consumer"         consumer "$(classify_network 'Vodafone Romania S.A.')"
assert_eq "Virgin Media -> consumer"     consumer "$(classify_network 'Virgin Media Limited')"
assert_eq "bare 'residential' -> hint"   home-hint "$(classify_network 'Generic ISP residential pool')"
assert_eq "DSL netname -> hint"          home-hint "$(classify_network 'NETNAME-ADSL-CUSTOMERS')"
assert_eq "empty -> unknown"             unknown  "$(classify_network '')"
assert_eq "opaque -> unknown"            unknown  "$(classify_network 'AS12345 NETBLOCK-4')"

# A data center network name can hold a word such as "customer" or "pool". The
# tool must still give the result "datacenter". If it does not, each OVH
# customer network gives a wrong HIGH result.
assert_eq "data center is stronger than home words" datacenter \
  "$(classify_network 'OVH SAS customer pool dynamic')"

printf '\n\033[1mip2int\033[0m\n'
assert_eq "0.0.0.0"         0          "$(ip2int 0.0.0.0)"
assert_eq "1.2.3.4"         16909060   "$(ip2int 1.2.3.4)"
assert_eq "104.16.0.0"      1745879040 "$(ip2int 104.16.0.0)"
assert_eq "255.255.255.255" 4294967295 "$(ip2int 255.255.255.255)"

printf '\n\033[1min_cidr4 — Cloudflare ranges\033[0m\n'
assert_true  "104.16.0.1 in 104.16.0.0/13"      in_cidr4 104.16.0.1   104.16.0.0/13
assert_true  "104.23.255.254 in 104.16.0.0/13"  in_cidr4 104.23.255.254 104.16.0.0/13
assert_false "104.24.0.1 NOT in 104.16.0.0/13"  in_cidr4 104.24.0.1   104.16.0.0/13
assert_true  "172.67.1.1 in 172.64.0.0/13"      in_cidr4 172.67.1.1   172.64.0.0/13
assert_false "172.72.0.1 NOT in 172.64.0.0/13"  in_cidr4 172.72.0.1   172.64.0.0/13
assert_true  "188.114.96.5 in 188.114.96.0/20"  in_cidr4 188.114.96.5 188.114.96.0/20
assert_false "188.114.112.5 NOT in /20"         in_cidr4 188.114.112.5 188.114.96.0/20

printf '\n\033[1min_cidr4 — edges\033[0m\n'
assert_true  "exact /32 match"          in_cidr4 8.8.8.8 8.8.8.8/32
assert_false "/32 mismatch"             in_cidr4 8.8.8.9 8.8.8.8/32
assert_true  "everything in /0"         in_cidr4 1.2.3.4 0.0.0.0/0
assert_false "no slash -> reject"       in_cidr4 1.2.3.4 1.2.3.4
assert_false "garbage ip -> reject"     in_cidr4 not-an-ip 1.2.3.0/24
assert_false "ipv6 passed to v4 -> reject" in_cidr4 2606:4700::1 1.2.3.0/24

# A home IP address that the tool must never put in a Cloudflare range.
assert_false "86.120.x.x not in any CF /13" in_cidr4 86.120.44.7 104.16.0.0/13

printf '\n\033[1mv6_prefix\033[0m\n'
assert_eq "full address"     "2606:4700" "$(v6_prefix 2606:4700:3033::6815:1)"
assert_eq "compressed"       "2606:4700" "$(v6_prefix 2606:4700::1)"
assert_eq "uppercase folded" "2a06:98c0" "$(v6_prefix 2A06:98C0::3)"
assert_eq "range net part"   "2606:4700" "$(v6_prefix 2606:4700::)"
assert_eq "non-CF address"   "2a02:2f0b" "$(v6_prefix 2a02:2f0b:b04a::1)"

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m%s passed, 0 failed\033[0m\n\n' "$PASS"
  exit 0
else
  printf '\033[31m%s passed, %s FAILED\033[0m\n\n' "$PASS" "$FAIL"
  exit 1
fi
