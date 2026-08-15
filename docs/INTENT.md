# What the tool must do, how it does it, and how you know it worked

**Applies to version:** 1.3.0

This document has one section for each function of the tool. Each section gives
you three things:

1. **The purpose.** The question that the function must answer.
2. **The methods.** Each mechanism that the function uses, in the order of use.
3. **The test.** How you know that the function worked. How you know
   that it failed. How you know that the result is clean.

Read `CHECKS.md` for the meaning of each result code. Read `REMEDIATION.md` for
the correction of each result. Read this document to know why each check is here
and how to trust it.

This document uses ASD-STE100 Simplified Technical English. See
[STE-COMPLIANCE.md](STE-COMPLIANCE.md).

---

## The central problem

**A check that found nothing and a check that failed to look give the same
output, unless the tool separates them.**

This is the largest risk in a tool of this type. If crt.sh does not answer, the
list of hostnames is empty. An empty list looks the same as a domain with no
hostnames. The first condition is a fault of a service. The second condition is
a clean result. A person who cannot see the difference gets false confidence.

Each section below therefore gives three signals and not one:

| Signal | Meaning |
|--------|---------|
| **Clean** | The check ran, and it found no problem. |
| **Found** | The check ran, and it found something. |
| **Failed** | The check did not run, or a service gave no data. |

A result code exists for each **Failed** condition. Those codes are not
decoration. They are the test.

---

## The three rules that govern each decision

**Rule 1. A result describes the domain, not the tool.**

`CT-UNAVAILABLE` describes a gap in your knowledge of the domain, therefore it
is a result. "jq is absent" describes the computer that you run the tool on,
therefore it is an error message and exit code 8. This rule decides what becomes
a result code and what does not.

**Rule 2. Severity is about your ability to act, not about danger.**

| Severity | Meaning |
|----------|---------|
| **HIGH** | Personal data is public now, or an attacker can find your house. You can correct it, and you must. |
| **MEDIUM** | A real weakness that you can correct. |
| **LOW** | Information, or a condition that you cannot change. |

ICANN rules make your region public for all time. A hostname in a certificate
log stays there for all time. Each one is a LOW result for that reason.

A LOW result sets no bit in the exit code. If it did, the exit code would give
you no information, because a LOW result comes back on each run.

**Rule 3. The baseline is the product, not the scan.**

One run tells you your position today. Many results cannot change. If you read
the full list on each run, you will start to ignore the list. The list of
changes is the new information. Each design decision protects the quality of
that list.

---

## Check 1 – Registration data

### Purpose

This check does three separate jobs against one set of queries.

1. **Find personal data that your registration publishes.** A street address in
   a registration record is the shortest path from a domain name to your house.
2. **Watch the date that the registration stops.** A domain that stops is a
   domain that another person can register and use with your name.
3. **Test the two locks that stop a hijack.** `clientTransferProhibited` stops a
   move to another registrar. `clientUpdateProhibited` stops a change to your
   contact data.

### Methods

The tool uses four methods, in this order. Each one is a fallback for the one
before it.

1. **The IANA bootstrap list.** The tool reads the list of RDAP servers, and it
   finds the server for your TLD. The list stays in the cache for 168 hours.
2. **rdap.org.** If the IANA list is not available, the tool uses this service
   as a proxy. It says so in the output, because the answer then comes from a
   third party.
3. **The registrar RDAP server.** The registry record holds almost no data. The
   registrar record holds the contact fields. The tool reads the `related` link
   in the registry answer, and it queries the registrar server.
4. **WHOIS on port 43.** Some TLDs have no RDAP server. The `.la` registry is
   one example. The tool reads port 43 for those domains, and the check is then
   complete by a different method.

The tool then reads three more fields from the same answer.

- **The expiry date.** The tool compares it against today. Under 45 days gives
  `EXPIRY-SOON`. A date in the past gives `EXPIRED` with HIGH severity.
