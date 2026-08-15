#!/usr/bin/env bash
#
# lib/classify.sh – the functions that classify data for domain-exposure-audit
#
# Each function in this file gives the same result for the same arguments. The
# functions use no network and no files. They read only the word lists in this
# file. These functions make the decisions of the tool, therefore they are in a
# separate file. The unit tests can then test them. See tests/test-classify.sh.
#
# SPDX-License-Identifier: MIT
#
# 1.3.0 CHANGES
#   - New function is_provider_soa_contact. The tool used an inline list in the
#     DNS check, and that list had no entry for Gandi. The tool then said that
#     hostmaster.gandi.net was possibly a personal mailbox, one time for each
#     Gandi domain. The list is now here, therefore a test can test it.

lc() { tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------------------
# Redaction detection
# ---------------------------------------------------------------------------
# The registrars do not use the same placeholder text. This list holds the text
# that gTLD registrars and privacy services use. If a value is in this list, the
# tool decides that the value is not real data.
#
# Be careful. This list makes the tool decide "redacted" more often than
# "real data". A wrong decision of "redacted" hides a real problem from you.
# Therefore each new pattern must be text that a real address cannot hold.
#
# The words "privacy" and "proxy" are a risk. A small number of streets in the
# United States have the name Privacy Lane. But each large privacy service puts
# one of these two words in the organization field, therefore the tool needs
# them.

REDACTION_PATTERNS='redacted|not disclosed|non-public|nonpublic|withheld|privacy|proxy|statutory masking|gdpr|masked|protected|data protected|whois agent|anonymize|anonymise|obscured|see contact-uri|please query|not available|unavailable|hidden|private by design|identity protect|domains by proxy|contact privacy|withheld for privacy'

# is_redacted VALUE -> code 0 if the value is placeholder text and not real data
is_redacted() {
  local v
  v="$(printf '%s' "${1:-}" | lc | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  [ -z "$v" ] && return 0
  case "$v" in
    -|--|---|n/a|na|none|null|nil|.|,|0|x|xx|xxx|xxxxx|"") return 0 ;;
  esac
  printf '%s' "$v" | grep -qE "$REDACTION_PATTERNS" && return 0
  # A relay address from a registrar is not your data.
  is_relay_email "$v" && return 0
  return 1
}

# ---------------------------------------------------------------------------
# A relay address from a registrar
# ---------------------------------------------------------------------------
# A registrar that redacts your data publishes its own relay address in
# place of your mailbox. A message to that address goes to you, but the address
# does not give your identity. Such an address is not a fault, therefore the
# tool must not write a result for it.
#
# One real example from Gandi:
#     8b63ef004b7b74c693720a8c46221f08-2266992@contact.gandi.net
# The part before the @ is a token of 32 hexadecimal digits and a number. No
# person chooses a mailbox name of that form.
#
# The tool makes the decision in two ways. First, a list of the domains that
# registrars use for this purpose. Second, the form of the part before the @.
# The second way finds the address of a registrar that this list does not hold.

RELAY_EMAIL_DOMAINS='contact\.gandi\.net|aa\.gandi\.net|gandi\.net|withheldforprivacy\.com|domainsbyproxy\.com|contactprivacy\.com|whoisguard\.com|whoisprivacyprotect\.com|privacyprotect\.org|privacyguardian\.org|identity-protect\.org|identityprotect\.org|anonymize\.com|tieredaccess\.com|withheld\.for\.privacy|proxy\.dreamhost\.com|namecheap\.com|porkbun\.com|registrar\.cloudflare\.com|domaincontact\.registrar\.cloudflare\.com|1and1-private-registration\.com|ovh\.net|privacy\.link|privatewhois\.net|protecteddomainservices\.com|buydomains\.com|networksolutionsprivateregistration\.com|pdr\.solutions|publicdomainregistry\.com'

