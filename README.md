# domain-exposure-audit

This tool finds the public data about a domain that you own. It only reads. It
changes nothing.

Run the tool one time to see your position today. Run the tool on a timer to see
when your position changes.

The important question is not "does the registration hide my address". The
important question is this: can a person find a path from this domain name to
my house? Such a path can open at any time, and it opens quietly.

Here are three examples. You add a subdomain from a computer at home. A
certificate authority makes a certificate for a hostname that gives the name of
your software. A registrar changes a contact field during a transfer. None of
these events sends you a message.

This project uses ASD-STE100 Simplified Technical English. See
[docs/STE-COMPLIANCE.md](docs/STE-COMPLIANCE.md).

```
$ ./domain-exposure-audit.sh example.com

════ example.com ════

1. Registration data (RDAP)
  registry RDAP  https://rdap.identitydigital.services/rdap/domain/example.com -> 200
  registrar RDAP https://rdap.cloudflare.com/rdap/v1/domain/example.com -> 200
  status: clientTransferProhibited
  expires: 2027-03-14T00:00:00Z
  WHOIS on port 43: stopped for .com. This is correct after January 2025.
...
Summary
  HIGH: 0   MEDIUM: 2   LOW: 5
  ▲ NO-CAA The domain has no CAA record. Any certificate authority can make
    certificates for this domain.
  ▲ ARCHIVE-PRESENT The Wayback Machine holds 41 address(es) for this domain.
```

## The checks

| # | Check | The question it answers |
|---|-------|-------------------------|
| 1 | Registration data (RDAP) | Is my name, street, city, or postal code public? |
| 2 | DNS records | What do my nameservers give to a person? Can a person send false mail as me? Can a person copy my zone? |
| 3 | Certificate Transparency | Which hostnames are in a permanent public log? |
| 4 | Hostnames and addresses | Does a name point to an address outside the proxy? Who owns that network? |
| 5 | HTTP paths and headers | Does a live host give source code, secrets, user names, or the name of my origin server? |
| 3b | More hostnames | Do other passive sources know a hostname that the logs do not hold? |
| 6 | Copies in the archive | Does the Wayback Machine hold a page with data that I removed? |
| 7 | GPS data in images | Do the images on my site hold GPS data? |
| 8 | Shodan records | Is a public scan database aware of my addresses? |

[docs/CHECKS.md](docs/CHECKS.md) tells you the purpose of each check, the
correct result, and each other possible result.
[docs/REMEDIATION.md](docs/REMEDIATION.md) tells you how to correct each result.

## Installation

```bash
git clone https://github.com/om1d3/domain-exposure-audit.git
cd domain-exposure-audit
chmod +x domain-exposure-audit.sh tests/*.sh examples/notify-desktop.sh
./tests/test-classify.sh          # 144 tests for the decision functions
./tests/test-parsing.sh           # 22 tests for the data that servers send
./tests/test-enrich.sh            # 36 tests for the other programs and DNS
./tests/test-ste.sh               # the language checker
```

This GitHub repository is a copy, and it is read only. Another server holds the
source of truth, and that server sends each change here with a force push.
Therefore a commit that you make here is lost at the next copy. A pull request
here cannot go into the project. Please write an issue instead.

These three tools are necessary: `curl`, `jq`, and `dig`.

These tools are not necessary, but they add more checks:

| Tool | What it adds |
|------|--------------|
| `whois` | The owner of an IP address. This check separates a data center from a house. |
| `exiftool` | GPS data in the images on your site. |
| `subfinder` | Hostnames from about 30 passive sources. Certificate Transparency is then not the only source. |
| `theHarvester` | Email addresses from search engines. Use the `--harvest` flag. |

`subfinder` and `theHarvester` are not in each package system. Get `subfinder`
from the ProjectDiscovery releases, or with `go install`. Get `theHarvester`
from `pipx install theHarvester`.

```bash
# Arch and CachyOS
sudo pacman -S curl jq bind whois perl-image-exiftool
# Debian and Ubuntu
sudo apt install curl jq dnsutils whois libimage-exiftool-perl
# Fedora
sudo dnf install curl jq bind-utils whois perl-Image-ExifTool
# macOS
brew install curl jq bind whois exiftool
```

The tool is one file and one library file. The tool finds `lib/classify.sh` in
the same directory. Therefore you do not install the tool. Clone the repository
and run the tool. You do not need root permissions.