- **The status list.** The tool accepts the form with spaces from RFC 9083 and
  the EPP form, because a registry can use either one.
- **The region and the country.** ICANN rules make these public. No registrar
  can hide them, therefore they are LOW.

The tool classifies each contact field with three functions from
`lib/classify.sh`:

| Function | Question |
|----------|----------|
| `is_redacted` | Is the field a placeholder, or is it empty? |
| `is_relay_email` | Is the address a relay address from the registrar? |
| `is_contact_uri` | Is the field the address of a web page and not a mailbox? |

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | `RDAP-REDACTED`, `WHOIS-REDACTED`, `RELAY-EMAIL`, `CONTACT-FORM` |
| **Found, personal data** | `PII-STREET`, `PII-CITY`, `PII-POSTCODE` (HIGH), `PII-NAME`, `PII-EMAIL`, `WHOIS43-PII` |
| **Found, the registration stops** | `EXPIRED` (HIGH), `EXPIRY-SOON` |
| **Found, a lock is absent** | `NO-TRANSFER-LOCK`, `NO-UPDATE-LOCK` |
| **You cannot change it** | `RDAP-REGION`, `RDAP-COUNTRY`, `RDAP-TEL` |
| **Failed** | `RDAP-UNREADABLE`, `RDAP-HTTP`, `RDAP-NOTFOUND` |
| **Partial** | `RDAP-REGISTRAR`, `RDAP-NO-RELATED`, `RDAP-NO-REGISTRANT` |
| **A different method** | `RDAP-NO-SERVER`, and the tool reads WHOIS on port 43 |

**The trap in this check.** `RDAP-REGISTRAR` means that the registry gave the
address of the registrar server, and that server gave no useful answer. The
contact results then come from the registry record only. **A clean result under
that condition has almost no value**, because a registry publishes almost no
data. The tool gives this result MEDIUM severity for that reason.

`RDAP-NO-REGISTRANT` needs the same care. The record holds no registrant object
at all. That looks clean, and it possibly means that the tool cannot see the
object.

**A second test, outside the tool.** Query the registrar RDAP server
yourself and read the answer:

```bash
curl -sL -H 'Accept: application/rdap+json' <registrar-rdap-address> | jq .
```

---

## Check 2 – DNS records

### Purpose

Answer two different questions with one set of queries.

1. Can a person send mail that shows your domain as the sender?
2. Does a public record hold a personal mailbox?

### Methods

1. **Query each record type.** The tool reads NS, SOA, A, AAAA, MX, TXT, CAA, DS,
   and the TXT record at `_dmarc`.
2. **Try a zone transfer.** The tool sends an AXFR request to each
   nameserver. This is a positive test: a success is unambiguous.
3. **Read the SOA contact.** The second field of an SOA record is an email
   address, and the first dot takes the place of the `@` character.
   `is_provider_soa_contact` compares the address against 48 patterns that cover
   the DNS providers and the registrars.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | no result for SPF, DMARC, or CAA. `SOA-PROVIDER` |
| **Found, the zone is open** | `AXFR-OPEN` (HIGH) |
| **Found, mail** | `NO-SPF`, `NO-DMARC`, `NO-CAA`, `DMARC-NONE`, `SPF-SOFT`, `DMARC-QUARANTINE` |
| **Found, a contact** | `SOA-RNAME` |
| **Optional** | `NO-DNSSEC` |
| **Failed** | `DNS-NO-NS` |

**How the tool separates "no record" from "no answer".** Almost every result in
this check is about an absent record. An absent record and a failed query give
the same empty output.

The NS query is the control. If the NS query gives an answer, DNS works, and
each other absent record is a true absence. If the NS query gives no answer,
`DNS-NO-NS` fires, and you must not trust the other results from this check.

**A known weakness.** The tool does not separate a query that fails from a
record that is absent, for each record type on its own. The NS control covers
the common condition, which is a network fault or a broken zone. It does not
cover a fault in one record type only.

