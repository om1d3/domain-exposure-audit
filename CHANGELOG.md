# Changes

This file uses ASD-STE100 Simplified Technical English. See
[docs/STE-COMPLIANCE.md](docs/STE-COMPLIANCE.md).

## 1.2.0

A run on three real domains, and one run with subfinder, found nine faults. This
version corrects them.

### Corrections

- **Three email results were wrong.** Gandi publishes a relay address in
  place of your mailbox, for example
  `8b63ef004b7b74c693720a8c46221f08-2266992@contact.gandi.net`. The tool
  reported that address as your data, therefore it wrote three `PII-EMAIL`
  results that need no action. The new function `is_relay_email` finds a
  relay address in two ways: a list of the domains that registrars use, and
  the form of the part before the `@`. A token of 16 hexadecimal digits or more
  is not a mailbox that a person chose. The tool now writes the LOW result
  `RELAY-EMAIL` instead.

- **The tool joined a list of names with the wrong separator.** `paste -d` takes
  a **list** of characters and it uses them one after the other. Therefore
  `paste -sd'; '` joined the first pair with a semicolon and the second pair with
  a space. The issuer line joined three names into text that looks like two
  names. This fault was in three
  places. The same fault was in one other place in version 1.0.0, and the
  correction there did not reach these three.

- **The cache for Certificate Transparency was 6 hours.** A certificate log only
  grows, therefore a name never leaves it, therefore an answer from one week
  before is nearly as good as a new answer. The window is now 168 hours. A run
  during a fault at crt.sh now uses the last good answer.

- **An empty answer counted as a success.** CertSpotter gave an empty list for
  two domains that have certificates, and the tool accepted it. An empty list is
  now a failure, therefore an old answer from the cache of crt.sh wins.

- **The tool did not say which service gave the data.** CertSpotter shows the
  certificates that are valid now. crt.sh shows each certificate from the past.
  The two answers are not the same, and the difference is important. The new LOW
  result `CT-SECOND-SOURCE` says which service the tool used.

- **A result for the hostnames gave a number and not the names.** A hostname
  that points to no address is absent from Check 4, therefore the names that
  tell an attacker which software you use were found and then not shown. On
  horia.wtf, subfinder found `pass` and `status`, and the result said only "2
  hostname(s)". The result now names each one.

- **`ENRICH-ABSENT` was a result.** It describes the programs on your computer,
  and not the public data about your domain. Therefore the install of subfinder
  made a change in the list of results, and that change was noise. It is now a
  message on the screen.

- **`RDAP-NO-SERVER` was MEDIUM.** Version 1.1.0 reads the contact fields from
  WHOIS in that condition, therefore the check is complete and the severity is
  now LOW.

- **subfinder asked its own servers for a new version.** The tool now passes
  `-disable-update-check`, which removes one request for each domain.

### One result for each network

The tool wrote one result for each address. Eight addresses at one company gave
eight results. The addresses of one company are the same infrastructure,
therefore the tool now writes one result for each **network**. A test with five
hostnames on four addresses at two companies gives two results.

### The tool is faster

The wait between the tries at crt.sh was 3 seconds and then 6 seconds. That is 9
seconds for each domain, and 27 seconds for three domains, with no work. The wait
is now 1 second and then 2 seconds. The longer cache window removes most of the
tries.

### Tests

`tests/test-classify.sh` now has 114 tests. The new tests hold the real
relay address from the record of numerge.net. They also test that a real
mailbox does not look like a relay address, for example
`j.smith@gandi-consulting.com`, which holds the name of the registrar but is not
a domain of the registrar.

## 1.1.1

### Punctuation

The project used the em-dash 63 times, in 10 files. ASD-STE100 restricts the
dash, because a dash inside a sentence hides the relationship between the two
parts of the sentence. The em-dash is now not permitted in this project, in any
place.

- A separator in a heading or a title is now the en-dash, for example
  `Check 1 – Registration data (RDAP)`.
- A table cell that means "not applicable" now holds the word `none`.
- The separator in a report line is now a colon.
- The text that the notify command sends is now a sentence. That text also used
  the severity words of version 1.0.0, and it now uses HIGH and MEDIUM.

### The checker did not find this fault

The checker in `tests/test-ste.sh` reads the prose of each file, and it skips a
heading. Each em-dash was in a heading or in a title, therefore the checker
found none of them. The claim of 0 failures had no value for this rule.

The checker now reads each raw line of each file. It has two new rules:

- No em-dash, in any place.
- No en-dash inside a sentence. A line that ends with a full stop is a
  sentence. Text between two backticks is a quotation of an example, therefore
  the check ignores it.

### A fault in the checker itself

The first version of the new rule used the bash escape `$'\u2014'`. Bash expands
that escape only in a locale that can hold the character. In the C locale, bash
leaves the text as the letters `u2014`, therefore the rule matched the wrong text
and it found no real em-dash. The checker now holds the exact bytes of each
character, from `printf` with an octal escape. Therefore it works in each
locale.

## 1.1.0

This version corrects the faults that the run of version 1.0.1 found. It also
adds two other programs as a source of hostnames.

### Corrections

- **The branch for the HTTP code 404 could not run.** The tool tested the body
  for valid JSON before it read the code. An RDAP server that does not hold a
  TLD answers 404 with a body that is not JSON, therefore the tool stopped at the
  test for JSON. The correction of version 1.0.1 was behind a door that never
  opened. The domain `humai.la` still got no check. The tool now reads the code
  first.

