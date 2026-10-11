#!/usr/bin/env perl
# Helper for scripts/check_l10n.sh: finds hardcoded user-visible string
# literals in Dart files.
#
#   perl scripts/l10n_hardcoded_strings.pl FILE...          "<file>\t<count>"
#   perl scripts/l10n_hardcoded_strings.pl --list FILE...   "<file>:<line>: <text>"
#
# See the header of check_l10n.sh for what counts.
use strict;
use warnings;
use utf8;

binmode(STDOUT, ':utf8');

my $call = qr{
    (?<![A-Za-z0-9_.])Text\(\s*(?:const\s+)?
  | \b(?:tooltip|hintText|labelText|helperText|semanticLabel)\s*:\s*(?:const\s+)?
  | \bshow(?:App|Error|Success)?SnackBar\(\s*[A-Za-z_.]+\s*,\s*
}x;

# Reads the string literal starting at $i (on its opening quote). Returns the
# literal text without `$interpolation` and escapes, and the index after the
# closing quote; (undef, $i) when it is not a single-line literal.
sub literal {
    my ($s, $i) = @_;
    my $q = substr($s, $i, 1);
    my $len = length $s;
    my $out = '';
    $i++;
    while ($i < $len) {
        my $c = substr($s, $i, 1);
        if ($c eq '\\') {
            my $rest = substr($s, $i + 1, 8);
            if ($rest =~ /^u\{[0-9A-Fa-f]+\}/ || $rest =~ /^u[0-9A-Fa-f]{4}/ || $rest =~ /^x[0-9A-Fa-f]{2}/) {
                $i += 1 + length($&);
            } else {
                $i += 2;
            }
            next;
        }
        return ($out, $i + 1) if $c eq $q;
        return (undef, $i) if $c eq "\n";
        if ($c eq '$') {
            my $n = substr($s, $i + 1, 1);
            if ($n eq '{') {
                my $depth = 1;
                $i += 2;
                while ($i < $len && $depth > 0) {
                    my $c2 = substr($s, $i, 1);
                    if ($c2 eq '{') { $depth++; }
                    elsif ($c2 eq '}') { $depth--; }
                    elsif ($c2 eq "'" || $c2 eq '"') {
                        my (undef, $j) = literal($s, $i);
                        $i = $j;
                        next;
                    }
                    $i++;
                }
                next;
            }
            if ($n =~ /[A-Za-z_]/) {
                $i++;
                $i++ while $i < $len && substr($s, $i, 1) =~ /[A-Za-z0-9_]/;
                next;
            }
        }
        $out .= $c;
        $i++;
    }
    return (undef, $i);
}

my $list = (@ARGV && $ARGV[0] eq '--list') ? shift(@ARGV) : 0;
for my $f (@ARGV) {
    open(my $fh, '<:encoding(UTF-8)', $f) or next;
    local $/;
    my $s = <$fh>;
    close $fh;
    my @lines = split(/\n/, $s, -1);
    my $n = 0;
    while ($s =~ /$call/g) {
        my $p = pos($s);
        my $c = substr($s, $p, 1);
        if ($c eq 'r' && substr($s, $p + 1, 1) =~ /['"]/) {
            $p++;
            $c = substr($s, $p, 1);
        }
        next unless $c eq "'" || $c eq '"';
        my ($text, $end) = literal($s, $p);
        next unless defined $text;
        next unless $text =~ /\p{L}{2,}/;
        my $line = 1 + (substr($s, 0, $p) =~ tr/\n//);
        next if $lines[$line - 1] =~ /l10n-ignore/;
        $n++;
        print "$f:$line: $text\n" if $list;
    }
    print "$f\t$n\n" if $n > 0 && !$list;
}
