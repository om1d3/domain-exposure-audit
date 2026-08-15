#!/usr/bin/env bash
#
# tests/test-ste.sh – check this project against ASD-STE100 Simplified
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

# The bytes of the two dash characters, in UTF-8. printf with an octal escape
# gives the same bytes in each locale.
EM_DASH="$(printf '\342\200\224')"
EN_DASH="$(printf '\342\200\223')"

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
        # 1.3.1: the placeholder is CODE and not X, and it is the same
        # placeholder that extract_md uses. A single capital letter and a
        # period look like an initial such as "J. Smith", therefore the test
        # for rule 4.2 protected that period and joined two sentences into one.
        gsub(/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/, "CODE", out)
        gsub(/\$\([^)]*\)/, "CODE", out)
        if (out ~ /[A-Za-z]{4}/) print NR "\tprose\t" out
      }
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

# 1.3.1: bash tests each pattern itself. The earlier form started an external
# program for each pattern and each line: about 20 processes for one line, and
# more than 64000 processes for a full run. The system time was more than two
# minutes, and almost all of it was the cost of the processes. Bash gives the
# same answers with no process at all, because the operator =~ uses the same
# regular expression library that grep -E uses.
RE_OBLIQUE="[A-Za-z]{3,}/[A-Za-z]{3,}"
RE_OBLIQUE_OK="(https?:|/mnt|/home|/usr|/etc|\\.(sh|md|json|conf|com|net|org)|CODE|\\\$[A-Z_]|docs/|lib/|tests/|examples/)"

check_words() { # check_words FILE LINENO TEXT
  local f="$1" n="$2" t="$3" w lw seen=""

  # grep -i gave the case-insensitive tests. nocasematch gives the same.
  shopt -s nocasematch
  [[ $t =~ $RE_CONTRACTION ]]   && fail "$f" "$n" "punctuation: $CONTRACTIONS"    "found '${BASH_REMATCH[0]}' in: $t"
  [[ $t =~ $RE_COMPLEX_TENSE ]] && fail "$f" "$n" "rule 3.5: use simple tenses"   "found '${BASH_REMATCH[0]}' in: $t"
  [[ $t =~ $RE_REMOVED ]]       && fail "$f" "$n" "rule 1.1: word not approved"   "found '${BASH_REMATCH[0]}' in: $t"
  [[ $t =~ $RE_VAGUE ]]         && fail "$f" "$n" "rule 1.1: vague word"          "found '${BASH_REMATCH[0]}' in: $t"
  shopt -u nocasematch

  # This test was case-sensitive before, therefore it stays case-sensitive.
  [[ $t =~ $RE_BAD_PUNCT ]]     && fail "$f" "$n" "punctuation"                   "found '${BASH_REMATCH[0]}' in: $t"

  # Rule 3.4: -ing forms. The earlier form used grep, tr, and sort. Bash splits
  # the line into words itself. set -f stops the shell from an expansion of a
  # character such as * in the text.
  set -f
  for w in $t; do
    w="${w//[^A-Za-z]/}"
    [ "${#w}" -ge 8 ] || continue            # 5 letters or more, and then "ing"
    lw="${w,,}"
    [ "${lw: -3}" = "ing" ] || continue
    [[ $lw =~ ^($ING_ALLOWED)$ ]] && continue
    case " $seen " in *" $lw "*) continue ;; esac    # sort -u, one time each
    seen="$seen $lw"
    fail "$f" "$n" "rule 3.4: no -ing form" "found '$lw' in: $t"
  done
  set +f

  # The oblique between words, not in a path or a command.
  if [[ $t =~ $RE_OBLIQUE ]] && [[ ! $t =~ $RE_OBLIQUE_OK ]]; then
    note "$f" "$n" "punctuation: no oblique in text" "$t"
  fi
}

