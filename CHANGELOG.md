# Changes

This file uses ASD-STE100 Simplified Technical English. See
[docs/STE-COMPLIANCE.md](docs/STE-COMPLIANCE.md).

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
