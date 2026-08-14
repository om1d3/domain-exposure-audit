# ASD-STE100 compliance record

This project uses ASD-STE100 Simplified Technical English. This document records
the decisions that make that possible, and the limits of the result.

ASD-STE100 Rule 1.5 tells you to keep a list of the Technical Names that your
project uses. Rule 1.6 tells you to do the same for Technical Verbs. Sections 3
and 4 of this document are those lists.

- [1. Scope](#1-scope)
- [2. Rules applied](#2-rules-applied)
- [3. Technical Names](#3-technical-names)
- [4. Technical Verbs](#4-technical-verbs)
- [5. Approved substitutions](#5-approved-substitutions)
- [6. Known deviations](#6-known-deviations)
- [7. How to check compliance](#7-how-to-check-compliance)

---

## 1. Scope

STE applies to all text that a person reads:

- `README.md`, and all files in `docs/`
- the help text of the tool
- all console messages
- all result messages
- all comments in the shell scripts
- `domains.conf.example` and the files in `examples/`

STE does not apply to:

- code identifiers, such as variable names and function names
- JSON keys
- command syntax and file paths
- text that comes from other systems, such as HTTP headers or RDAP fields

STE is a specification for natural language. A variable name is not natural
language. Therefore the code keeps names such as `DEA_STATE_DIR`.

---

## 2. Rules applied

### Words (Section 1)

| Rule | Application |
|------|-------------|
| 1.1 | Use approved words, Technical Names, and Technical Verbs only. |
| 1.2 | Use one word for one meaning. |
| 1.3 | Use one part of speech for one word. |
| 1.4 | Do not use idioms or metaphors. |
| 1.5 | Keep the Technical Names list. See Section 3. |
| 1.6 | Keep the Technical Verbs list. See Section 4. |

### Noun phrases (Section 2)

| Rule | Application |
|------|-------------|
| 2.1 | Use a maximum of three nouns together. |
| 2.2 | Add hyphens, or write the phrase again, if the meaning is not clear. |
| 2.3 | Do not remove the articles `the` and `a`. |

### Verbs (Section 3)

| Rule | Application |
|------|-------------|
| 3.1 | Use the infinitive, the imperative, the simple present, the simple past, the simple future, and the past participle as an adjective. |
| 3.2 | Use the active voice in instructions. |
| 3.3 | Use the active voice in descriptions, if this is possible. |
| 3.4 | Do not use the `-ing` form, except in a Technical Name. |
| 3.5 | Do not use complex tenses. Write `the tool found` and not `the tool has found`. |

### Sentences (Section 4)

| Rule | Application |
|------|-------------|
| 4.1 | Instructions have a maximum of 20 words. |
| 4.2 | Descriptions have a maximum of 25 words. |
| 4.3 | Write one instruction in one sentence. |
| 4.4 | Use vertical lists for complex text. This project uses many lists and tables for this reason. |
| 4.5 | A paragraph has a maximum of 6 sentences. |
| 4.6 | Write about one topic in one paragraph. |

### Punctuation

- Do not use the oblique (`/`) in text. Use `or`, or write the words again.
  The oblique is permitted in a file path or a command.
- Do not use `&`. Use `and`.
- Do not use contractions. Write `do not` and not `don't`.
- Do not use `e.g.` or `i.e.`. Use `for example` and `that is`.
- Do not use the em-dash. Not in a heading, not in a table, not in a sentence.
- Use the en-dash only as a separator after a title or a heading, for example
  `Check 1 – Registration data`. A dash inside a sentence hides the
  relationship between the two parts of the sentence. Use a comma, use a colon,
  or write two sentences.

---

## 3. Technical Names

STE permits a Technical Name if the name is in an approved category. Each name
below is a noun that this project needs. The category is from ASD-STE100
Section 1, Rule 1.5.

### Names of organizations and standards

`ASD-STE100`, `ICANN`, `IANA`, `RIR`, `CA` (certificate authority),
`Cloudflare`, `Identity Digital`, `Let's Encrypt`, `Internet Archive`,
`Wayback Machine`, `crt.sh`, `Shodan`, `Censys`, `Whoxy`, `SecurityTrails`,
`GDPR`, `RFC 7505`

### Names of technical concepts and data objects

`domain`, `subdomain`, `hostname`, `apex`, `zone`, `record`, `nameserver`,
`resolver`, `registry`, `registrar`, `registrant`, `certificate`,
`certificate authority`, `Certificate Transparency`, `wildcard certificate`,
`log`, `snapshot`, `baseline`, `result`, `severity`, `IP address`,
`network`, `port`, `header`, `path`, `secret`, `credential`, `archive`,
`metadata`, `coordinate`, `attacker`, `proxy`, `origin`, `origin server`,
`relay address`,
`data center`, `home internet service`, `bitmask`, `exit code`, `timer`

### Names of protocols, formats, and software

`RDAP`, `WHOIS`, `DNS`, `DNSSEC`, `SPF`, `DMARC`, `DKIM`, `CAA`, `SOA`,
`AXFR`, `TXT`, `MX`, `NS`, `TLS`, `HTTP`, `HTTPS`, `JSON`, `EXIF`, `GPS`,
`ACME`, `DNS-01`, `TLD`, `gTLD`, `ccTLD`, `CIDR`, `IPv4`, `IPv6`, `CDN`,
`VPS`, `VPN`, `bash`, `curl`, `dig`, `jq`, `whois`, `exiftool`, `nginx`,
`Apache`, `WordPress`, `systemd`, `cron`, `git`, `Tailscale`, `WireGuard`,
`Pi-hole`, `BIND`, `flock`

### Names of tools and units in this project

`domain-exposure-audit`, `classify.sh`, `domains.conf`, `baseline.json`,
`latest.json`

---

## 4. Technical Verbs

STE permits a Technical Verb if the verb describes a technical process and the
project records it. These verbs are necessary because no approved word has the
same meaning.

| Technical Verb | Meaning in this project |
|----------------|-------------------------|
| `to publish` | To make data available to all persons on the internet. |
| `to redact` | To replace a data field with a placeholder, to hide personal data. |
| `to resolve` | To translate a hostname into an IP address with DNS. |
| `to query` | To send a request to a server and get data. |
| `to proxy` | To send traffic through a server, to hide the address of the origin. |
| `to cache` | To keep a copy of a response, to prevent a second request. |
| `to log` | To write a permanent record. |
| `to issue` | To make and give a certificate. |
| `to renew` | To extend a registration for more time. |
| `to rotate` | To replace a secret with a new secret. |
| `to strip` | To remove metadata from a file. |
| `to geolocate` | To find a physical location from an IP address. |
| `to spoof` | To send a message that shows a false sender. |
| `to throttle` | To limit the number of requests that a server accepts. |
| `to enumerate` | To make a list of all the items of one type. |
| `to classify` | To put an item into a group. |

---

## 5. Approved substitutions

The first version of this project used the words in the left column. STE does
not approve them. The project now uses the words in the right column.

<!-- ste-check: off -->

| Removed word | Approved replacement |
|--------------|----------------------|
| via | with, or through |
| utilize | use |
| prior to | before |
| subsequent to | after |
| in order to | to |
| in the event that | if |
| assist | help |
| obtain | get |
| require | need |
| attempt | try |
| commence | start |
| terminate | stop |
| sufficient | enough |
| additional | more |
| approximately | about |
| currently | now |
| deliberately | for this reason |
| aggressively | often |
| catastrophic | a serious risk |
| adversary | attacker |
| granularity | detail |
| residual | remaining |
| reconnaissance | information for an attack |
| mitigate | make less bad |
| defeat (a proxy) | make a proxy not work |
| unmask | show the identity of |
| leak (verb) | show, or make public |

The project also removed all idioms. Two examples:

| Removed idiom | Approved replacement |
|---------------|----------------------|
| Absence of evidence is not evidence of absence. | A clean result does not show that you are safe. It shows only that these sources have no data today. |
| Treat the first run as a shakedown. | Look at the first run carefully. It can show errors in the tool. |

<!-- ste-check: on -->

### Result codes and classification values

Two names in the output of the tool held an `-ing` form, which Rule 3.4 does not
permit. The project changed them.

| Old name | New name |
|----------|----------|
| the result code `ORIGIN-HOSTING` | `ORIGIN-DATACENTER` |
| the classification value `hosting` | `datacenter` |
| the classification value `residential-hint` | `home-hint` |
| the noun `finding` | `result` |

The word `finding` is an `-ing` form. The tool used it as a noun for each item
in its output, and the JSON output used the key `findings`. The tool now uses
`result` and `results`.

### Severity names

<!-- ste-check: off -->
The first version used `CRITICAL`, `WARN`, and `INFO`. STE does not approve
these words with these meanings.
<!-- ste-check: on --> The project now uses `HIGH`, `MEDIUM`, and
`LOW`. All three words are simple adjectives with one meaning.

This change makes the JSON schema version 2. A `baseline.json` file from
version 1 is not compatible. Make a new baseline after you install this
version.

---

## 6. Known deviations

Be careful. This project follows the Writing Rules, but it is not certified.

1. **The Dictionary is not available.** ASD-STE100 Part 2 is a licensed
   document. This project applies the Writing Rules and keeps the word lists in
   Sections 3 and 4. It does not check each word against the official
   Dictionary. Some words in this project can be words that the Dictionary does
   not approve.

2. **The automated checker reports no failure.** The checker in
   `tests/test-ste.sh` tests each rule in the table in Section 7. It reports 0
   failures for each file in this project. This does not mean that the project
   is certified. Deviation 1 gives the reason.

3. **Text from other systems is not in STE.** The tool shows RDAP fields,
   HTTP headers, and network descriptions from other servers. This text is
   evidence. The tool must not change it.

4. **Code examples are not in STE.** The `nginx`, PHP, and DNS examples in
   `docs/REMEDIATION.md` are code. The comments in those examples are in STE.

To make this project certified, do these steps:

1. Get a licensed copy of ASD-STE100 Part 2, the Dictionary.
2. Check each word in each document against the Dictionary.
3. Add each word that the Dictionary does not approve to Section 3 or Section 4
   of this document, or replace the word.
4. Use a commercial checker, for example HyperSTE or the TechScribe STE
   term checker.

---

## 7. How to check compliance

The project has an automated checker. It tests the rules that a program can
test.

```bash
./tests/test-ste.sh
```

The checker tests these rules:

| Test | Rule |
|------|------|
| No contractions | Punctuation |
| No `-ing` verb forms, except Technical Names | 3.4 |
| No complex tenses | 3.5 |
| No removed words from Section 5 | 1.1 |
| No `e.g.`, `i.e.`, or `&` | Punctuation |
| No em-dash, in any place | Punctuation |
| No en-dash inside a sentence | Punctuation |

The check for the en-dash ignores the text between two backticks. Such text is a
quotation of an example, and not punctuation in a sentence.
| Descriptive sentences have 25 words or fewer | 4.2 |
| Paragraphs have 6 sentences or fewer | 4.5 |

Rule 4.4 recommends a vertical list. Therefore the checker counts each list item
as a separate unit, and not as part of a paragraph.

The checker cannot test these rules. A person must check them:

- Rule 1.1, for the full Dictionary
- Rule 1.4, idioms and metaphors
- Rule 2.1, noun clusters
- Rule 3.2 and Rule 3.3, the active voice
- Rule 4.3, one instruction in one sentence

Run the checker before each commit:

```bash
ln -s ../../tests/test-ste.sh .git/hooks/pre-commit
```