# is_contact_uri VALUE -> code 0 if the value is an address of a web page
# Some registries publish the address of a contact form in the email field, and
# not an email address. One real example, from the registry of .la:
#     https://whois.nic.la/contact/humai.la/registrant
# Cloudflare does the same with the field contact-uri. This is the best possible
# condition, because the record holds no email address of any type.
is_contact_uri() {
  local v
  v="$(printf '%s' "${1:-}" | lc | sed 's/[[:space:]]//g')"
  [ -z "$v" ] && return 1
  case "$v" in
    http://*|https://*) return 0 ;;
  esac
  # A value with a slash and no @ is a path, and not an email address.
  case "$v" in
    *@*) return 1 ;;
    */*) return 0 ;;
  esac
  return 1
}

# is_relay_email VALUE -> code 0 if the value is a relay address
is_relay_email() {
  local v local_part domain_part
  v="$(printf '%s' "${1:-}" | lc | sed 's/[[:space:]]//g')"
  # A contact form is not your address either.
  is_contact_uri "$v" && return 0
  case "$v" in *@*) ;; *) return 1 ;; esac
  local_part="${v%@*}"
  domain_part="${v##*@}"

  # The first way: the domain belongs to a registrar or to a privacy service.
  printf '%s' "$domain_part" | grep -qE "^($RELAY_EMAIL_DOMAINS)$" && return 0

  # The second way: the part before the @ is a token that a program made.
  # A token of 16 hexadecimal digits or more, with a number after it or not.
  printf '%s' "$local_part" | grep -qE '^[0-9a-f]{16,}(-[0-9]+)?$' && return 0
  # A token of 24 characters or more, with no full stop and no underscore.
  printf '%s' "$local_part" | grep -qE '^[0-9a-z]{24,}$' && return 0
  # The forms that some services use.
  printf '%s' "$local_part" | grep -qE '(^|[.-])(protect|proxy|privacy|redacted|masked|withheld|abuse-c)([.-]|$)' && return 0

  return 1
}

# ---------------------------------------------------------------------------
# Network classification
# ---------------------------------------------------------------------------
# The RIR gives a text description of a network. It is in the organization
# name, the network name, or the description field of a whois answer for an IP
# address. This function decides which type of network it is.
#
# The order of the tests is important. The tool tests for a data center first.
# Many data center network names hold a word such as "customer" or "pool". If
# the tool tested for a home internet service first, it would give a wrong
# result for those networks.

RESIDENTIAL_PATTERNS='residential|broadband|dsl|adsl|vdsl|cable modem|fibre to the home|fiber to the home|ftth|dial-?up|dynamic ip|dynamic-ip|dynamic pool|subscriber|home user|end user|cpe|dhcp pool|access network|retail customer'
CONSUMER_ISP_PATTERNS='comcast|xfinity|verizon|frontier communications|centurylink|lumen|spectrum|charter communi|cox communi|optimum|altice|mediacom|windstream|starlink|t-mobile|at&t|sprint|deutsche telekom|vodafone|orange (s\.a\.|polska|romania|france)|telefonica|movistar|free sas|sfr|bouygues|virgin media|sky broadband|sky uk|bt group|british telecom|talktalk|plusnet|kpn|ziggo|telenet|proximus|telia|telenor|telstra|optus|rogers communi|bell canada|shaw communi|videotron|rcs & rds|rcs-rds|digi romania|upc |a1 telekom|magenta telekom|swisscom|sunrise communi|iliad|tim s\.p\.a|wind tre|jazztel|megafon|rostelecom|mts |beeline|turk telekom|ttnet|reliance jio|bharti airtel|bsnl|nos comunica|meo|vivo |claro |oi s\.a'
DATACENTER_PATTERNS='cloudflare|amazon|aws|ec2|google|gcp|azure|microsoft|oracle|digitalocean|linode|akamai|fastly|vultr|hetzner|ovh|scaleway|online s\.a\.s|contabo|netcup|ionos|1&1|godaddy|namecheap|dreamhost|bluehost|hostgator|siteground|kinsta|wpengine|heroku|render|railway|fly\.io|netlify|vercel|github|gitlab|bunny|stackpath|cdn77|leaseweb|softlayer|equinix|packet host|latitude\.sh|upcloud|kamatera|liquid web|rackspace|alibaba|aliyun|tencent|huawei cloud|yandex|selectel|servers\.com|datacamp|m247|worldstream|serverius|combell|transip|greenhost|snel\.com|tilaa|hostinger|namesilo|porkbun|gandi|infomaniak|netim|dinahosting|loopia|one\.com|hostpoint|cyso|is-interned|redpill|elastx|glesys|binero|obenetwork|domeneshop|nordu|funet|host ?europe|strato|mittwald|hosttech|nine\.ch|init7|iway|vshn|exoscale|safe ?host|opensystems|flow ?swiss|dedicated|colocation|colo |data ?cent(er|re)|hosting|cloud services|vps'

# classify_network DESCRIPTION -> datacenter, consumer, home-hint, or unknown
# ---------------------------------------------------------------------------
# The SOA contact
# ---------------------------------------------------------------------------
# The second field of an SOA record is an email address, and the first dot
# takes the place of the @ character. A managed DNS provider puts its own
# address there. A person who runs their own nameserver often puts a real
# mailbox there, and every person who queries the zone can then read it.
#
# is_provider_soa_contact CONTACT
#   0 -> the address belongs to a DNS provider or a registrar
#   1 -> the tool cannot recognise the address, therefore it is possibly yours
is_provider_soa_contact() {
  local v; v="$(printf '%s' "${1:-}" | lc | sed 's/\.$//')"
  [ -n "$v" ] || return 0
  case "$v" in
    *cloudflare.com|*awsdns*|*amazonaws.com|*azure*|*azure-dns*|\
    *googledomains*|*google.com|*googledomains.com|\
    *gandi.net|*ovh.net|*ovh.com|*hetzner.com|*hetzner.de|\
    *namecheap.com|*registrar-servers.com|*porkbun.com|*dnsimple.com|\
    *nsone.net|*dnsmadeeasy.com|*ultradns*|*akam.net|*akamai*|\
    *digitalocean.com|*linode.com|*vultr.com|*netlify.com|*vercel-dns.com|\
    *he.net|*dyn.com|*easydns.com|*njal.la|*inwx.de|*ionos.com|*1and1*|\
    *strato.de|*infomaniak.ch|*loopia.se|*one.com|*domeneshop.no|\
    *transip.nl|*combell.com|*rackspace.com|*constellix.com|\
    *registrar*|*registry*|*hostmaster.*|*dns-admin.*|*dnsadmin.*)
      return 0 ;;
  esac
  return 1
}

classify_network() {
  local d
  d="$(printf '%s' "${1:-}" | lc)"
  [ -z "$d" ] && { printf 'unknown'; return 0; }
  if printf '%s' "$d" | grep -qE "$DATACENTER_PATTERNS";   then printf 'datacenter'; return 0; fi
  if printf '%s' "$d" | grep -qE "$CONSUMER_ISP_PATTERNS"; then printf 'consumer';   return 0; fi
  if printf '%s' "$d" | grep -qE "$RESIDENTIAL_PATTERNS";  then printf 'home-hint';  return 0; fi
  printf 'unknown'
}

# ---------------------------------------------------------------------------
# Does a hostname give the name of a program?
# ---------------------------------------------------------------------------
# A name such as vault or grafana tells an attacker which program you use. A
# name such as australis or borealis tells an attacker nothing. The tool must
# not give the same advice for the two groups.

SOFTWARE_NAMES='pass|passwd|password|vault|bitwarden|vaultwarden|passbolt|keepass|keycloak|authelia|authentik|sso|auth|oauth|ldap|nas|synology|unraid|truenas|freenas|proxmox|pve|esxi|vcenter|xen|kvm|libvirt|docker|portainer|rancher|k8s|kube|kubernetes|openshift|nomad|consul|vault|grafana|prometheus|influx|graphite|zabbix|nagios|icinga|kibana|elastic|opensearch|splunk|loki|status|uptime|monitor|munin|cacti|netdata|jenkins|drone|gitlab|gitea|forgejo|git|svn|jira|confluence|redmine|mantis|sonar|nexus|artifactory|harbor|registry|plex|jellyfin|emby|kodi|sonarr|radarr|lidarr|prowlarr|bazarr|transmission|deluge|qbit|qbittorrent|rutorrent|sabnzbd|nzbget|nextcloud|owncloud|seafile|syncthing|resilio|webdav|samba|smb|nfs|ftp|sftp|tftp|vpn|wireguard|wg|openvpn|tailscale|zerotier|pihole|adguard|unbound|bind|pdns|dns|dhcp|radius|freeipa|zimbra|roundcube|rainloop|snappymail|mailcow|postfix|dovecot|exim|rspamd|spamassassin|phpmyadmin|adminer|pgadmin|mysql|mariadb|postgres|pgsql|redis|mongo|couch|influxdb|clickhouse|minio|s3|backup|borg|restic|duplicati|veeam|bacula|amanda|router|switch|firewall|pfsense|opnsense|openwrt|ubnt|unifi|mikrotik|idrac|ipmi|ilo|bmc|kvmip|camera|cam|nvr|dvr|frigate|zoneminder|shinobi|homeassistant|hass|homebridge|openhab|zwave|zigbee|mqtt|node-red|grocy|paperless|bookstack|wiki|dokuwiki|mediawiki|outline|hedgedoc|etherpad|cryptpad|jitsi|matrix|synapse|element|mattermost|rocketchat|discourse|admin|administrator|manage|management|panel|cpanel|whm|plesk|webmin|virtualmin|dashboard|portal|internal|intranet|private|secret|staging|stage|dev|devel|test|testing|qa|uat|preprod|sandbox|old|legacy|backup2|temp|tmp'

# reveals_software HOSTNAME -> code 0 if the first label is the name of a program
reveals_software() {
  local first
  first="$(printf '%s' "${1:-}" | lc | cut -d. -f1 | sed 's/[0-9]*$//; s/[-_]$//')"
  [ -z "$first" ] && return 1
  printf '%s' "$first" | grep -qxE "$SOFTWARE_NAMES" && return 0
  return 1
}

# any_reveals_software NAMES -> code 0 if one name or more names a program
# The names come on stdin, one on each line.
any_reveals_software() {
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    reveals_software "$n" && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# IPv4 CIDR tests, in bash only
# ---------------------------------------------------------------------------

ip2int() {
  local IFS=. a b c d
  read -r a b c d <<< "$1"
  printf '%s' "$(( (a << 24) | (b << 16) | (c << 8) | d ))"
}

# in_cidr4 IP CIDR -> code 0 if the IP address is in the CIDR range
in_cidr4() {
  local ip="$1" cidr="$2" net bits mask ipi neti
  case "$cidr" in */*) ;; *) return 1 ;; esac
  net="${cidr%/*}"; bits="${cidr#*/}"
  case "$ip" in *[!0-9.]*|"") return 1 ;; esac
  case "$net" in *[!0-9.]*|"") return 1 ;; esac
  case "$bits" in *[!0-9]*|"") return 1 ;; esac
  ipi="$(ip2int "$ip")"; neti="$(ip2int "$net")"
  if   [ "$bits" -le 0 ];  then mask=0
  elif [ "$bits" -ge 32 ]; then mask=4294967295
  else mask=$(( (4294967295 << (32 - bits)) & 4294967295 ))
  fi
  [ $(( ipi & mask )) -eq $(( neti & mask )) ]
}

# ---------------------------------------------------------------------------
# IPv6 coarse prefix
# ---------------------------------------------------------------------------
# Bash cannot do 128-bit arithmetic easily. Each Cloudflare IPv6 range is /29
# to /32. Therefore the tool compares the first two groups of hexadecimal
# digits. This gives the correct answer for each range except 2a06:98c0::/29.
# For that range, the tool can miss an address in the upper part.
#
# A miss gives the wrong answer "not Cloudflare". The tool then writes a MEDIUM
# result, and a person looks at it. This is the safe type of error.

v6_prefix() {
  printf '%s' "$1" | lc | awk -F: '{ printf "%s:%s", $1, $2 }'
}