---

## Check 3 – Certificate Transparency

### Purpose

Find the hostnames that your certificates published. Every public certificate
goes into a public log, and the log keeps each name for all time. This is the
best source of true hostnames, and it is better than any word list.

### Methods

1. **crt.sh.** The tool tries three times. It waits 5 seconds and then 15
   seconds between the tries, because a code of 502 or 503 means that the
   service has too much work.
2. **The cache.** Each answer stays in the cache for 168 hours. **When a request
   fails, the tool uses the answer in the cache even if the answer is older than
   that time.** The cache is not under the state directory, therefore the command
   `rm -rf state` keeps it.
3. **certspotter.** If crt.sh gives no valid answer, the tool queries this second
   service. It reads the same public logs.
4. **A test of the answer, and not of the HTTP code.** An empty list is not an
   answer. The tool accepts a list with one item or more items only.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | no result. The log holds the apex name and a wildcard name only. |
| **Found** | `CT-HOSTNAMES`, `CT-MIXED` |
| **Failed** | `CT-UNAVAILABLE` |
| **Partial** | `CT-SECOND-SOURCE` |

**`CT-SECOND-SOURCE` is a partial result and not a clean one.** certspotter
shows the certificates that are valid now. It does not show each certificate
from the past. The list of names is possibly shorter than the true list.

**The message for `CT-UNAVAILABLE` gives you the next action.** It names the
HTTP code of each of the two services, and it separates two conditions:

| Condition | Your action |
|-----------|-------------|
| A code of 000, 502, or 503 | Run the tool again later. The service has too much work. |
| certspotter gives 200 with an empty list | A later run gives the same answer. Use `subfinder`. |

---

## Check 3b – More hostnames from other programs

### Purpose

Find the hostnames that Certificate Transparency does not hold. A host with no
public certificate is not in the log.

### Methods

1. **subfinder**, if it is installed. It reads about 30 passive sources. The tool
   keeps only the names that end with your domain.
2. **theHarvester**, only with the flag `--harvest`. It searches search engines
   for hostnames and email addresses. It is not automatic, because it sends many
   requests and a search engine can stop them.
3. **A test of each name.** `reveals_software` holds a list of about 200 program
   names. A name such as `vault` or `grafana` tells an attacker which program you
   use. A name such as `australis` tells an attacker nothing.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | no result, and the message says that each name is already in the log |
| **Found** | `ENRICH-HOSTNAMES`, `HARVEST-EMAIL` |
| **Failed** | `HARVEST-UNREADABLE` |

**A message that must be true.** When Certificate Transparency gives no data, the
tool holds no list to compare against. It then says that the comparison was not
possible. It does not say that each name is already in the log, because that
statement would be false.

**The value of `ENRICH-HOSTNAMES` depends on the names.** The result says whether
a name in the list gives the name of a program. Four constellation names give an
attacker almost nothing. One name such as `vault` tells an attacker which login page
to copy.

---

## Check 4 – Hostnames and their addresses

### Purpose

**This is the check that the tool exists for.** Find out if any name under your
domain points to an address on a home internet connection. Such an address gives
an attacker your approximate house.

### Methods

1. **Assemble the candidate names** from four sources: the names from
   Certificate Transparency, the names from the other programs, a default list of
   138 words, and your own word list from `--wordlist`.
2. **Resolve each name.** A helper script resolves one name. `xargs` starts many
   copies of the helper at the same time. The default is 8 at the same time, and
   `--parallel 1` gives one query at a time.
3. **Test each address against the proxy ranges.** The tool reads the published
   Cloudflare ranges and keeps them in the cache for 168 hours. `in_cidr4` and
   `v6_prefix` do the comparison.
4. **Query WHOIS for each address that is not behind a proxy.** The tool reads
   the fields `orgname`, `netname`, `descr`, and `owner`.
