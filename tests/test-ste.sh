#!/usr/bin/env bash
#
# tests/test-ste.sh — check this project against ASD-STE100 Simplified
# Technical English.
#
# The checker tests the rules that a program can test. It cannot test the full
# Dictionary, idioms, noun clusters, or the active voice. A person must check
# those. See docs/STE-COMPLIANCE.md Section 7.
#
# Run:  ./tests/test-ste.sh
#       ./tests/test-ste.sh --notes    (also show the manual review notes)
#
# Exit code: 0 if there are no failures, 1 if there is one failure or more.
#
# To stop the checker for a region of a file, put a marker in the text. Use
# this only for text that must show a word that STE removed, for example the
# substitution table in docs/STE-COMPLIANCE.md.
#
#     <!-- ste-check: off -->    ... text ...    <!-- ste-check: on -->
#     # ste-check: off           ... text ...    # ste-check: on

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SHOW_NOTES=0
[ "${1:-}" = "--notes" ] && SHOW_NOTES=1

FAILS=0
NOTES=0

red()   { printf '\033[31m%s\033[0m' "$1"; }
yell()  { printf '\033[33m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m' "$1"; }

fail() { # fail FILE LINE RULE TEXT
  FAILS=$((FAILS + 1))
  printf '%s %s:%s  %s\n      %s\n' "$(red 'FAIL')" "$1" "$2" "$(dim "$3")" "$4"
}
note() { # note FILE LINE RULE TEXT
  NOTES=$((NOTES + 1))
  [ "$SHOW_NOTES" -eq 1 ] &&
    printf '%s %s:%s  %s\n      %s\n' "$(yell 'NOTE')" "$1" "$2" "$(dim "$3")" "$4"
  return 0
}

# ---------------------------------------------------------------------------
# Word lists
# ---------------------------------------------------------------------------

# Rule: do not use contractions.
CONTRACTIONS="do not use contractions"
RE_CONTRACTION="\\b([A-Za-z]+n't|[A-Za-z]+'(ll|re|ve|d|s|m))\\b"

# Rule 3.4: do not use the -ing form, except in a Technical Name.
# These words end in "ing" but are not verb forms, or they are Technical Names
# from docs/STE-COMPLIANCE.md Section 3.
ING_ALLOWED="during|string|strings|thing|things|nothing|something|anything|everything|bring|ring|spring|ping|king|wing|sing"

# Rule 3.5: do not use complex tenses.
RE_COMPLEX_TENSE="\\b(ha(s|ve|d) been|ha(s|ve|d) not been|will have been|ha(s|ve|d) [a-z]+ed)\\b"

# Rule 1.1 with docs/STE-COMPLIANCE.md Section 5: words this project removed.
RE_REMOVED="\\b(via|utiliz(e|es|ed)|prior to|subsequent to|in order to|in the event|assist(s|ed)?|obtain(s|ed)?|requires?|required|requirements?|attempts?|attempted|commences?|terminates?|sufficient|additional|approximately|currently|deliberately|aggressively|catastrophic|adversar(y|ies)|granularity|residual|reconnaissance|mitigates?|unmask(s|ed)?|leverages?|seamless|robustly)\\b"

# STE removes vague words and intensifiers. They add no information.
RE_VAGUE="\\b(very|quite|just|simply|actually|basically|essentially|obviously|rather|fairly|somewhat|really|nice|good enough)\\b"

# Punctuation rules.
RE_BAD_PUNCT="(\\be\\.g\\.|\\bi\\.e\\.|\\betc\\.|&)"

# ---------------------------------------------------------------------------
# Prose extraction
# ---------------------------------------------------------------------------
# Emits "LINENO<TAB>KIND<TAB>TEXT" where KIND is "prose" or "cell".
# Table cells are checked for words but not for sentence length, because a
# pipe-separated row is not one sentence.