- **A TLD with no RDAP server now gets a full check.** Before, the tool only told
  you to read the WHOIS answer yourself. It now reads the contact fields from
  WHOIS on port 43 and writes the same `PII-` results. One function
  `assess_contact` makes the decision for RDAP data and for WHOIS data.
  Therefore the two paths cannot use different rules.

- **A second service for Certificate Transparency.** crt.sh gave the codes 000,
  404, and 503 in one run of three domains. The tool now tries crt.sh three
  times, with a longer wait after each try. Then it tries CertSpotter, which
  reads the same public logs.

- **A message about a timeout became an IPv6 address.** The filter accepted any
  line with a colon. A message such as `;; connection timed out` holds colons.
  The filter now accepts only the characters of an IPv6 address.

- **The data of one domain became a result for the next domain.** theHarvester
  writes its own file. The tool did not remove that file before the next domain,
  therefore it read the file of the domain before. The check for images had the
  same fault. The tool now removes both before each domain.

- **One failure gave two results.** An RDAP server that failed gave both
  `RDAP-HTTP` and `RDAP-UNREADABLE`. It now gives one.

- **A count from jq can be empty.** An empty count stopped a test with an error
  message on the screen. A new function `num` gives 0 for a value that is not a
  number.

### The tool is faster

The tool sends 8 DNS queries at the same time. Use `--parallel N` to change the
number, and `--parallel 1` for one query at a time. The tool also reads the
status and the A records from one answer, therefore it makes two queries for
each name and not three.

A run of three domains needed 159 seconds with version 1.0.1. The cause was 414
DNS queries, one after the other.

### More hostnames

New check 3b. The tool can use two other programs. Each one is passive, and it
sends no traffic to your hosts.

- `subfinder` reads about 30 passive sources. The tool uses it if it is
  installed. Use `--no-enrich` to stop this. Use `--enrich-all` to let subfinder
  use each source. Some of those sources need an API key.
- `theHarvester` searches for email addresses and hostnames. The tool uses it
  only with the `--harvest` flag, because it sends many requests to search
  engines.

The tool keeps a name only if the name ends with your domain. Therefore a name
from another domain cannot enter Check 4.

### Nmap and other active scanners

The tool does not scan a port, and it will not. Check 10 in `docs/CHECKS.md`
gives the reason and tells you how to use Nmap yourself. In short: the tool
stays passive, therefore it is safe to run on any name in your `domains.conf`
file. Also, a shared address such as the mail service of a hosting company
belongs to that company and not to you.

### New result codes

`RDAP-NO-SERVER`, `WHOIS-REDACTED`, `ENRICH-HOSTNAMES`, `ENRICH-ABSENT`,
`HARVEST-EMAIL`, `HARVEST-UNREADABLE`.

### Tests

New file `tests/test-enrich.sh`, with 36 tests. It makes fake copies of `dig`,
`subfinder`, and `theHarvester`, therefore it needs no network. It takes each
function out of the tool with awk, therefore it reads the real code and not a
copy of the code.

Two of the faults above came from these tests and not from a run on a real
domain: the file of one domain that became a result for the next domain, and the
message about a timeout that became an address.

The project now has 146 tests in three files.

## 1.0.1

A run on three real domains found five faults. This version corrects them. Each
correction has a test in `tests/test-classify.sh` or `tests/test-parsing.sh`.

### Corrections

- **The status check for a registrar lock.** RFC 9083 writes a status in
  lowercase with spaces, for example `client transfer prohibited`. Version 1.0.0
  compared the answer against the EPP name `clientTransferProhibited`. The two
  never matched, therefore `NO-TRANSFER-LOCK` and `NO-UPDATE-LOCK` fired for
  every domain. The tool now removes the spaces and compares both forms.

- **The HTTP code from curl.** When a connection fails, curl writes `000` and
  also stops with a code that is not 0. Version 1.0.0 added a second `000` for
  the failure, therefore the value was `000000`. That value is not valid JSON,
  and the branch for "no answer" never ran. A new function `http_code` gives
  three digits at all times.

- **The word list for a data center.** The list had no entry for Gandi.
  Therefore 10 addresses at Gandi gave a wrong `ORIGIN-UNKNOWN` result. The list
  now holds Gandi and about 20 more hosts in Europe.

- **The check for WHOIS on port 43.** The old check inverted a text search. An
  empty field did not match a placeholder pattern, therefore the tool reported
  the field as public. This gave a wrong HIGH result. The check now uses the
  `is_redacted` function, which accepts each empty form.

- **A TLD with no RDAP server.** Many ccTLDs are not in the IANA RDAP list. The
  tool got the HTTP code 404 and said that the domain has no registration. It
  now asks WHOIS on port 43 first, and it writes the new result
  `RDAP-NO-SERVER` if the domain does have a registration.

### Improvements

- The tool asks the RIR about each address one time only. It keeps the answer
  for the run.
- The tool writes one result for each address, and not one result for each pair
  of a hostname and an address. Five hostnames on two addresses give two
  results, and not ten.
- New file `tests/test-parsing.sh`, with 22 tests. Three of them read the tool
  file and stop if the old code comes back.
- New result code `RDAP-NO-SERVER`.
- The heading `5. HTTP surface` is now `5. HTTP paths and headers`. The word
  "surface" is a metaphor, and Rule 1.4 does not permit a metaphor.
- New files in `assets/`: a logo, four sizes for an avatar, and an image for the
  GitHub social preview. The file `assets/logo.py` makes each of them from one
  set of coordinates.

## 1.0.0

The first version. The JSON schema is version 2, because the word `finding` is
an `-ing` form. See Section 5 of `docs/STE-COMPLIANCE.md`.