5. **Classify the description.** `classify_network` gives one of four answers:
   a data center, a home internet service, a hint of a home service, or unknown.
   A data center word is stronger than a home word, because a data center often
   holds the word `net` or `dsl` in a network name.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | `ORIGIN-DATACENTER`, `NO-ADDRESS-RECORDS`, or each address is behind a proxy |
| **Found** | `ORIGIN-RESIDENTIAL` (HIGH) |
| **Failed** | `ORIGIN-NOWHOIS` |
| **Cannot decide** | `ORIGIN-UNKNOWN` |

**`ORIGIN-UNKNOWN` means "the tool cannot decide". It does not mean "there is no
problem".** The tool gives it MEDIUM severity for that reason. Look at the
network yourself.

**The completeness of this check depends on check 3.** If `CT-UNAVAILABLE` is in
the results, check 4 used the word list only. The word list is short, therefore
the tool possibly missed a hostname. The message for `CT-UNAVAILABLE` says this.

**A second test.** The output gives three numbers: how many addresses
use a proxy, how many are direct, and how many networks the tool found. Each
address counts one time, even if two hostnames share it.

---

## Check 5 – HTTP paths and headers

### Purpose

Find a file that your web server publishes and must not publish. Find a header
that gives information to an attacker.

### Methods

1. **Request 29 paths.** The list holds `/.git/HEAD`, `/.env`, `/backup.sql`,
   `/.ssh/id_rsa`, `/wp-json/wp/v2/users`, and other paths of the same class.
2. **Separate a serious path from a minor path.** A path that holds credentials,
   a repository, or a database gives `HTTP-EXPOSED` with HIGH severity. Each
   other path gives `HTTP-EXPOSED-MINOR`.
3. **Read the headers.** The tool reads the `Server` header for a version number,
   and it looks for a header that names your origin server.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | no result |
| **Found** | `HTTP-EXPOSED` (HIGH), `HTTP-EXPOSED-MINOR`, `HTTP-AUTHORS`, `HTTP-ORIGIN-HEADER`, `HTTP-SERVER-VERSION` |
| **Not run** | the message says that no name points to an address |

**This check depends on check 4.** If no name points to an address, the tool
sends no HTTP request. That is correct, and the output says so. Do not read the
absence of a result as a clean result under that condition.

---

## Check 6 – Copies in the archive

### Purpose

Find data that you removed from your site and that is still public. A page that
you deleted in 2016 can still hold a telephone number.

### Methods

The tool queries the Wayback CDX service, and it counts the copies. It gives you
the date of the first copy and the date of the last copy.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | `ARCHIVE-NONE` |
| **Found** | `ARCHIVE-PRESENT` |
| **Failed** | `ARCHIVE-UNAVAILABLE` |

**The known limit of this check, and it is large.** The tool counts the copies.
**It does not read them.** `ARCHIVE-PRESENT` therefore tells you that an archive
exists, and it cannot tell you what the archive holds.

A domain with 88 copies from 2006 needs a person to read the pages. No result
code can replace that work. The result gives you the address to start:

```
https://web.archive.org/web/*/<domain>/*
```

---

## Check 7 – GPS data in the images

### Purpose

Find a photograph on your site that holds the position of your house.

### Methods

The tool reads your home page, it finds the image addresses, and it runs
`exiftool` against each image. The check needs the flag `--exif`, and it needs
`exiftool` on the computer.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | no result |
| **Found** | `EXIF-GPS` (HIGH) |
| **Not run** | the flag is absent, or `exiftool` is absent |

**This check reads the home page only.** An image on a different page is not in
the test.

---

## Check 8 – Shodan records

### Purpose

Find out if a public scan service holds a record of your origin server.

### Methods

The tool queries the Shodan API for each address that is not behind a proxy. The
check needs the variable `SHODAN_API_KEY`.

### The test

