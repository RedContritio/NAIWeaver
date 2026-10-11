#!/usr/bin/env bash
# Ratchet for the UI conventions in ARCHITECTURE.md ("UI Conventions").
#
# Counts convention violations per file and per category under lib/ and
# compares them with scripts/ui_conventions_baseline.txt. Any increase (or a
# violation in a file that had none) fails; decreases ask for a baseline
# update, so the numbers only ever go down.
#
#   scripts/check_ui_conventions.sh           check against the baseline
#   scripts/check_ui_conventions.sh --update  rewrite the baseline
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/scripts/ui_conventions_baseline.txt"
cd "$ROOT"

# Prints "<file>\t<category>\t<count>" for every non-zero count, sorted.
count_violations() {
  find lib -name '*.dart' -print0 | sort -z | xargs -0 perl -e '
    my @cats = (
      ["Colors.",          sub { my ($s) = @_; scalar(() = $s =~ /\bColors\.(?!transparent\b)/g) }],
      ["Color(0x",         sub { my ($s) = @_; scalar(() = $s =~ /\bColor\(0x/g) }],
      ["fontSize:number",  sub { my ($s) = @_; scalar(() = $s =~ /\bfontSize:\s*\d/g) }],
      ["Theme.colorScheme",sub { my ($s) = @_; scalar(() = $s =~ /Theme\.of\(context\)\.colorScheme/g) }],
      ["showModalBottomSheet", sub { my ($s, $f) = @_;
          return 0 if $f =~ m{^lib/core/widgets/ui/};
          scalar(() = $s =~ /\bshowModalBottomSheet\s*[<(]/g) }],
      ["SnackBar(",        sub { my ($s, $f) = @_;
          return 0 if $f =~ m{/app_snackbar\.dart$};
          scalar(() = $s =~ /(?<![A-Za-z])SnackBar\(/g) }],
      ["MediaQuery.width<number", sub { my ($s) = @_;
          scalar(() = $s =~ /MediaQuery\.of\(context\)\.size\.width\s*[<>]=?\s*\d/g)
        + scalar(() = $s =~ /MediaQuery\.sizeOf\(context\)\.width\s*[<>]=?\s*\d/g) }],
    );
    for my $f (@ARGV) {
      open(my $fh, "<", $f) or next;
      local $/;
      my $s = <$fh>;
      close $fh;
      for my $c (@cats) {
        my $n = $c->[1]->($s, $f);
        print "$f\t$c->[0]\t$n\n" if $n > 0;
      }
    }
  ' | LC_ALL=C sort
}

current="$(count_violations)"

if [[ "${1:-}" == "--update" ]]; then
  printf '%s\n' "$current" >"$BASELINE"
  echo "Baseline updated: $(printf '%s\n' "$current" | awk -F'\t' '{s+=$3} END {print s+0}') violations in $BASELINE"
  exit 0
fi

if [[ ! -f "$BASELINE" ]]; then
  echo "Missing $BASELINE; run scripts/check_ui_conventions.sh --update" >&2
  exit 2
fi

report="$(awk -F'\t' '
  FNR == NR { if (NF == 3) base[$1 "\t" $2] = $3; next }
  NF == 3 {
    key = $1 "\t" $2
    seen[key] = 1
    b = (key in base) ? base[key] : 0
    if ($3 > b) printf "INCREASE\t%s\t%s\t+%d (baseline %d, now %d)\n", $1, $2, $3 - b, b, $3
    else if ($3 < b) printf "DECREASE\t%s\t%s\t-%d (baseline %d, now %d)\n", $1, $2, b - $3, b, $3
  }
  END {
    for (key in base) if (!(key in seen)) {
      split(key, p, "\t")
      printf "DECREASE\t%s\t%s\t-%d (baseline %d, now 0)\n", p[1], p[2], base[key], base[key]
    }
  }
' "$BASELINE" <(printf '%s\n' "$current") | LC_ALL=C sort)"

increases="$(printf '%s\n' "$report" | grep '^INCREASE' || true)"
decreases="$(printf '%s\n' "$report" | grep '^DECREASE' || true)"

if [[ -n "$increases" ]]; then
  echo "UI convention violations increased (see ARCHITECTURE.md, UI Conventions):" >&2
  printf '%s\n' "$increases" | awk -F'\t' '{printf "  %s  [%s]  %s\n", $2, $3, $4}' >&2
  exit 1
fi

if [[ -n "$decreases" ]]; then
  echo "Violations went down; lock it in with: scripts/check_ui_conventions.sh --update"
  printf '%s\n' "$decreases" | awk -F'\t' '{printf "  %s  [%s]  %s\n", $2, $3, $4}'
fi
echo "UI conventions OK."
