# The checks and their purpose

This document tells you about each check. For each check it gives you the
purpose, the correct result, and each other possible result.

Read this document one time before your first run. After that, read the section
for the result that you want to understand.

This document uses ASD-STE100 Simplified Technical English. See
[STE-COMPLIANCE.md](STE-COMPLIANCE.md).

- [The type of attacker](#the-type-of-attacker)
- [The three severity values](#the-three-severity-values)
- [Check 1 – Registration data (RDAP)](#check-1--registration-data-rdap)
- [Check 2 – DNS records](#check-2--dns-records)
- [Check 3 – Certificate Transparency](#check-3--certificate-transparency)
- [Check 4 – Hostnames and their addresses](#check-4--hostnames-and-their-addresses)
- [Check 5 – HTTP paths and headers](#check-5--http-paths-and-headers)
- [Check 6 – Copies in the archive](#check-6--copies-in-the-archive)
- [Check 7 – GPS data in images](#check-7--gps-data-in-images)
- [Check 8 – Shodan records](#check-8--shodan-records)
- [Check 9 – The checks that a person must do](#check-9--the-checks-that-a-person-must-do)
- [The changes from the baseline](#the-changes-from-the-baseline)

---

## The type of attacker

The tool assumes an attacker with these properties:

- The attacker knows your domain name and nothing more.
- The attacker has no name, no court order, and no money for a data broker.
- The attacker is patient. The attacker will look again later.

The tool looks for a path from the domain name to a physical location or to a
real identity. Three paths are important. The list starts with the path that
works most often.

1. **An IP address in a home network.** This is the most common path, and it is
   the strongest. You can redact a registration record. You cannot redact an A
   record that points to your house. An attacker can find the area of a home
   from an IP address, and sometimes the street.
2. **Registration data that is not redacted.** Most persons think of this path
   first. Modern gTLD registrars redact the data, therefore this path is usually
   closed. If the path is open, it is a serious risk.
3. **Data that you made public and then forgot.** An old contact page in an
   archive. GPS data in a photograph. A hostname that gives the name of your
   software.

Note the difference between these paths. You can close path 2 with one click.
Many persons do this, and then they stop work. Paths 1 and 3 hold the risk that
stays. For this reason, the tool does most of its work on paths 1 and 3.

This tool examines a domain. It does not examine you. Your name and your address
can be in business records, in an electoral register, in a data broker database,
in a stolen password list, or on your own social media pages. A clean result
from this tool tells you nothing about those sources.

---

## The three severity values

| Severity | Meaning | Exit bit |
|----------|---------|----------|
| **HIGH** | Your location or a secret is public now. Correct this today. | 2 |
| **MEDIUM** | Your position is weaker, or the tool could not get an answer. A person must look at the result. | 1 |
| **LOW** | The result is correct and useful. It is not a problem. Many LOW results are permanent. | none |

A LOW result sets no exit bit. Some LOW results are permanent facts. Your region
is public, and your hostnames stay in the certificate logs. These results come
back on each run. If they set a bit, the exit code would never be 0.

---

## Check 1 – Registration data (RDAP)

### Purpose

Find out if your name, street, city, postal code, email address, or telephone
number is in the public registration record.

### What the tool queries

1. **The IANA list** at `data.iana.org/rdap/dns.json`. The tool keeps this list
   for one week. The list gives the correct RDAP server for your TLD. Therefore
   the tool does not need another company to find the server.
2. **The RDAP server of the registry**, for the domain.
3. **The RDAP server of the registrar**. The tool finds this server in the
   `related` link of the answer from the registry.
4. **WHOIS on port 43**, if the `whois` program is present. The tool records the
   answer. It does not trust the answer.

Step 3 is the important step, and most persons do not do it. The ICANN
Registration Data Policy started in August 2025. After that date, a registry
publishes almost no data. Your contact data is at the **registrar**.

Be careful. If you query the registry only, you get a result that looks good but
means nothing. You decide that your data is redacted. But you asked a company
that never had the data.

The tool queries port 43 last, and it is old technology. ICANN stopped the WHOIS
rule for gTLDs on 28 January 2025. Some hundreds of registries then stopped the
service.

The answer `TLD is not supported` is the correct answer for most gTLDs today. It
is not an error, and the registry hides nothing. But if the service does answer,
it sometimes shows a field that RDAP hides. For this reason the tool sends one
query.

### Why this is important

An attacker with no name and no money can read a registration record. The record
is free, the answer is immediate, and the attacker needs no special knowledge.
In the past, this record gave the identity of persons who were careful in all
other ways.

Redaction is also the easiest correction in this document.

### The correct result

This is the result for a modern gTLD, at a registrar that redacts the data:

```
  status: clientTransferProhibited
  expires: 2027-03-14T00:00:00Z
  WHOIS on port 43: stopped for .wtf. This is correct after January 2025.
  · RDAP-REDACTED RDAP shows a registrant record. All the personal fields hold
    redacted data.
  · RDAP-REGION RDAP shows this region: ON. ICANN rules make this necessary.
```

You get `RDAP-REDACTED` or `RDAP-NO-REGISTRANT`. You also get `RDAP-REGION` and
`RDAP-COUNTRY`. You get no `PII-` result.

The region and the country are always public. ICANN rules make this necessary.
No registrar can hide them, and no configuration can remove them. The region is
the smallest area that you can hide.

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| `RDAP-NO-REGISTRANT` | RDAP has no registrant record. This is the best result. | LOW | None. |
| `RDAP-REDACTED` | The registrant record is present. All personal fields hold placeholder text. | LOW | None. |
| `PII-STREET` | Your street address is public. | **HIGH** | [Correct this today](REMEDIATION.md#pii-street-pii-city-and-pii-postcode). |
| `PII-CITY` | Your city is public. | **HIGH** | The same correction. |
| `PII-POSTCODE` | Your postal code is public. In most countries, a postal code gives a small group of streets. | **HIGH** | The same correction. |
| `PII-NAME` | Your name or your organization is public. Your identity is public, but not your location. | MEDIUM | You must decide. See the correction. |
| `PII-EMAIL` | A real email address is public. Programs will collect it in some days. | MEDIUM | Use the contact form of the registrar. |
| `RDAP-TEL` | A telephone number is public. It is usually the number of the registrar, and then it is safe. | LOW | Make sure that the number is not yours. |
| `RDAP-NO-RELATED` | The registry gave no link to the registrar. Therefore the tool could not check your contact data. | LOW | Query the RDAP server of your registrar yourself. This result is **not** a good result. |
| `RDAP-UNREADABLE` | RDAP gave no useful answer. This run checked nothing. | MEDIUM | Run the tool again. If the error continues, query the server yourself. |
| `RDAP-HTTP` | The registry gave an HTTP error code. | MEDIUM | The same action. |
| `RDAP-REGISTRAR` | The registry gave a link to the registrar, but that server gave no valid JSON. The results come from the registry record, which holds almost no data. | MEDIUM | Query the address yourself. A good result here has almost no value. |
| `WHOIS43-PII` | RDAP is redacted, but the old service on port 43 shows address fields. The two services do not agree. | **HIGH** | Send a message to your registrar. |
| `NO-TRANSFER-LOCK` | The status `clientTransferProhibited` is absent. A person can move your domain more easily. | MEDIUM | Set the lock. |
| `NO-UPDATE-LOCK` | A person can change your contact data without a second step. | LOW | This is optional. |
| `EXPIRY-SOON` | The registration stops in fewer than 45 days. | MEDIUM | Renew the registration. |
| `EXPIRED` | The registration stopped. | **HIGH** | Renew it now. Any person can register the domain and use your name. |
| `RDAP-NOTFOUND` | The registry says that the domain has no registration. | LOW | Look for an error in the name, or the registration stopped. |
| `RDAP-NO-SERVER` | RDAP has no server for this TLD, but WHOIS on port 43 shows a registration. Many ccTLDs are not in the IANA list. The tool reads the contact fields from WHOIS. | MEDIUM | Read the results for that WHOIS data. The same `PII-` codes apply. |
| `WHOIS-REDACTED` | The tool read the contact fields from WHOIS on port 43, and it found no personal data. | LOW | Nothing. |
| `RELAY-EMAIL` | The record holds a relay address from your registrar, and not your own address. | LOW | Nothing. This is the correct condition. |

### The limits of this check

The tool reads the data that is public. Your registrar keeps the full record. A
court can make the registrar give the record to another party. Redaction hides
the data. It does not delete the data.

The tool also cannot see the data in a historical WHOIS database. Such a
database can hold your address from the time before you redacted it. See
[Check 9](#check-9--the-checks-that-a-person-must-do).

---

## Check 2 – DNS records

### Purpose

Make a list of the records that your nameservers give to any person. Test the
records that stop false mail and stop a copy of your zone.

### What the tool queries

The tool queries these record types at the apex domain: `NS`, `SOA`, `A`,
`AAAA`, `MX`, `TXT`, `CAA`, and `DS`. It queries `TXT` at `_dmarc.<domain>`.
Then it asks each nameserver for a zone transfer.

### Why this is important

This check has four separate purposes.

**The SOA record holds an email address.** The second field of an SOA record is a
mailbox. The first dot in the field takes the place of the `@` character. If you
operate your own DNS and you put a personal address there, all persons who query
your zone can read it. A DNS company puts its own address there. For this reason,
the tool says nothing about the address of a known company.

**No SPF record and no DMARC record means that a person can send mail as you.**
This is not a location problem. But a domain with no mail rules is a free
identity for a false message. The attacker can send that message to you, and the
message shows your own domain as the sender.

**No CAA record means that any certificate authority can make a certificate for
your domain.** A CAA record is a DNS record. It gives the names of the
authorities that you permit. Without the record, the group of authorities that
can make a wrong certificate is "all authorities".

**An open zone transfer gives all your records to any person.** A zone transfer
gives each record that you have. This includes an internal hostname that has no
certificate and that no person can guess. This fault is rare at a DNS company,
and it is a serious risk. Therefore the tool sends one query for it.

### The correct result

This is the result for a domain at a DNS company, with no server behind it:

```
  NS    ns1.provider.net. ns2.provider.net.
  SOA   ns1.provider.net. dns.provider.net. 2411197596 10000 2400 604800 1800
  A     
  AAAA  
  Zone transfer: all nameservers refuse. This is correct.
```

An empty `A` field and an empty `AAAA` field are a **good** result. They show
that an attacker can find no origin server.

A new zone gives you `NO-CAA`, `NO-SPF`, and `NO-DMARC`. You can correct all
three in two minutes.

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| `AXFR-OPEN` | A nameserver permits a zone transfer to any person. All your records are public. | **HIGH** | [Correct this immediately](REMEDIATION.md#axfr-open). |
| `SOA-RNAME` | The SOA contact looks like a personal mailbox and not the mailbox of a company. | LOW | Use a role address. |
| `NO-CAA` | Any certificate authority can make a certificate for this domain. | MEDIUM | Add CAA records. |
| `NO-SPF` | The domain has no sender rules. A person can send mail as you. | MEDIUM | Add an SPF record. |
| `SPF-SOFT` | The SPF record ends with `~all` or `?all`. It does not stop a false message. | LOW | Use `-all` if no other host sends your mail. |
| `NO-DMARC` | The domain has no DMARC record. | MEDIUM | Add a DMARC record. |
| `DMARC-NONE` | The policy is `p=none`. It only makes reports and stops nothing. Many persons think that this policy protects them. | MEDIUM | Change the policy to `p=reject`. |
| `DMARC-QUARANTINE` | The policy is `p=quarantine`. This is good. `p=reject` is stronger. | LOW | This is optional. |
| `NO-DNSSEC` | The parent zone has no DS record. DNSSEC does not protect your answers. | LOW | Set DNSSEC if your DNS company has a simple control for it. |
| `DNS-NO-NS` | No NS record answers. The zone has a fault, or the domain has no registration. | MEDIUM | Correct this first. This fault also makes the other checks wrong. |

### The limits of this check

The tool sends each query to your default resolver. On a network with a local
resolver, a Pi-hole, or Tailscale, you can get a different answer. The public
internet gets the other answer.

This is the most common cause of a wrong result. Run the tool from a network
that is not your own, or give `dig` the address of a public resolver.

---

## Check 3 – Certificate Transparency

### Purpose

Make a list of each hostname under your domain that is in a public certificate
log. The list holds a name even if the name does not exist today.

### What the tool queries

The tool queries `crt.sh` for `%.<domain>`. It keeps the answer for 6 hours.

### Why this is important

Certificate Transparency is a public log. A program can add to the log, but no
person can remove from the log. Each certificate from each trusted authority
goes into the log.

You ask for a certificate for `vault.example.com`. Some seconds later, that
hostname is in a public log. It stays there for all time. There is no delete
function.

Most persons do not use this source when they examine their own domain. It is
better than a list of possible subdomain names, because it gives you names that
no person can guess.

The problem here is the **meaning** of a name, and not a technical fault. The
tool does not look for an IP address in this check. It looks at the information
in your names. The names `pass`, `vault`, `nas`, `proxmox`, `grafana`, and
`status` each give the name of a program.

You give this information to an attacker for free. The attacker now knows which
faults to try and which login page to copy. The attacker learned this without one
query to your server.

A name is in the log even if the name never had a public address. An ACME
program uses the DNS-01 method. It makes a TXT record, the authority reads the
record, and the program deletes the record some seconds later. The hostname
stays in the log for all time. The hostname never had a public address record.

### The correct result

One wildcard name and nothing more:

```
  The logs hold 2 names. 1 are wildcard names and 1 are single names.
    *.example.com
    example.com
```

A wildcard name is in the log as `*.example.com`. It gives no information about
one host. This is the reason to use a wildcard certificate on a personal domain.
The reason is not convenience. The reason is information.

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| no result | The log holds only the apex name and a wildcard name. | none | None. |
| `CT-HOSTNAMES` | The log holds single hostnames for all time. Read the list. Ask what each name tells an attacker. | LOW | You cannot remove them. [Give less information in the future](REMEDIATION.md#ct-hostnames). |
| `CT-MIXED` | You have a wildcard certificate, and you also make a certificate for each host. | LOW | Use the wildcard certificate only. |
| `CT-UNAVAILABLE` | Both services gave no data. | MEDIUM | This is almost always a request limit. Run the tool again after one hour. It is not a problem with your domain. |
| `CT-SECOND-SOURCE` | crt.sh gave no data, therefore the tool used CertSpotter. That service shows the certificates that are valid now, and not each certificate from the past. | LOW | Read the list of names with care. It is possibly shorter than the true list. Install `subfinder`, which reads about 30 sources. |

### The limits of this check

crt.sh limits the number of requests. `CT-UNAVAILABLE` is usually about crt.sh
and not about you.

Certificate Transparency holds the certificates of the public authorities only.
A certificate from your own private authority is not in the log. This is a good
reason to operate a private authority for your internal hosts.

---

## Check 3b – More hostnames from other programs

### Purpose

Find hostnames that Certificate Transparency does not give.

### Why this is important

Check 3 uses one service. A run on three real domains showed that crt.sh
answered `000`, `404`, and `503`. Therefore the tool had no real hostnames for
that run, and Check 4 used the word list only.

The tool now tries crt.sh three times, then it tries a second service
(CertSpotter). It can also use `subfinder`, which reads about 30 passive
sources. One service that stops requests is then not a serious problem.

### What the tool queries

| Program | What it gives | Default |
|---------|---------------|---------|
| `subfinder` | Hostnames from about 30 passive sources | The tool uses it if it is installed. Use `--no-enrich` to stop this. |
| `theHarvester` | Email addresses and hostnames from search engines | The tool uses it only with `--harvest`. |

Each program is passive. It sends no traffic to your hosts.

If no program is installed, the tool writes a message on the screen. It does not
write a result. The programs on your computer are not public data about your
domain, therefore a change in those programs must not make a change in the list
of results.

The tool keeps a name only if the name ends with your domain. It makes each name
lowercase, and it removes a dot at the end. Therefore a name from another domain
cannot enter Check 4.

`subfinder` does not use a source that needs an API key, because the tool does
not give it the `-all` option. Use `--enrich-all` to change this. Then subfinder
reads the keys in its own configuration file.

### The correct result

```
3b. More hostnames from other programs
  subfinder found 6 name(s)
```

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| `ENRICH-HOSTNAMES` | The other programs found hostnames that Certificate Transparency does not hold. The result names each one. | LOW | Read each name. A name such as pass, vault, nas, or status tells an attacker which software you use. A name is in this list even if it points to no address. |
| `HARVEST-EMAIL` | A public search found an email address for your domain. | MEDIUM | [See the correction](REMEDIATION.md#harvest-email). |
| `HARVEST-UNREADABLE` | theHarvester gave no file that the tool can read. | LOW | A search engine possibly stopped the requests. Run the tool again later. |

### The limits of this check

`theHarvester` sends many requests to search engines. A search engine can stop
the requests, and then the program gives no data. Some of its sources need an
API key. The results hold names of persons that are not correct, therefore a
person must read them.

`subfinder` reads passive sources. A source can be old. A name from this check
can be a name that you removed some years before.

---

## Check 4 – Hostnames and their addresses

**This check answers the first question in the README.**

### Purpose

Find each hostname under the domain that points to an address. Then decide if
each address is a proxy, a data center, or a house.

### What the tool queries

The tool makes a list of possible names. The list holds the apex name, each
single name from Check 3, each name from Check 3b, about 120 common names, and
the names in your `--wordlist` file.

The tool then queries `A` and `AAAA` for each name. It sends 8 queries at the
same time. Use `--parallel N` to change the number. Use `--parallel 1` for one
query at a time, which is slower but which uses less of your network.

The tool reads the status and the `A` records from one answer. Therefore it makes
two queries for each name and not three.

For each address that it finds, the tool does these steps:

1. It tests the address against the Cloudflare ranges. It gets the ranges from
   `cloudflare.com/ips-v4` and `cloudflare.com/ips-v6`, and it keeps them for
   one week.
2. If the address is not a Cloudflare address, the tool queries the RIR with
   `whois`. It gets the text description of the network.
3. It puts the network in one group: `datacenter`, `consumer`, `home-hint`, or
   `unknown`.

The tool asks the RIR about each address one time only, and it keeps the answer
for the run.

The tool writes one result for each **network**, and not one result for each
address. The addresses of one company are the same infrastructure, therefore one
result gives you the same information as many results. Five hostnames on four
addresses at two companies give two results. The screen shows each hostname and
each address.

The names from Certificate Transparency come first, and the word list comes
second. This order is important. The names from the log are real. The names from
the word list are estimates. A word list alone can miss the names that you use.

### Why this is important

Redaction hides your address in the registration record. A proxy hides the
address of your server. Neither one helps if one DNS record points to your
origin.

These are the common faults. The name `mail` often points to the real host,
because an HTTP proxy cannot carry mail. The names `direct` and `origin` point
to the real host by design. Also, a record that you made before you set up the
proxy can still point to the real host.

Step 3 is the important step. An origin at a data center company is an origin.
You must know about it, but it is not an emergency. An origin in the home
network of an internet service provider is a **physical address**. An attacker
can find the area of the home from the IP address, and sometimes the street.

This is the difference between a note about your servers and a risk to your
safety. For this reason, install the `whois` program.

### The correct result

The first correct result is that no name points to an address:

```
  No name points to an address.
  · NO-ADDRESS-RECORDS No name under this domain points to an IP address.
```

The second correct result is that each name points to the proxy:

```
    · example.com -> 104.21.3.4 [cloudflare proxy]
    · www.example.com -> 104.21.3.4 [cloudflare proxy]
  2 address(es) use a proxy. 0 address(es) are direct.
```

A name from the certificate log with the answer `NXDOMAIN` is also a correct
result. The tool shows it:

```
    · vault.example.com  NXDOMAIN. A certificate is present, but the name is
      not in public DNS.
```

This pair of facts is normal for a host on a private network. The certificate is
present, and the host has no public address. The ACME program used the DNS-01
method. The name is public, but the address is not public.

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| `NO-ADDRESS-RECORDS` | No name points to an address. An attacker can find no origin. | LOW | None. This is the best result. |
| `ORIGIN-RESIDENTIAL` | A name points to a home network. **An attacker can find the house from this address.** | **HIGH** | [Correct this today](REMEDIATION.md#origin-residential). |
| `ORIGIN-DATACENTER` | A name points to a data center. The address does not use the proxy. | LOW | This is not your home address. Use the proxy to make the server more difficult to attack. |
| `ORIGIN-UNKNOWN` | The address is not a Cloudflare address, and the RIR description is not clear. | MEDIUM | **Check this yourself.** The result means "the tool cannot decide". It does not mean "there is no problem". |
| `ORIGIN-NOWHOIS` | The address is not a Cloudflare address, and the `whois` program is absent. | MEDIUM | Install `whois` and run the tool again. |

### The limits of this check

The tool knows the Cloudflare ranges only. If you use Fastly, Bunny, or Akamai,
the tool puts your proxy addresses in the `datacenter` group. This result is
correct, but the words are different.

The IPv6 test compares two groups of hexadecimal digits. It does not do 128-bit
arithmetic. It can give the wrong answer "not Cloudflare". The tool then writes
a MEDIUM result, and a person reads it. This is the safe type of error.

The test for a home network reads text from the RIR. It does not know each small
internet service provider. Look at an `ORIGIN-UNKNOWN` result yourself if the
address is in your own country.

The word list is short by design. Certificate Transparency finds the real names.

---

## Check 5 – HTTP paths and headers

### Purpose

For each host that answers, find out if the web server gives source code,
secrets, user names, or the name of your origin server.

### What the tool queries

The tool sends one HTTPS `HEAD` request for the headers. Then it requests about
25 paths that often hold data. Three examples are `/.git/HEAD`, `/.env`, and
`/wp-json/wp/v2/users`. The tool does not run this check if no name points to an
address.

### Why this is important

This check finds a different type of problem. The path `/.git/HEAD` usually
means that any person can copy your full repository. The repository holds the
history. The history often holds a password that a person put there and later
removed.

The path `/.env` holds live secrets. The path `/wp-json/wp/v2/users` gives the
WordPress user names and the display names. The display name is often a real
name, on a site that gives no other personal data.

The headers are a smaller problem, but they are more difficult to see. The
headers `X-Real-IP`, `Via`, and `X-Served-By` sometimes give the name of the
origin server. Then the proxy does not protect you, and your DNS records make no
difference.

### The correct result

No name points to an address, therefore the tool sends no request:

```
  No name points to an address. Therefore the tool sends no HTTP request.
```

Or a live host gives only the files that must be public:

```
  example.com  HTTP 200  server: cloudflare
    /robots.txt -> 200. This path is public for a good reason.
    /sitemap.xml -> 200. This path is public for a good reason.
```

The files `robots.txt`, `sitemap.xml`, `security.txt`, and `humans.txt` must be
public. The tool shows them, but they are never a result.

But read your own `robots.txt` file. Each `Disallow` line is a public list of
the paths that you think are private.

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| `HTTP-EXPOSED` | A path such as `/.git/HEAD` or `/.env` gave the code 200. | **HIGH** | [Stop the access, then replace each secret](REMEDIATION.md#http-exposed). |
| `HTTP-AUTHORS` | A person can get a list of your WordPress user names. | MEDIUM | Stop the access to the path. |
| `HTTP-EXPOSED-MINOR` | Another path gave the code 200. | MEDIUM | Make sure that you want this path to be public. |
| `HTTP-ORIGIN-HEADER` | The headers can give the name of your origin server. | MEDIUM | Remove the headers at the proxy. |
| `HTTP-SERVER-VERSION` | The `Server` header holds a version number. | LOW | Remove the version number. This is a small problem. |
| the code 000 for each path | The name points to an address, but nothing answers on port 443. | none | This is normal for a host that is not a web server. |

### The limits of this check

The tool sends one request for each path. It uses no password, and it does not
read the pages of the site. It cannot find a problem behind a login page, on a
different port, or at a path that is not in the list.

---

## Check 6 – Copies in the archive

### Purpose

Find out if another party holds a copy of a page that you changed or deleted.

### What the tool queries

The tool queries the Wayback CDX service for each archived address under the
domain. It keeps the answer for 24 hours.

### Why this is important

Redaction hides your data from today. It does not remove your data from the
past. Each other check in this document tells you about your position now. This
check tells you about your position in the past. You cannot change the past.

The problem has a common form. A personal site starts with a real address on a
contact page. Some months later the person removes the page. The archive keeps
the old page and gives it to any person. The same problem happens with a
telephone number in a page footer, with an old legal notice, and with a work
history document.

### The correct result

This is the result for a domain that never had a public site:

```
  The archive holds no copy of this domain.
  · ARCHIVE-NONE The Wayback Machine holds no copy of this domain.
```

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| `ARCHIVE-NONE` | The archive holds no copy. | LOW | None. |
| `ARCHIVE-PRESENT` | The archive holds copies. They can show data that you removed. | MEDIUM | [Read the pages, then decide](REMEDIATION.md#archive-present). The number is not important. The content is important. |
| `ARCHIVE-UNAVAILABLE` | The CDX service gave no answer. | LOW | Run the tool again later. |

### The limits of this check

The Wayback Machine is one archive. These other services keep their own copies,
and each one has a different removal process: `archive.today`, the Google cache,
the Bing cache, Common Crawl, and many other programs that read web pages. The
tool does not query them.

The result `ARCHIVE-NONE` means that **the Wayback Machine** holds no copy.

---

## Check 7 – GPS data in images

Use the flag `--exif` for this check. It needs the `exiftool` program.

### Purpose

Find GPS data in the images on your site.

### What the tool queries

The tool gets the home page of the first live host. It finds up to 15 image
addresses, gets the images, and runs `exiftool -gps:all`.

### Why this is important

A telephone camera writes GPS data into an image file. This is the default
behaviour. Many site programs copy the file without a change, and the GPS data
stays in the file.

One photograph from your house then gives your position to a distance of some
metres. This is more exact than each other result in this document.

### The correct result

The tool reads the images and finds no GPS data:

```
  The tool read 4 image(s). It found no GPS data.
```

Most large sites remove the data when you send an image. A site that you build
yourself often does not remove the data.

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| no GPS data | The images that the tool read are correct. | none | None. |
| `EXIF-GPS` | One image or more holds GPS data. | **HIGH** | [Remove the data and send the image again](REMEDIATION.md#exif-gps). Also read the archive. It can hold the first image. |

### The limits of this check

The tool reads the home page only, and a maximum of 15 images. It reads the
`src` attribute only. It cannot find an image in a CSS background, in a gallery
that loads later, on another page, or in a directory with no link from the home
page.

For a site with many photographs, run `exiftool -gps:all` on your image
directory. That result is correct. This check is only a sample.

---

## Check 8 – Shodan records

This check needs the environment variable `SHODAN_API_KEY`.

### Purpose

Find out if a public scan database holds a record of the addresses from Check 4.

### What the tool queries

The tool queries `api.shodan.io/shodan/host/<ip>` for each address that is not a
Cloudflare address.

### Why this is important

Check 4 tells you that an address is public. This check tells you that a
database already holds a record of the address. The record gives the open ports,
the programs, and the text that each program sends.

This check changes "a person can find this" into "a database already holds
this". It also tells you what the attacker can read.

### The correct result

The tool has no address to query, or Shodan holds no record:

```
  All addresses use a proxy, therefore the tool queries nothing.
```

### The other possible results

| Result | Meaning | Severity | Action |
|--------|---------|----------|--------|
| no address to query | Each address uses a proxy. | none | None. |
| `is not in Shodan` | Shodan holds no record of the address today. | none | Note the word "today". |
| `SHODAN-INDEXED` | Shodan holds the address and the open ports. | MEDIUM | Read the list of ports. Stop each port that you do not need. |

### The limits of this check

Shodan is one scanner. Censys, ZoomEye, LeakIX, and BinaryEdge each make their
own records. An empty result from Shodan is weak evidence.

---

## Check 9 – The checks that a person must do

The tool does not do these checks. Each one needs an account, a paid service, a
CAPTCHA, or the decision of a person.

Be careful. A clean result from the tool does not include these checks.

### Historical WHOIS – the important one

Whoxy, DomainTools, SecurityTrails, and WhoisXML keep copies of registration
records from many years in the past. If your address was public at any time, one
of these services probably holds it. Redaction today does not remove it.

This is the most important check in this list.

```
https://www.whoxy.com/<domain>
https://viewdns.info/whoishistory/?domain=<domain>
https://securitytrails.com/domain/<domain>/history/a
```

Some of these services accept a removal request. This is more probable under
GDPR. Send the request. The result is different for each service.

### Reverse WHOIS

You register some domains with the same contact data. This links the domains
together. One domain that is not redacted then gives the identity of each other
domain with the same contact. One error on a `.us` registration can remove the
protection from all your other domains.

```
https://viewdns.info/reversewhois/
https://www.whoxy.com/reverse-whois/
```

### Other scan services and archives

Query Censys at `search.censys.io` for the addresses from Check 4. Also query
the SHA-256 value of your certificate from crt.sh. This sometimes finds an
origin server that sends your certificate from its own address.

Query `archive.today` for the pages that the Wayback Machine does not hold.

### Links between your sites

The same Google Analytics number or AdSense number on two sites links the two
sites together. These services show the links:
`dnslytics.com/reverse-analytics` and `builtwith.com/relationships`.

### A normal search

Search for your street address and your telephone number. Put quotation marks
around them. Search for `site:<domain>`. Search for the domain name in the text
sites and the stolen password lists.

No program does this as well as a person who reads the results.

---

## Check 10 – Why this tool does not scan a port

Nmap and other active scanners are not in this tool, and the tool will not add
them. This section gives the reason, and it tells you how to use Nmap yourself.

### Why the tool is passive

Each check in this tool reads a public database, or it queries DNS. The tool
sends no traffic to a host that it examines. This gives you three things:

1. **You can run the tool on any domain, and it is safe.** The
   `domains.conf` file holds a list of names. A wrong name in that file has no
   effect. An active scanner pointed at a name that you do not own is a
   different act.
2. **You need no permission.** A port scan of a network can be against the rules
   of your internet service provider, the rules of the network that you scan, or
   the law of your country.
3. **You do not scan another person.** Look at the results from a real run. The
   address `217.70.178.4` is the shared mail service of a hosting company. Many
   customers use it. A scan of that address is a scan of the company and of its
   other customers, and not a scan of your server.

### You already have the data

Check 8 queries Shodan. Shodan gives the open ports and the text that each
service sends, and you send no packet. Censys gives the same data. See
[Check 9](#check-9--the-checks-that-a-person-must-do).

### How to use Nmap yourself

Use Nmap on a server that you own, from a network where you have permission.

```bash
# The addresses that Check 4 found, from the JSON output of the tool
./domain-exposure-audit.sh --json example.com \
  | jq -r '.hosts[] | select(.classification != "cloudflare") | (.a + .aaaa)[]' \
  | sort -u > /tmp/my-addresses.txt

# Read the file first. Remove each address that you do not own.
cat /tmp/my-addresses.txt

# The 1000 most common ports, with the service names
sudo nmap -sS -sV --top-ports 1000 -iL /tmp/my-addresses.txt
```

Be careful. Read the file before you scan it. An address of a shared service
belongs to your hosting company, and not to you.

---

## The changes from the baseline

After the checks, the tool compares this run to the baseline. It reports the
differences in the fields that show your public data. These are the fields: the
certificate names, the apex addresses, the `NS` records, the `MX` records, the
`TXT` records, the hostnames, the results, and the status of your SPF record,
your DMARC record, and your personal data.

This is the part to read on each run after the first run.

Most results do not change. Your region is public for all time. Your hostnames
stay in the certificate logs for all time. On the tenth run, you will read the
same list again, and you will start to ignore the report. Then the monitor has
no purpose.

A change is always important. On a domain that you do not use for work, a change
means that another party did something.

| Change | Meaning |
|--------|---------|
| `ct_added` | A certificate authority made a certificate for a new name. You did this, or another person did this. |
| `a_added` | A name now points to an address. **This is the most important line.** |
| `hosts_added` | The same meaning as `a_added`. |
| `ns_removed` or `ns_added` | Your nameservers changed. If you did not change them, a person can now control your domain. |
| `mx_added` | Your mail route changed. The same reason. |
| `txt_added` | A new TXT record is present. This is a new domain verification, or a person proves an ownership that the person does not have. |
| `pii_changed` | The redaction status changed. This sometimes happens during a transfer, with no message to you. |
| `results_cleared` | You corrected something. Make sure, then make a new baseline. |

The pair `ns_removed` and `pii_changed` shows that a person took control of your
domain. A weekly run finds this pair. A manual check does not find it.

Make a new baseline only after you read the changes and you are satisfied:

```bash
./domain-exposure-audit.sh -c domains.conf              # read the changes
./domain-exposure-audit.sh -c domains.conf --baseline    # accept the changes
```
