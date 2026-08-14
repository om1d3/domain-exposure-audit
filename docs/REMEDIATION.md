# How to correct each result

This document has one section for each result code. The HIGH results are first.

This document uses ASD-STE100 Simplified Technical English. See
[STE-COMPLIANCE.md](STE-COMPLIANCE.md). The code examples are code, therefore
they are not in Simplified Technical English. The comments in the code examples
are in Simplified Technical English.

Go to: [HIGH](#high) · [MEDIUM](#medium) · [LOW](#low) ·
[DNS records to copy](#dns-records-to-copy)

---

## HIGH

### `ORIGIN-RESIDENTIAL`

A hostname points to an address in the network of a consumer internet service
provider. This result gives your physical location. Correct this result first.

**Make sure of the result before you make a change.** The tool reads a text
description from the RIR, and the description can be wrong.

```bash
dig +short A suspect.example.com
whois <that-ip> | grep -iE 'orgname|netname|descr|country'
```

If the network belongs to a consumer internet service provider, and the
connection is yours, use one of these four methods:

1. **Send the traffic through the proxy.** In the Cloudflare DNS panel, change
   the record from DNS-only (the grey cloud) to Proxied (the orange cloud). A
   visitor then gets the Cloudflare address. This method works for HTTP and
   HTTPS only.
2. **Move the service to another network.** A VPS for 4 euros each month removes
   the problem. The other methods only make the problem smaller.
3. **Use a tunnel.** Cloudflare Tunnel, Tailscale Funnel, and a WireGuard
   connection to a VPS all show the address of the other server. They do not
   show your address. They also need no open port at your house.
4. **Delete the record.** If only you use the host, the name does not belong in
   public DNS. Use a private resolver or Tailscale. Get your certificates with
   the DNS-01 method.

**The proxy is not enough if the record was public in the past.** A person who
queried the record can have a copy of the address. A historical DNS service such
as SecurityTrails or DNSDB keeps the old value. If the record was public for a
long time, assume that the address is known. Then you must move the service. The
proxy alone is not enough.

Be careful with the records that cannot use an HTTP proxy. An `MX` record must
point to a real host. Therefore a mail server at your house shows your address
by design. Use a mail company, or send your mail through a VPS.

### `PII-STREET`, `PII-CITY`, and `PII-POSTCODE`

Your address is in the public registration record.

1. **Look for a control that is set to off.** Most gTLD registrars redact the
   data, and they give you a control. At Cloudflare, look in the Registration
   section of the domain, under Contact Information.
2. **If the TLD does not permit redaction, no control will help.** The TLD `.us`
   is the known example. The registry does not permit a privacy service, and it
   needs correct data that a person can use. Some ccTLDs have their own rules.
   For such a TLD, you must change the content of the record. Use one of these
   three:
   - a registered agent service,
   - a virtual mailbox,
   - the address of a company that you own.

   Be careful. A post office box and some mail services do not meet the rules of
   the registry. Ask the registry first. A record that does not meet the rules
   can cost you the domain.
3. **Never put false data in the record.** False registration data is a reason
   for the registry to stop your domain. Use a real address that is not your
   house.
4. **Then check the historical WHOIS services.** See
   [Check 9](CHECKS.md#check-9--the-checks-that-a-person-must-do). A change today
   does not remove a copy from the past.

Make sure of the correction at the RDAP server of the registrar, and not at the
registry:

```bash
curl -sL -H 'Accept: application/rdap+json' \
  "$(curl -sL https://rdap.org/domain/example.com | jq -r '.links[]|select(.rel=="related").href')" \
  | jq '[.entities[] | {roles, vcard: (.vcardArray[1] | map({(.[0]): .[3]}) | add)}]'
```

### `WHOIS43-PII`

RDAP holds redacted data, but the old service on port 43 shows the address
fields. The two data services of your registrar do not agree.

You cannot correct this yourself. Send a message to the support group of your
registrar. Give the names of the fields. Give the name of the ICANN Registration
Data Policy.

### `AXFR-OPEN`

A nameserver permits a zone transfer to any person. Therefore any person can copy
all your DNS records. This includes each internal name that has no certificate.

If a company operates your DNS, this fault must not be possible. Send a message
to the company. Also look at your `NS` records. If an old nameserver is still in
the list, remove it.

If you operate BIND, permit a zone transfer to your secondary servers only:

```
// Give the zone to the secondary servers only.
allow-transfer { 192.0.2.53; 198.51.100.53; };
```

Put `allow-transfer { none; };` in the global section. Then permit the transfer
in each zone that needs it. For Knot, NSD, and PowerDNS, use the same type of
rule, and use TSIG keys for the secondary servers.

After the correction, assume that a person has a copy of the zone. Read each
name in the zone. Ask what each name tells an attacker.

### `HTTP-EXPOSED`

A path such as `/.git/HEAD`, `/.env`, a credentials file, or a database file gave
the HTTP code 200.

The order of these steps is important:

1. Stop the access at the server or at the proxy. The code examples are below.
2. **Replace each secret that was public.** Assume that each secret is known.
   Programs read these paths continuously, and you do not know the length of
   time. Replace the database passwords, the API keys, the session secrets, and
   the mail passwords.
3. Read your access records, if they go far enough into the past. Find out who
   read the path.
4. Correct the process that made the path public. A public `.git` directory
   almost always means that your installation process copies the work directory.
   It must export the files instead.

```nginx
# Stop the access to the version control and configuration files.
location ~ /\.(git|env|svn|hg|aws|ssh|DS_Store) { deny all; return 404; }
location ~ \.(sql|bak|old|swp)$ { deny all; return 404; }
```

```apache
# Stop the access to the version control and configuration files.
RedirectMatch 404 /\.(git|env|svn|hg|aws|ssh)
<FilesMatch "\.(sql|bak|old|swp)$">
  Require all denied
</FilesMatch>
```

### `EXIF-GPS`

An image on your site holds GPS data.

```bash
# Read the GPS data.
exiftool -gps:all -n /path/to/images/

# Remove the metadata. Keep a copy of the first files. This command
# changes the files.
exiftool -all= -tagsFromFile @ -Orientation -ColorSpace -icc_profile \
  -overwrite_original /path/to/images/
```

This command keeps the orientation and the colour profile. Therefore the images
are still correct on the screen. The command removes each other data field. Send
the new files to your site.

Then stop the problem for the future. Remove the metadata in your build process,
or stop the location record in your telephone camera.

Also read the archive. It can hold the first image with the GPS data, after you
replace the image on your site.

### `EXPIRED`

The registration stopped. Renew it now.

After the redemption period, any person can register the domain. That person then
gets your mail route and the good name of the domain.

---

## MEDIUM

### `PII-NAME`

Your name or your organization is public, but your location is not public.

You must decide about this result. It is not always a fault. For a company
domain, the name is normal, and it is sometimes necessary. For a personal
domain, the name links you to each service on the domain. If your name is not
common, the name can be enough for an attacker.

The correction is the same as the correction for `PII-STREET`.

Note one special condition. If the domain name **is** your name, redaction has almost
no value. The name is in the domain.

### `PII-EMAIL`

A real email address is public. Programs will collect the address in some days.
Then you will get false messages about the renewal of your domain, and messages
that give the name of your domain.

There are two corrections. Set the redaction control, and then the registrar
publishes a contact form. Or use a role address such as `domains@yourdomain`,
and then you can filter the messages.

### `ORIGIN-UNKNOWN` and `ORIGIN-NOWHOIS`

A hostname points to an address that is not a Cloudflare address. The tool could
not find the owner of the network.

The result means "the tool cannot decide". It does not mean "there is no
problem".

```bash
whois <ip> | grep -iE 'orgname|netname|descr|country|abuse'
dig +short -x <ip>              # the PTR record often gives the provider
```

If the network belongs to a consumer internet service provider, use the
correction for `ORIGIN-RESIDENTIAL`.

If the network belongs to a data center company that the tool does not know, add
the name to `DATACENTER_PATTERNS` in `lib/classify.sh`. Add a test to
`tests/test-classify.sh`. Then run the tests:

```bash
./tests/test-classify.sh
```

For `ORIGIN-NOWHOIS`, install the `whois` program and run the tool again.

### `HTTP-ORIGIN-HEADER`

Your headers can give the name of your origin server. Then the proxy does not
protect you, and your DNS records make no difference.

```nginx
# Remove the headers that give the name of the origin server.
proxy_hide_header X-Real-IP;
proxy_hide_header X-Served-By;
more_clear_headers 'X-Powered-By' 'Via';   # needs the headers-more module
```

At Cloudflare, use a Transform Rule. Select Modify Response Header, then Remove.
This method needs no change at your server.

### `HTTP-AUTHORS`

A person can get a list of your WordPress user names at
`/wp-json/wp/v2/users` or at `/?author=1`. The list holds the display names. A
display name is often a real name, on a site that gives no other personal data.

```php
// Stop the users endpoint for a person who is not logged in.
add_filter('rest_endpoints', function ($endpoints) {
    if (!is_user_logged_in()) {
        unset($endpoints['/wp/v2/users']);
        unset($endpoints['/wp/v2/users/(?P<id>[\d]+)']);
    }
    return $endpoints;
});
// Stop the redirect from ?author=N to /author/<username>/.
add_action('template_redirect', function () {
    if (is_author()) { wp_redirect(home_url(), 301); exit; }
});
```

Also give each user a display name that is different from the login name.

### `NO-CAA`

Without a CAA record, any certificate authority can make a certificate for your
domain. See [DNS records to copy](#dns-records-to-copy).

### `NO-SPF`, `NO-DMARC`, and `DMARC-NONE`

A person can send mail that shows your domain as the sender.

Many persons do not understand `p=none`. That policy only makes reports. It stops
no mail, but a DMARC record is present.

If the domain sends no mail, use the null MX configuration in the next section.
It is the strongest method.

### `NO-TRANSFER-LOCK`

The status `clientTransferProhibited` is absent. Therefore a person can move your
domain more easily. Set the lock in the control panel of your registrar. It is
one control. After that, a transfer needs two steps.

Also make sure that your registrar account uses a TOTP code or a hardware key. A
person takes control of a domain through the account more often than through the
registry.

### `EXPIRY-SOON`

The registration stops in fewer than 45 days. Renew it, and set automatic
renewal. Also look at the payment card in your account. An old card is the usual
cause of an accidental stop.

### `ARCHIVE-PRESENT`

The archive holds copies of your pages. They can show data that you removed.

1. Read the pages. The number of pages is not important. The content is
   important.
   `https://web.archive.org/web/*/<domain>/*`
2. Look for a contact page, a legal notice, a work history document, a telephone
   number in a page footer, and the old images.
3. If a page holds personal data, send a removal request to `info@archive.org`.
   Tell them which page it is, and tell them the reason. The Internet Archive
   usually accepts a request for personal data. It needs some time.
4. Do the same for `archive.today`. That service has its own process.

### `RDAP-UNREADABLE`, `RDAP-HTTP`, `RDAP-REGISTRAR`, `CT-UNAVAILABLE`, and `ARCHIVE-UNAVAILABLE`

The tool could not check something on this run. This is not a result about your
domain. It is a gap in the checks. Run the tool again. If the error continues,
send the query yourself.

`RDAP-REGISTRAR` needs a second look. The registry gave the address of the RDAP
server of your registrar, and that server gave no useful answer. Therefore the
contact results come from the **registry** record. A registry publishes almost no
data. A good result under this condition has almost no value.

```bash
curl -sL -H 'Accept: application/rdap+json' <registrar-rdap-address> | jq .
```

`CT-UNAVAILABLE` is almost always a request limit at crt.sh.
`ARCHIVE-UNAVAILABLE` means that the Wayback CDX service did not answer in time.

### `HTTP-EXPOSED-MINOR`

A path gave the code 200. The path is not clearly dangerous, but it is also not
clearly necessary. Three examples are a status page, an editor file, and an old
file.

Get the path and read it. If the path must be public, do nothing. If the path is
an old file such as `.swp`, `.old`, `.bak`, or `phpinfo.php`, delete the file.
Then add the file extension to the rules under [`HTTP-EXPOSED`](#http-exposed).
The next old file is then not public.

### `DNS-NO-NS`

No `NS` record answers. The zone has a fault, or the domain has no registration.
Correct this first. This fault also makes the other checks wrong.

---

## LOW

You must know about these results. For most of them, you do nothing.

| Code | Note |
|------|------|
| `RDAP-NO-REGISTRANT` | This is the best result for a registration record. |
| `RDAP-REDACTED` | The redaction works. |
| `RDAP-REGION` | ICANN rules make this necessary. No registrar and no TLD can hide it. The region is the smallest area that you can hide. |
| `RDAP-COUNTRY` | The same as `RDAP-REGION`. |
| `RDAP-TEL` | Make sure that the number belongs to the registrar and not to you. |
| `RDAP-NO-RELATED` | The tool could not check your contact data at the registrar. Query the RDAP server of your registrar yourself. This is not a good result. |
| `CT-HOSTNAMES` | You cannot remove a name from a log. Give less information in the future. Use a wildcard certificate for each host. Or operate a private certificate authority for your internal hosts. Then their names are never in a public log. |
| `CT-MIXED` | You have a wildcard certificate, and you also make a certificate for each host. Use the wildcard certificate only. |
| `ORIGIN-DATACENTER` | A person can reach your origin server directly. This is not your home address. Use the proxy, and permit connections from the proxy ranges only. |
| `NO-ADDRESS-RECORDS` | No name points to an address. An attacker can find no origin. |
| `SOA-RNAME` | If this is your personal mailbox, use a role address. |
| `SPF-SOFT` | The record ends with `~all` or `?all`. Use `-all` if no other host sends your mail. |
| `DMARC-QUARANTINE` | This policy is good. The policy `p=reject` is stronger. |
| `NO-DNSSEC` | Set DNSSEC if your DNS company has a simple control for it. |
| `NO-UPDATE-LOCK` | This lock adds one step to a change of your contact data. It is optional. |
| `HTTP-SERVER-VERSION` | Remove the version number. In nginx, use `server_tokens off;`. |
| `ARCHIVE-NONE` | The Wayback Machine holds no copy. The tool does not query the other archives. |
| `SHODAN-INDEXED` | Read the list of open ports. Stop each port that you do not need. |
| `RDAP-NOTFOUND` | The registry says that the domain has no registration. Look for an error in the name, or the registration stopped. |

---

## DNS records to copy

Add these records as DNS-only records. Do not send them through the proxy. Put
your own certificate authority and your own address in them.

### CAA — the authorities that you permit

```
example.com.  CAA  0 issue "letsencrypt.org"
example.com.  CAA  0 issuewild "letsencrypt.org"
example.com.  CAA  0 iodef "mailto:security@example.com"
```

Add one `issue` line for each authority that you use. If you use the Cloudflare
universal certificate, the group of authorities includes `pki.goog`,
`letsencrypt.org`, and `ssl.com`.

Be careful. If you do not name an authority that you use, your next certificate
will fail. Look at your certificates first. Some DNS companies have a control
that adds the correct CAA records for you. Use that control.

### A domain that sends no mail

These four records are the strongest statement:

```
example.com.            MX    0 .
example.com.            TXT   "v=spf1 -all"
_dmarc.example.com.     TXT   "v=DMARC1; p=reject; aspf=s; adkim=s;"
_domainkey.example.com. TXT   "v=DKIM1; p="
```

The record `MX 0 .` is the null MX of RFC 7505. It says that the domain accepts
no mail. This is stronger than a domain with no `MX` record. The empty DKIM
record says that no key is valid.

### A domain that sends mail

```
example.com.        TXT  "v=spf1 include:_spf.your-provider.com -all"
_dmarc.example.com. TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@example.com; aspf=s; adkim=s;"
```

Start with `p=none` and the `rua=` field. Read the reports for two weeks. Make
sure that no correct message fails. Then change the policy to `p=reject`.

Be careful. Do not start with `p=reject` on a domain that sends real mail. Your
mail will stop, and you will get no message about it.

### After each change

```bash
./domain-exposure-audit.sh example.com               # make sure the result is gone
./domain-exposure-audit.sh example.com --baseline    # accept the new state
```
