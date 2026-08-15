# Changes

This file uses ASD-STE100 Simplified Technical English. See
[docs/STE-COMPLIANCE.md](docs/STE-COMPLIANCE.md).

## 1.3.1

A new document, and three faults in the language checker. The tool itself did
not change.

### docs/INTENT.md

The project had a document for the meaning of each result, and a document for
the correction of each result. It had no document for the purpose of each check.

`docs/INTENT.md` gives three things for each of the 15 functions: the purpose,
each method in the order of use, and the test that tells you the function
worked.

It starts from one problem. **A check that found nothing and a check that failed
to look give the same output.** An empty list of hostnames looks the same for a
domain with no hostnames and for a run where crt.sh did not answer. Each section
therefore gives three signals and not one: clean, found, and failed. The
`-UNAVAILABLE` and `-UNREADABLE` result codes are the test.

The document names all 57 result codes. Each number in it was compared against
the code.

### The language checker: three faults

**Rule 4.2 never found one sentence, in any version.** The test sent
`printf '%s'` into `while read`. `printf '%s'` writes no final newline,
therefore `read` returned false at the end of the data and the loop body did not
run for the last line. Almost every line holds one sentence, therefore the test
found nothing at all. The correction reads the file with one `awk`, and `awk`
reads the last record correctly.

**A failure did not change the exit code.** `check_paragraphs` sent `awk` into
`while read` through a pipe. A pipe puts the loop in a subshell, therefore the
count of the failures went back to its old value when the loop ended. A
paragraph with too many sentences printed a failure, and the tool gave exit code
0. A person who reads the exit code saw a clean run. Both loops now read from a
process substitution.

**The placeholder for a shell variable was one capital letter.** The test for
rule 4.2 protects a period after a capital letter, because `J. Smith` is a name
and not the end of a sentence. The placeholder `X` therefore joined two
sentences into one, and gave two false results. The placeholder is now `CODE`,
which is the placeholder that the markdown reader already used.

### The language checker: 61 times faster

A full run needed 83 seconds. It now needs 1.4 seconds.

The cause was the number of programs. `check_words` ran 20 programs for each
line of each file, and `check_dashes` ran 3 more for each line to remove the
text between backticks. A full run started more than 80000 programs, and almost
all of the time was the cost of the programs and not the work.

| Function | Before | After |
|----------|--------|-------|
| `check_words` | 20 programs for each line | bash tests each pattern itself |
| `check_sentences` | 4 programs for each line, 3 more for each sentence | one `awk` for each file |
| `check_dashes` | 3 programs for each line | bash removes the backticks itself |

The output is the same, character for character, except for the three faults
above. This was tested against the version from 1.3.0 before the correction of
the faults.

A test that needs 83 seconds is a test that a person skips before a commit.

### Tests

`tests/test-parsing.sh` now has 36 tests. Seven new tests read the checker
itself, and three of them give it a file that must fail and a file that must
pass. Those three test the **exit code** and not the message, because the fault
above printed the correct message and gave the wrong code.

## 1.3.0

A code review of version 1.2.1, together with a run on three real domains, found
one fault that made a whole feature dead, one fault that made the documented
procedure destroy its own protection, and five smaller faults.

### The cache moved out of the state directory

The documented way to make a new baseline is `rm -rf state`. The cache was at
`state/cache/`, therefore that command also deleted every answer from crt.sh.

`cache_fetch` holds a fallback for this exact condition: when a request fails and
a file is in the cache, the tool uses the old file. During the run of version
1.2.1, crt.sh answered 000, then 502, then 503, on all three domains. The
fallback could not run, because the command deleted the cache minutes before.

The cache is now at `$XDG_CACHE_HOME/domain-exposure-audit`. Use `--cache-dir` or
`DEA_CACHE_DIR` to put it somewhere else. The old directory `state/cache/` is no
longer in use, and you can delete it.

### --baseline refuses a run that did not see all the data

The run of version 1.2.1 used `--baseline`, and crt.sh failed for two of the
three domains. The tool therefore wrote a baseline that holds an empty list of
hostnames for those two domains. The next run would show every hostname as a new
name. That looks like news about the domain, and it is only the recovery of a
service.

`--baseline` now writes nothing after a run with `CT-UNAVAILABLE`,
`ARCHIVE-UNAVAILABLE`, `RDAP-UNREADABLE`, or `HARVEST-UNREADABLE`. The tool gives
a warning that names each service. Use `--force-baseline` to write the baseline
anyway.

`CT-SECOND-SOURCE` does not stop a baseline. crt.sh fails often, and certspotter
gives a good answer.

The exit code does not change, because the condition is a fault of a service and
not a result about your domain.

### Corrections

- **The notify command never ran, in any version.** An unconditional `return 0`
  was above the notify block in `audit_domain`, therefore the block was
  unreachable. `DEA_NOTIFY_CMD`, the flag `--notify`, and
  `examples/notify-desktop.sh` all had no effect. The notify block now comes
  before the exit mask, and `return 0` is the last line of the function. The
  `return 0` is necessary: the last test in the mask is false when nothing
  changed, and the function must give a success.