# 1.3.1: one awk for each file, and not four programs for each line and three
# more for each sentence. check_paragraphs already used this design. The input
# is the output of extract_md or extract_sh: a line number, a kind, and a text.
# 1.3.1: the loop reads from a process substitution and not from a pipe. A
# pipe puts the loop in a subshell, therefore FAILS goes back to its old value
# when the loop ends. The tool then prints a failure and gives exit code 0.
check_sentences() { # check_sentences FILE EXTRACTED
  local f="$1" src="$2"
  while IFS=$'\t' read -r ln wc text; do
    fail "$f" "$ln" "rule 4.2: 25 words maximum, found $wc" "$text"
  done < <(awk -F'\t' '
    $2 != "prose" { next }
    {
      line = $3

      # Protect a period that does not end a sentence. awk gives no group in a
      # replacement, therefore each loop finds one period and changes it.
      while (match(line, /[0-9]\.[0-9]/))
        line = substr(line, 1, RSTART) "@" substr(line, RSTART + 2)

      while (match(line, /\.(sh|md|json|conf|com|net|org|wtf|us|io)([^A-Za-z0-9]|$)/))
        line = substr(line, 1, RSTART - 1) "@" substr(line, RSTART + 1)

      while (match(line, /(^|[^A-Za-z])[A-Z]\./)) {
        pos = RSTART + RLENGTH - 1
        line = substr(line, 1, pos - 1) "@" substr(line, pos + 1)
      }

      # One sentence on each line. The terminator stays with its sentence.
      gsub(/[.!?][[:space:]]+/, "&\n", line)

      ns = split(line, sentences, /\n/)
      for (i = 1; i <= ns; i++) {
        s = sentences[i]
        if (s == "") continue
        wc = 0
        nw = split(s, words, /[[:space:]]+/)
        for (j = 1; j <= nw; j++)
          if (words[j] ~ /[A-Za-z0-9]/) wc++
        if (wc > 25) printf "%s\t%d\t%s\n", $1, wc, substr(s, 1, 110)
      }
    }
  ' "$src")
}

# check_dashes FILE
# The em-dash is not permitted in this project. See docs/STE-COMPLIANCE.md.
# This function reads each raw line, and not the prose only. A heading can hold
# a dash, therefore a check of the prose does not find it.
check_dashes() {
  local f="$1" n line off=0
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *'ste-check: off'*) off=1; continue ;;
      *'ste-check: on'*)  off=0; continue ;;
    esac
    [ "$off" -eq 1 ] && continue

    # Rule: no em-dash, in any place.
    case "$line" in
      *"$EM_DASH"*) fail "$f" "$n" "punctuation: the em-dash is not permitted" \
                      "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-100)" ;;
    esac

    # Rule: an en-dash is a separator in a title or a heading only. A line that
    # ends with a full stop is a sentence. A dash in a sentence hides the
    # relationship between the two parts. Use a comma, a colon, or two
    # sentences.
    #
    # A dash between two backticks is a quotation of an example, and not
    # punctuation in a sentence. Therefore the check removes the text between
    # backticks first.
    # 1.3.1: this test starts no program. The earlier form removed the text
    # between backticks with sed, for each line of each file, before it looked
    # for an en-dash. That was 3 processes for each line, and most lines hold
    # no en-dash at all. The test for the en-dash now comes first, and bash
    # removes the backticks itself.
    case "$line" in
      *"$EN_DASH"*)
        local bare="$line" pre rest
        while [ "${bare#*\`}" != "$bare" ] && [ "${bare#*\`*\`}" != "$bare" ]; do
          pre="${bare%%\`*}"
          rest="${bare#*\`}"
          rest="${rest#*\`}"
          bare="$pre$rest"
        done
        case "$bare" in
          *"$EN_DASH"*)
            bare="${bare%"${bare##*[![:space:]]}"}"        # remove the trailing spaces
            case "$bare" in
              *.) fail "$f" "$n" "punctuation: no en-dash inside a sentence" \
                    "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-100)" ;;
            esac ;;
        esac ;;
    esac
  done < "$f"
}

# 1.3.1: the same correction as check_sentences. This bug was older: a
# paragraph with too many sentences printed a failure, and the tool still gave
# exit code 0.
check_paragraphs() { # check_paragraphs FILE
  local f="$1"
  while IFS=$'\t' read -r ln count; do
    fail "$f" "$ln" "rule 4.5: 6 sentences maximum in a paragraph, found $count" \
         "the paragraph that starts at this line is too long"
  done < <(awk '
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
  ' "$f")
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

printf '\n%s\n' "$(dim 'ASD-STE100 check – see docs/STE-COMPLIANCE.md for the rules applied')"

cd "$ROOT" || exit 1

TMP_EXTRACT="$(mktemp "${TMPDIR:-/tmp}/ste.XXXXXX")" || exit 1
trap 'rm -f "$TMP_EXTRACT"' EXIT INT TERM

MD_FILES=(README.md CHANGELOG.md docs/CHECKS.md docs/REMEDIATION.md
          docs/INTENT.md docs/STE-COMPLIANCE.md)
SH_FILES=(domain-exposure-audit.sh lib/classify.sh tests/test-classify.sh
          tests/test-parsing.sh tests/test-enrich.sh tests/test-ste.sh
          examples/notify-desktop.sh domains.conf.example
          examples/domain-exposure-audit.service examples/domain-exposure-audit.timer)

for f in "${MD_FILES[@]}"; do
  [ -f "$f" ] || continue
  printf '\n%s\n' "$(dim "-- $f")"
  extract_md "$f" > "$TMP_EXTRACT"
  while IFS=$'\t' read -r n kind text; do
    check_words "$f" "$n" "$text"
  done < "$TMP_EXTRACT"
  check_sentences "$f" "$TMP_EXTRACT"
  check_paragraphs "$f"
  check_dashes "$f"
done

for f in "${SH_FILES[@]}"; do
  [ -f "$f" ] || continue
  printf '\n%s\n' "$(dim "-- $f")"
  extract_sh "$f" > "$TMP_EXTRACT"
  while IFS=$'\t' read -r n kind text; do
    check_words "$f" "$n" "$text"
  done < "$TMP_EXTRACT"
  check_sentences "$f" "$TMP_EXTRACT"
  check_dashes "$f"
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