extract_md() { # extract_md FILE
  awk '
    BEGIN { fence = 0; off = 0 }
    {
      line = $0
      if (line ~ /ste-check:[[:space:]]*off/) { off = 1; next }
      if (line ~ /ste-check:[[:space:]]*on/)  { off = 0; next }
      if (off) next
      if (line ~ /^[[:space:]]*```/) { fence = 1 - fence; next }
      if (fence) next
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^#+ /) next                       # headings
      gsub(/`[^`]*`/, "CODE", line)                 # inline code spans
      gsub(/\[([^]]*)\]\([^)]*\)/, "\\1", line)     # link targets
      gsub(/^[[:space:]]*[-*+][[:space:]]+/, "", line)
      gsub(/^[[:space:]]*[0-9]+\.[[:space:]]+/, "", line)
      gsub(/\*\*/, "", line); gsub(/\*/, "", line)
      if (line ~ /^[[:space:]]*\|/) { print NR "\tcell\t" line; next }
      if (line ~ /^[[:space:]]*$/) next
      print NR "\tprose\t" line
    }
  ' "$1"
}

# Shell and unit files: only comments and the help text are natural language.
extract_sh() { # extract_sh FILE
  awk '
    BEGIN { here = 0; off = 0 }
    {
      line = $0
      if (line ~ /ste-check:[[:space:]]*off/) { off = 1; next }
      if (line ~ /ste-check:[[:space:]]*on/)  { off = 0; next }
      if (off) next
      if (line ~ /<<[-]?.?EOF.?/) { here = 1; next }
      if (here && line ~ /^EOF$/) { here = 0; next }
      if (here) { print NR "\tprose\t" line; next }
      if (line ~ /^[[:space:]]*#!/) next
      if (line ~ /^[[:space:]]*#/) {
        sub(/^[[:space:]]*#[[:space:]]?/, "", line)
        if (line ~ /^[[:space:]]*$/) next
        if (line ~ /^-+$/) next
        print NR "\tprose\t" line
        next
      }
      # Message text inside add_result and say calls.
      if (line ~ /add_result [A-Z]+ [A-Z0-9-]+ "/ || line ~ /say "/) {
        n = split(line, parts, "\"")
        out = ""
        for (i = 2; i <= n; i += 2) out = out " " parts[i]
        gsub(/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/, "X", out)
        gsub(/\$\([^)]*\)/, "X", out)
        if (out ~ /[A-Za-z]{4}/) print NR "\tprose\t" out
      }
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

check_words() { # check_words FILE LINENO TEXT
  local f="$1" n="$2" t="$3" hit

  hit="$(printf '%s' "$t" | grep -oEi "$RE_CONTRACTION" | head -1)"
  [ -n "$hit" ] && fail "$f" "$n" "punctuation: $CONTRACTIONS" "found '$hit' in: $t"

  hit="$(printf '%s' "$t" | grep -oEi "$RE_COMPLEX_TENSE" | head -1)"
  [ -n "$hit" ] && fail "$f" "$n" "rule 3.5: use simple tenses" "found '$hit' in: $t"

  hit="$(printf '%s' "$t" | grep -oEi "$RE_REMOVED" | head -1)"
  [ -n "$hit" ] && fail "$f" "$n" "rule 1.1: word not approved" "found '$hit' in: $t"

  hit="$(printf '%s' "$t" | grep -oEi "$RE_VAGUE" | head -1)"
  [ -n "$hit" ] && fail "$f" "$n" "rule 1.1: vague word" "found '$hit' in: $t"

  hit="$(printf '%s' "$t" | grep -oE "$RE_BAD_PUNCT" | head -1)"
  [ -n "$hit" ] && fail "$f" "$n" "punctuation" "found '$hit' in: $t"

  # Rule 3.4: -ing forms.
  local w
  for w in $(printf '%s' "$t" | grep -oE '\b[A-Za-z]{5,}ing\b' | tr '[:upper:]' '[:lower:]' | sort -u); do
    printf '%s' "$w" | grep -qxE "$ING_ALLOWED" && continue
    fail "$f" "$n" "rule 3.4: no -ing form" "found '$w' in: $t"
  done

  # The oblique between words, not in a path or a command.
  if printf '%s' "$t" | grep -qE '[A-Za-z]{3,}/[A-Za-z]{3,}'; then
    printf '%s' "$t" | grep -qE '(https?:|/mnt|/home|/usr|/etc|\.(sh|md|json|conf|com|net|org)|CODE|\$[A-Z_]|docs/|lib/|tests/|examples/)' ||
      note "$f" "$n" "punctuation: no oblique in text" "$t"
  fi
}

check_sentence_length() { # check_sentence_length FILE LINENO TEXT
  local f="$1" n="$2" t="$3"
  # Protect the periods that do not end a sentence.
  local p
  p="$(printf '%s' "$t" \
     | sed -E 's/([0-9])\.([0-9])/\1@\2/g' \
     | sed -E 's/\.(sh|md|json|conf|com|net|org|wtf|us|io)\b/@\1/g' \
     | sed -E 's/\b([A-Z])\./\1@/g')"
  printf '%s' "$p" | sed -E 's/([.!?])[[:space:]]+/\1\n/g' | while IFS= read -r s; do
    [ -n "$s" ] || continue
    local wc
    wc="$(printf '%s' "$s" | tr -s '[:space:]' '\n' | grep -c '[A-Za-z0-9]')"
    if [ "$wc" -gt 25 ]; then
      fail "$f" "$n" "rule 4.2: 25 words maximum, found $wc" "$(printf '%s' "$s" | cut -c1-110)"
    fi
  done
}

check_paragraphs() { # check_paragraphs FILE
  local f="$1"
  awk '
    BEGIN { fence = 0; sent = 0; start = 0 }
    function flush() {
      if (sent > 6) printf "%d\t%d\n", start, sent
      sent = 0; start = 0
    }
    {
      if ($0 ~ /^[[:space:]]*```/) { fence = 1 - fence; flush(); next }
      if (fence) next
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^#+ / || $0 ~ /^[[:space:]]*\|/) { flush(); next }
      # Rule 4.4 recommends vertical lists, therefore a list item is its own
      # unit and not part of a paragraph. Each item starts a new count.
      if ($0 ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/) { flush() }
      if (start == 0) start = NR
      line = $0
      gsub(/[0-9]\.[0-9]/, "", line)
      n = gsub(/[.!?]([[:space:]]|$)/, "", line)
      sent += n
    }
    END { flush() }
  ' "$f" | while IFS=$'\t' read -r ln count; do
    fail "$f" "$ln" "rule 4.5: 6 sentences maximum in a paragraph, found $count" \
         "the paragraph that starts at this line is too long"
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

printf '\n%s\n' "$(dim 'ASD-STE100 check — see docs/STE-COMPLIANCE.md for the rules applied')"

cd "$ROOT" || exit 1

MD_FILES=(README.md CHANGELOG.md docs/CHECKS.md docs/REMEDIATION.md
          docs/STE-COMPLIANCE.md)
SH_FILES=(domain-exposure-audit.sh lib/classify.sh tests/test-classify.sh
          tests/test-parsing.sh tests/test-ste.sh
          examples/notify-desktop.sh domains.conf.example
          examples/domain-exposure-audit.service examples/domain-exposure-audit.timer)

for f in "${MD_FILES[@]}"; do
  [ -f "$f" ] || continue
  printf '\n%s\n' "$(dim "-- $f")"
  while IFS=$'\t' read -r n kind text; do
    check_words "$f" "$n" "$text"
    [ "$kind" = "prose" ] && check_sentence_length "$f" "$n" "$text"
  done < <(extract_md "$f")
  check_paragraphs "$f"
done

for f in "${SH_FILES[@]}"; do
  [ -f "$f" ] || continue
  printf '\n%s\n' "$(dim "-- $f")"
  while IFS=$'\t' read -r n kind text; do
    check_words "$f" "$n" "$text"
    [ "$kind" = "prose" ] && check_sentence_length "$f" "$n" "$text"
  done < <(extract_sh "$f")
done

printf '\n'
if [ "$FAILS" -eq 0 ]; then
  printf '%s\n' "$(green "0 failures. $NOTES note(s) for manual review.")"
  [ "$SHOW_NOTES" -eq 0 ] && [ "$NOTES" -gt 0 ] &&
    printf '%s\n' "$(dim 'Run with --notes to see them.')"
  printf '\n'
  exit 0
else
  printf '%s\n\n' "$(red "$FAILS failure(s), $NOTES note(s).")"
  exit 1
fi