- **`CT-UNAVAILABLE` named the wrong HTTP code.** The message used the code from
  crt.sh only. During the run, certspotter answered 200 for two domains, and the
  message said 502. The message now names the code of each service. It also says
  which of two conditions happened: a transport failure, which a later run
  repairs, or an answer that holds no certificate, which a later run does not
  repair.

- **The delay between the tries at crt.sh was too short.** The delays were 1
  second and 2 seconds. A code of 502 or 503 means that the service has too much
  work, and 3 seconds is not enough time for the load to fall. The delays are now
  5 seconds and 15 seconds. A run costs at most 20 more seconds.

- **The tool said that the SOA contact of a DNS provider was possibly your own
  mailbox.** The list of providers was inline in the DNS check, and it had no
  entry for Gandi. The result `SOA-RNAME` therefore came one time for each Gandi
  domain, three times in one run. The list is now the function
  `is_provider_soa_contact` in `lib/classify.sh`, therefore a test can test it.
  The list holds about 40 providers. The new LOW result `SOA-PROVIDER` reports the
  good condition, in the same way as `RELAY-EMAIL` and `CONTACT-FORM`.

- **Check 3b gave a message that was not true.** When Certificate Transparency
  gave no data and the other programs found no new name, the tool said "Each name
  is already in Certificate Transparency". The tool held no list to compare
  against. The message now says that the comparison was not possible.

- **The systemd unit failed on the first run of a new install.**
  `ReadWritePaths=%S/domain-exposure-audit` needs the directory to exist before
  systemd builds the mount namespace, and the tool creates the directory later.
  `StateDirectory=` and `CacheDirectory=` replace that line. systemd creates both
  directories first, and it makes both writable. The unit also marks all three
  paths that you must edit, not one.

- **The tool gave no clear message on bash 3.2.** It uses `mapfile`, associative
  arrays, and `${var: -3}`, therefore it needs bash 4.2 or a later version. macOS
  gives bash 3.2 at `/bin/bash`. The tool now tests the version and stops with a
  message and exit code 8.

- **The README said that the tool keeps a crt.sh answer for 6 hours.** The default
  is 168 hours.

### Tests

`tests/test-classify.sh` now has 163 tests. The new tests hold 13 real SOA
contacts of DNS providers. One of them is `hostmaster.gandi.net`. The tests also
hold four addresses that are possibly personal.

`tests/test-parsing.sh` now has 29 tests. Seven new tests read the tool file:

- the notify block comes before the exit mask, therefore it can run
- the cache is not under the state directory
- the tool has the variable `DEA_CACHE_DIR`
- `--baseline` tests for a run with missing data
- the tool holds the list of codes that show missing data
- the message for `CT-UNAVAILABLE` names the code from certspotter
- the tool tests the version of bash

### What you must do after this upgrade

Make a new baseline for `humai.la` and `numerge.net`. The baseline from the run of
version 1.2.1 holds an empty list of hostnames for both, because crt.sh failed.
Check that the output says `the tool used crt.sh` before you accept the baseline.

## 1.2.1

A run of version 1.2.0 on three real domains found five faults.

### Corrections

- **A contact form counted as your email address.** The registry of `.la`
  publishes the address of a web page in the email field, for example
  `https://whois.nic.la/contact/humai.la/registrant`. Cloudflare does the same.
  The record then holds no email address of any type, which is the best possible
  condition. But `is_relay_email` needed an `@` character, therefore the value
  fell through to "real data" and the tool wrote three wrong `PII-EMAIL` results
  for humai.la. The new function `is_contact_uri` finds such a value, and the
  tool writes the new LOW result `CONTACT-FORM`.

- **A result for `www` gave the wrong advice.** `ENRICH-HOSTNAMES` said that a
  name tells an attacker which software you use, and the name was `www`. The
  result now removes the apex name and the name `www`, because those two names
  are public by design.

- **The tool printed fewer names than it found, with no reason.** Check 3b said
  "subfinder found 5 name(s)" and then printed one name. The tool now says how
  many of the names are not in Certificate Transparency, before it prints them.

- **Two numbers in one line did not agree.** The line said "10 address(es) are
  direct", and the networks below it held 8 addresses. The count held each pair
  of a hostname and an address, therefore an address that two hostnames share
  counted two times. The tool now counts each address one time.

- **The advice about a hostname was always the same.** `CT-HOSTNAMES` said that a
  name such as pass or vault gives the name of a program, and the names were
  `australis`, `borealis`, `cancer`, and `capricorn`. Those names give the name
  of no program. The new function `reveals_software` holds a list of about 200
  program names. The advice now depends on the names in the list.

### Tests

`tests/test-classify.sh` now has 144 tests. The new tests hold the real contact
form address from the record of humai.la. They also test that the tool separates
a name such as `vault` from a name such as `australis`.

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