| Signal | Result codes |
|--------|--------------|
| **Clean** | no result |
| **Found** | `SHODAN-INDEXED` |
| **Not run** | the key is absent, or each address uses a proxy |

---

## The baseline and the list of changes

### Purpose

**This function makes the tool a monitor and not a scanner.** Many results cannot
change, and they come back on each run. The list of changes is the new
information.

### Methods

1. **The snapshot.** Each run writes a JSON document that holds the state of each
   check and each result.
2. **The baseline.** The flag `--baseline` copies the snapshot to
   `baseline.json`.
3. **The comparison.** The tool compares the new snapshot against the baseline.
   It reports a new hostname, a new address, a new certificate name, a change to
   a DNS record, and a change to the registration.
4. **The history.** The tool keeps the last 120 snapshots.
5. **The guard.** `--baseline` writes nothing after a run with a missing service.

### The test

**The guard is the test.** These four results stop a baseline:

| Result | The gap in the run |
|--------|--------------------|
| `CT-UNAVAILABLE` | check 3 found no name, and check 4 used the word list only |
| `ARCHIVE-UNAVAILABLE` | check 6 did not read the archive |
| `RDAP-UNREADABLE` | check 1 did not read the registration |
| `HARVEST-UNREADABLE` | check 3b did not read the output of theHarvester |

A baseline from such a run makes the next run show the recovery of the service as
though it were news about your domain. The tool gives a warning that names each
service. Use `--force-baseline` to write the baseline anyway.

`CT-SECOND-SOURCE` does **not** stop a baseline. crt.sh fails often, and
certspotter gives a good answer.

**The exit code does not change under this condition**, because a failure of a
service is not a result about your domain. This follows Rule 1.

---

## The cache

### Purpose

Protect the tool against a service that fails, and reduce the load on a free
service.

### Methods

1. Each answer goes into a file, and the file name comes from the URL.
2. A fresh file is one that is newer than `DEA_CT_CACHE_HOURS`. The default is
   168 hours.
3. **When a request fails and a file is in the cache, the tool uses the old
   file**, even if the file is older than that time. The output shows
   `404(stale-cache)` for this condition.
4. The cache is at `$XDG_CACHE_HOME/domain-exposure-audit`. It is **not** under
   the state directory.

### The test

The output shows `200(cached)` for a fresh file, and `404(stale-cache)` for the
fallback. Each code that holds a word is a code from the cache and not from a
server.

**Why the location matters.** The documented way to make a new baseline is
`rm -rf state`. Version 1.2.1 and each earlier version kept the cache inside that
directory. The command therefore deleted the protection against a crt.sh outage,
minutes before the run that needed it.

---

## The classification library

### Purpose

Hold each decision of the tool in one file that a test can test with no network.

### Methods

`lib/classify.sh` holds 11 functions. Each one takes a string and gives an exit
code or a word. No function sends a request. The table below gives the seven
functions that make a decision. The other four are helpers: `lc`, `ip2int`,
`any_reveals_software`, and `v6_prefix`.

| Function | Decision |
|----------|----------|
| `is_redacted` | Is this contact field a placeholder? |
| `is_relay_email` | Is this address a relay address from a registrar? |
| `is_contact_uri` | Is this field a web page and not a mailbox? |
| `is_provider_soa_contact` | Does this SOA contact belong to a DNS provider? |
| `classify_network` | Is this network a data center or a home service? |
| `reveals_software` | Does this hostname give the name of a program? |
| `in_cidr4` | Is this address in this range? |

### The test

**163 unit tests in `tests/test-classify.sh`.** They hold real data: the contact
form address from the record of `humai.la`, 13 real SOA contacts of DNS
providers, real Cloudflare ranges, and real relay addresses from six registrars.

A decision that a test cannot test is a decision in the wrong file.

---

## The exit code

### Purpose

Give a result to a program, and not to a person. `cron` and `systemd` read this
number.

### Methods

The code is a bitmask, therefore one number can show more than one result.