## How to use the tool

```bash
# one domain
./domain-exposure-audit.sh example.com

# many domains, from a file
cp domains.conf.example domains.conf   # then edit the file
./domain-exposure-audit.sh -c domains.conf

# keep the state of today as the baseline
./domain-exposure-audit.sh -c domains.conf --baseline

# show only the changes from the baseline
./domain-exposure-audit.sh -c domains.conf --diff-only

# get the data as JSON
./domain-exposure-audit.sh --json example.com | jq '.results'
```

Use `--help` to see all the flags.

### The baseline is the important part

One run tells you your position today. The baseline makes the tool a monitor and
not only a scanner. The flag `--baseline` keeps the snapshot of today. Each run
after that shows you what is different.

This is important because you cannot change many of the results. ICANN rules
make your region public. A hostname in a certificate log stays there for all
time. These results come back on each run. If you read the full list each time,
you will start to ignore the list. The list of changes is the new information.

Make a new baseline only after you make a change and you are satisfied with the
new state:

```bash
./domain-exposure-audit.sh -c domains.conf            # read the changes
./domain-exposure-audit.sh -c domains.conf --baseline  # accept the changes
```

## The exit code

The exit code is a bitmask. One number can show you more than one result.

| Bit | Value | Meaning |
|-----|-------|---------|
| none | 0 | No results, and no change. |
| 0 | 1 | The tool found MEDIUM results. |
| 1 | 2 | The tool found HIGH results. |
| 2 | 4 | The tool found a change from the baseline. |
| 3 | 8 | The tool failed. A tool is absent, the state directory is not writable, or another run is in use. |

The code 6 shows HIGH results and a change from the baseline.

A LOW result sets no bit. Your region is public for all time. If that result set
a bit, the exit code would never be 0, and the code would give you no
information.

```bash
./domain-exposure-audit.sh -q -c domains.conf
status=$?
(( status & 2 )) && echo "the tool found a HIGH result"
(( status & 4 )) && echo "the data changed"
```

## How to run the tool on a timer

One run each week is correct for most persons. Registration data changes only a small
number of times each year. A certificate log gets new data some hours after a
certificate authority makes a certificate. Also, crt.sh limits the number of
requests. Use one run each day only while you make changes to your servers.

### systemd

The directory [`examples/`](examples/) holds the two unit files. Install them
for your user:

```bash
mkdir -p ~/.config/systemd/user
cp examples/domain-exposure-audit.{service,timer} ~/.config/systemd/user/
# edit the ExecStart path in the .service file
systemctl --user daemon-reload
systemctl --user enable --now domain-exposure-audit.timer
systemctl --user list-timers domain-exposure-audit.timer
journalctl --user -u domain-exposure-audit -n 50
```

The timer runs only while you are logged in. To change this, use this command:

```bash
loginctl enable-linger $USER
```

### cron

```cron
# Each Monday at 07:30. Send mail only for a HIGH result or for a change.
30 7 * * 1 /path/to/domain-exposure-audit.sh -q -c /path/to/domains.conf; s=$?; [ $((s & 6)) -ne 0 ] && /path/to/domain-exposure-audit.sh -c /path/to/domains.conf --diff-only
```

### A message on your desktop

```bash
./domain-exposure-audit.sh -q -c domains.conf --notify examples/notify-desktop.sh
```

## The files that the tool writes

```
$XDG_STATE_HOME/domain-exposure-audit/       # ~/.local/state/... is the default
├── <domain>/
│   ├── baseline.json      the state that you kept with --baseline
│   ├── latest.json        the most recent run
│   └── history/           the last 120 snapshots, with a time in each name
├── cache/                 the IANA list, the Cloudflare ranges, crt.sh answers
├── reports/               one report file for each run
└── .lock                  the lock file, to stop two runs at the same time
```

Use `-s` to change the state directory. Use `-o` to change the report directory.

Be careful. A snapshot and a report hold your own data. If your registration is
not redacted, the file `baseline.json` holds your street address. For this
reason, the file `.gitignore` holds `state/`, `reports/`, the snapshot files,
and `domains.conf`. Do not remove these lines if the repository is public.

## The files in this repository

