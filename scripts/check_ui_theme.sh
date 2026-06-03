#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

perl - <<'PERL'
use strict;
use warnings;

my @files = split /\0/, `git ls-files -z mac-app`;
@files = grep { /\.swift$/ } @files;

my %globally_tinted_identifier;
for my $file (@files) {
    open my $fh, '<', $file or next;
    while (my $line = <$fh>) {
        if ($line =~ /\b([A-Za-z_][A-Za-z0-9_]*)\.contentTintColor\s*=/) {
            $globally_tinted_identifier{$1} = 1;
        }
    }
    close $fh;
}

my @failures;

for my $file (@files) {
    next if $file =~ m{/TemplateSymbolImage\.swift$};

    open my $fh, '<', $file or next;
    my @lines = <$fh>;
    close $fh;

    for (my $i = 0; $i < @lines; $i++) {
        my $line = $lines[$i];
        next if $line =~ /leafreader-theme-ok/;

        next unless $line =~ /\b([A-Za-z_][A-Za-z0-9_]*)\.image\s*=\s*(?:NSImage\s*\(\s*systemSymbolName|TemplateSymbolImage\.make)/;
        my $identifier = $1;

        next if $globally_tinted_identifier{$identifier};
        next if nearby_theme_handling(\@lines, $i, $identifier);

        push @failures, sprintf(
            "%s:%d: icon image assigned to `%s` without a visible theme tint path; set contentTintColor from the active ReaderTheme or add it to the surface theme refresh traversal",
            $file,
            $i + 1,
            $identifier
        );
    }
}

if (@failures) {
    print "UI theme checks failed:\n";
    print " - $_\n" for @failures;
    exit 1;
}

print "UI theme checks passed.\n";

sub nearby_theme_handling {
    my ($lines, $index, $identifier) = @_;
    my $start = $index - 6;
    $start = 0 if $start < 0;
    my $end = $index + 14;
    $end = $#$lines if $end > $#$lines;
    my $chunk = join '', @$lines[$start..$end];

    return 1 if $chunk =~ /\Q$identifier\E\.contentTintColor\s*=/;
    return 1 if $chunk =~ /\Q$identifier\E\.theme\s*=/;
    return 1 if $chunk =~ /let\s+\Q$identifier\E\s*=\s*(?:iconButton|capsuleButton|settingsActionButton|actionButton)\s*\(/;
    return 1 if $chunk =~ /apply[A-Za-z0-9_]*Theme|setTheme|restyle|themeChanged/;
    return 1 if $chunk =~ /contentTintColor\s*=\s*(?:theme|ReaderTheme|ReadingNoteTheme|settings|primaryText|secondaryText|text|accent|color)/;
    return 0;
}
PERL
