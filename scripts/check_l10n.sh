#!/usr/bin/env bash
# Localization guard for lib/l10n/app_{en,ja,zh}.arb and the UI code.
#
#   1. Dead keys: a key in app_en.arb that is never referenced as `.keyName`
#      anywhere in lib/ outside lib/l10n fails. Keys that are legitimately
#      reached some other way (built by string, looked up by name) go into
#      scripts/l10n_dead_key_allowlist.txt, one per line, with a `#` comment
#      saying why.
#   2. Key parity: app_en.arb, app_ja.arb and app_zh.arb must define exactly
#      the same keys.
#   3. Hardcoded-string ratchet: counts user-visible string literals in lib/
#      (excluding lib/l10n and generated files) per file and compares them with
#      scripts/l10n_hardcoded_baseline.txt. Counted: `Text('...')`,
#      `tooltip:`, `hintText:`, `labelText:`, `helperText:`, `semanticLabel:`
#      and the message of showAppSnackBar / showErrorSnackBar /
#      showSuccessSnackBar, when the literal (after removing `$interpolation`
#      and escapes) holds two or more consecutive letters. A line carrying
#      `// l10n-ignore: <reason>` is skipped; use it only for text that must
#      not be translated (brand names, protocol values, each language's own
#      name, prompt tags). Any increase fails; decreases ask for a baseline
#      update, so the numbers only ever go down.
#
#   scripts/check_l10n.sh           run all checks
#   scripts/check_l10n.sh --update  rewrite the hardcoded-string baseline
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/scripts/l10n_hardcoded_baseline.txt"
ALLOWLIST="$ROOT/scripts/l10n_dead_key_allowlist.txt"
cd "$ROOT"

# Prints "<file>\t<count>" for every file with hardcoded strings, sorted.
count_hardcoded() {
  find lib -name '*.dart' -not -path 'lib/l10n/*' -not -name '*.g.dart' \
    -not -name '*.freezed.dart' -print0 | sort -z \
    | xargs -0 perl "$ROOT/scripts/l10n_hardcoded_strings.pl" | LC_ALL=C sort
}

if [[ "${1:-}" == "--update" ]]; then
  current="$(count_hardcoded)"
  printf '%s\n' "$current" | sed '/^$/d' >"$BASELINE"
  echo "Baseline updated: $(awk -F'\t' '{s+=$2} END {print s+0}' "$BASELINE") hardcoded strings in $BASELINE"
  exit 0
fi

status=0

# ---- 1 + 2: dead keys and key parity ----------------------------------
perl -e '
  use strict;
  use warnings;
  use utf8;
  my ($root, $allowlist) = @ARGV;

  sub arb_keys {
    my ($path) = @_;
    open(my $fh, "<:encoding(UTF-8)", $path) or die "cannot read $path: $!\n";
    my %k;
    while (my $ln = <$fh>) {
      $k{$1} = 1 if $ln =~ /^  "([A-Za-z0-9_]+)"\s*:/;
    }
    return %k;
  }

  my %en = arb_keys("$root/lib/l10n/app_en.arb");
  my $fail = 0;

  for my $loc (qw(ja zh)) {
    my %o = arb_keys("$root/lib/l10n/app_$loc.arb");
    my @missing = sort grep { !$o{$_} } keys %en;
    my @extra   = sort grep { !$en{$_} } keys %o;
    if (@missing) {
      print STDERR "app_$loc.arb is missing " . scalar(@missing) . " key(s) present in app_en.arb:\n";
      print STDERR "  $_\n" for @missing;
      $fail = 1;
    }
    if (@extra) {
      print STDERR "app_$loc.arb has " . scalar(@extra) . " key(s) not in app_en.arb:\n";
      print STDERR "  $_\n" for @extra;
      $fail = 1;
    }
  }

  my %allowed;
  if (open(my $af, "<:encoding(UTF-8)", $allowlist)) {
    while (my $ln = <$af>) {
      $ln =~ s/#.*//;
      $ln =~ s/^\s+|\s+$//g;
      $allowed{$ln} = 1 if length $ln;
    }
    close $af;
  }

  my %used;
  my @files = split(/\0/, `find "$root/lib" -name "*.dart" -not -path "$root/lib/l10n/*" -print0`);
  for my $f (@files) {
    open(my $fh, "<:encoding(UTF-8)", $f) or next;
    local $/;
    my $s = <$fh>;
    close $fh;
    $used{$1} = 1 while $s =~ /\.([A-Za-z_][A-Za-z0-9_]*)/g;
  }

  my @dead = sort grep { !$used{$_} && !$allowed{$_} } keys %en;
  if (@dead) {
    print STDERR "Dead ARB keys (never referenced as .keyName in lib/ outside lib/l10n):\n";
    print STDERR "  $_\n" for @dead;
    print STDERR "Delete them from all three ARB files, or justify a dynamic use in scripts/l10n_dead_key_allowlist.txt.\n";
    $fail = 1;
  }
  my @stale = sort grep { $used{$_} && $allowed{$_} } keys %allowed;
  for my $k (@stale) {
    print STDERR "note: $k is in the allowlist but is now referenced directly; you can drop it.\n";
  }
  exit $fail;
' "$ROOT" "$ALLOWLIST" || status=1

# ---- 3: hardcoded-string ratchet --------------------------------------
current="$(count_hardcoded)"

if [[ ! -f "$BASELINE" ]]; then
  echo "Missing $BASELINE; run scripts/check_l10n.sh --update" >&2
  exit 2
fi

report="$(awk -F'\t' '
  FILENAME == ARGV[1] { if (NF == 2) base[$1] = $2; next }
  NF == 2 {
    seen[$1] = 1
    b = ($1 in base) ? base[$1] : 0
    if ($2 > b) printf "INCREASE\t%s\t+%d (baseline %d, now %d)\n", $1, $2 - b, b, $2
    else if ($2 < b) printf "DECREASE\t%s\t-%d (baseline %d, now %d)\n", $1, b - $2, b, $2
  }
  END {
    for (f in base) if (!(f in seen)) printf "DECREASE\t%s\t-%d (baseline %d, now 0)\n", f, base[f], base[f]
  }
' "$BASELINE" <(printf '%s\n' "$current") | LC_ALL=C sort)"

increases="$(printf '%s\n' "$report" | grep '^INCREASE' || true)"
decreases="$(printf '%s\n' "$report" | grep '^DECREASE' || true)"

if [[ -n "$increases" ]]; then
  echo "Hardcoded user-visible strings increased; move them to lib/l10n/app_{en,ja,zh}.arb:" >&2
  printf '%s\n' "$increases" | awk -F'\t' '{printf "  %s  %s\n", $2, $3}' >&2
  status=1
fi

if [[ -n "$decreases" ]]; then
  echo "Hardcoded strings went down; lock it in with: scripts/check_l10n.sh --update"
  printf '%s\n' "$decreases" | awk -F'\t' '{printf "  %s  %s\n", $2, $3}'
fi

if [[ $status -ne 0 ]]; then
  exit 1
fi
echo "Localization checks OK."