```
domain-exposure-audit.sh    the tool
lib/classify.sh             the decision functions. They use no network.
tests/test-classify.sh      144 tests for lib/. No network.
tests/test-parsing.sh       22 tests for RDAP and HTTP answers. No network.
tests/test-enrich.sh        36 tests for DNS and the other programs. No network.
tests/test-ste.sh           the ASD-STE100 language checker
docs/CHECKS.md              each check: purpose, correct result, other results
docs/REMEDIATION.md         each result code, and how to correct it
docs/STE-COMPLIANCE.md      the language rules, and the word lists
domains.conf.example        an example configuration file
examples/                   a systemd service, a timer, and a notify command
```

The tool and the library are in two files for a reason. The library holds the
decisions of the tool. Two examples: does this field hold redacted data, and is
this IP address in a data center or in a house?

These decisions are estimates. You must change them when you see a new registrar
or a new internet service provider. The library uses no network and no files.
Therefore the unit tests can test the library, and you can change an estimate
without a live query.

## What the tests prove

This section tells you what the tests prove and what they do not prove.

The tests prove that `lib/classify.sh` is correct. There are 144 tests, and all
144 pass. They test the placeholder text of real registrars. They test the
difference between an internet service provider and a data center. They test the
IPv4 CIDR arithmetic at the limits of each range.

The tests prove that the tool reads the answers of other servers correctly.
There are 22 tests in `tests/test-parsing.sh`. They hold the real data from the
run that found the faults in version 1.0.0.

The tests prove that the resolver and the other programs work. There are 36
tests in `tests/test-enrich.sh`. That file makes fake copies of `dig`,
`subfinder`, and `theHarvester`, therefore it needs no network. Seven of the
tests read the tool file and stop if an old fault comes back.

The tests prove that the tool has no syntax error. The command `bash -n` gives
no error. The flag `--help` works. The tool gives the correct message when a
necessary program is absent.

The tests do not prove that the network code is correct. The `jq` filters for
the RDAP data, for the snapshot, and for the changes are new code. A person
wrote them and read them, but no person ran them against a live server. Look at
the first run carefully. It can show errors in the tool.

```bash
./domain-exposure-audit.sh --json your-domain.com > /tmp/snap.json
jq . /tmp/snap.json          # an error here shows a fault in a filter
```

## The limits of this tool

A clean result does not show that you are safe. It shows only that these public
sources have no data today. Your name and your address can still be in business
records, in a data broker database, or on your own social media pages. Check 9
in [docs/CHECKS.md](docs/CHECKS.md) lists the checks that a person must do.

The IPv6 test for the Cloudflare ranges is short. It compares two groups of
hexadecimal digits. It does not do 128-bit arithmetic. Therefore it can give the
wrong answer "not Cloudflare". The tool then writes a MEDIUM result, and a
person reads it. This is the safe type of error.

The test for a home network is an estimate. It reads the text description from
the RIR. It does not know each small internet service provider. The result
`ORIGIN-UNKNOWN` means "the tool cannot decide". It does not mean "there is no
problem".

crt.sh limits the number of requests. The result `CT-UNAVAILABLE` is almost
always this limit and not a problem with your domain. The tool keeps each crt.sh
answer for 6 hours. Change this time with `DEA_CT_CACHE_HOURS`.

The tool queries public sources only. A historical WHOIS service, a people
search database, and a data broker all need an account. The tool gives you the
addresses of these services. It does not query them.

The word list of subdomain names is short. Certificate Transparency finds the
real names. The word list finds only a name that has no certificate.

## What this tool does to you

Each query is a query about your domain, and it comes from your IP address. The
other party keeps a record. crt.sh, the Wayback Machine, rdap.org, and the RIRs
all see that you are interested in these names. This is necessary for this type
of work, and it is safe for almost all persons. But if a person can watch these
services, use a VPN or run the tool from a VPS.

Run the tool from a network that is not your own network, if you can. On your
home network, a local resolver, a Pi-hole, or Tailscale can give a different
answer. The public internet gets the other answer. This difference is the fault
that the tool must find.

## How to send a change

This GitHub repository is a copy. Another server holds the source of truth, and
the copy happens with a force push. Therefore this repository cannot accept a
pull request, and a commit that you make here is lost.

Write an issue. Put a patch in the issue if you have one, for example the output
of `git format-patch`. Each change must keep these two rules:

- The four test files must pass. Run them before you write the issue.
- The text must follow ASD-STE100. Run `./tests/test-ste.sh`. See
  [docs/STE-COMPLIANCE.md](docs/STE-COMPLIANCE.md).

## Licence

MIT. See [LICENSE](LICENSE).