| Bit | Meaning |
|-----|---------|
| 1 | The tool found MEDIUM results. |
| 2 | The tool found HIGH results. |
| 4 | The tool found a change from the baseline. |
| 8 | The tool failed. A tool is absent, or the tool cannot write. |

### The test

**A LOW result sets no bit.** This is deliberate. A LOW result comes back on each
run, therefore a bit for LOW would make the exit code useless.

**Bit 8 replaces the mask.** A fatal condition gives 8 and not 9 or 10, because
the tool stops before it can complete the results.

---

## The notification

### Purpose

Tell you about a change without a person who reads the output.

### Methods

The tool sends a short summary to the command in `--notify` or `DEA_NOTIFY_CMD`.
It sends the summary when the data changed, or when the tool found a HIGH result.

### The test

A test in `tests/test-parsing.sh` compares two line numbers. The notify block
must come before the exit mask in the function.

**Why a test guards a line number.** Each version up to 1.2.1 held an
unconditional `return 0` above the notify block. The block was unreachable,
therefore the notify command never ran in any version. The flag, the variable,
and the example script all had no effect, and no test found this.

---

## The language

### Purpose

Make each result readable by a person who is tired, or worried, or not a native
speaker of English.

### Methods

Each document and each message uses ASD-STE100 Simplified Technical English. The
rules limit the words, the tenses, and the length of each sentence.

### The test

`tests/test-ste.sh` reads 16 files. It gives a failure for a word that is not
approved, an `-ing` form, a complex tense, a sentence that is too long, and a
paragraph with too many sentences. The current state is **0 failures**.

---

## What the tool does not do

This list is as important as the list of functions. Each item is a deliberate
decision.

| The tool does not | Why |
|-------------------|-----|
| Read the pages in the archive | The count is automatic. The reading needs a person. |
| Query a historical WHOIS service | Each one needs an account. |
| Query a people-search database or a data broker | Each one needs an account. `REMEDIATION.md` gives you the addresses. |
| Read a private Certificate Transparency log | Only the public logs are public. |
| Test a login page or send a password | The tool audits public data. It is not a scanner of faults. |
| Change your DNS, your registration, or your server | The tool reads. `REMEDIATION.md` tells you what to change. |
| Give a result about the computer that runs it | Rule 1. A missing program is an error message and exit code 8. |

---

## A summary of each test

| Check | It worked | It failed | The result is clean |
|-------|-----------|-----------|---------------------|
| 1 Registration, personal data | a contact result of any type | `RDAP-UNREADABLE`, `RDAP-HTTP`, `RDAP-NOTFOUND` | `RDAP-REDACTED`, `RELAY-EMAIL`, `CONTACT-FORM` |
| 1 Registration, the expiry date | a date in the output | the date field is empty | no result |
| 1 Registration, the locks | a status list in the output | the status list is empty | no result |
| 2 DNS | the NS query gives an answer | `DNS-NO-NS` | no mail result, `SOA-PROVIDER` |
| 3 Certificate Transparency | `the tool used crt.sh` | `CT-UNAVAILABLE` | no result |
| 3b Other programs | a count of the names | `HARVEST-UNREADABLE` | each name is in the log |
| 4 Addresses | a count of the addresses and the networks | `ORIGIN-NOWHOIS` | `ORIGIN-DATACENTER`, `NO-ADDRESS-RECORDS` |
| 5 HTTP | an HTTP code for each name | check 4 found no address | no result |
| 6 Archive | a count of the copies | `ARCHIVE-UNAVAILABLE` | `ARCHIVE-NONE` |
| 7 Images | the flag `--exif` and `exiftool` | the tool says the program is absent | no result |
| 8 Shodan | the variable `SHODAN_API_KEY` | the tool says the key is absent | no result |
| Baseline | the tool wrote the baseline | the guard gives a warning | no change from the baseline |

---

*End of document.*
