#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

WARNINGS_AS_ERRORS=0
if [[ "${1:-}" == "--warnings-as-errors" ]]; then
  WARNINGS_AS_ERRORS=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--warnings-as-errors]" >&2
  exit 1
fi

WARNINGS_AS_ERRORS="$WARNINGS_AS_ERRORS" perl - <<'PERL'
use strict;
use warnings;

my $warnings_as_errors = $ENV{WARNINGS_AS_ERRORS} eq '1';
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
my @warnings;

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

    collect_color_warnings($file, \@lines, \@warnings);
}

if (@failures) {
    print "UI theme checks failed:\n";
    print " - $_\n" for @failures;
    exit 1;
}

if (@warnings) {
    my $limit = 20;
    print "UI theme warnings:\n";
    for my $i (0..$#warnings) {
        last if $i >= $limit;
        print " - $warnings[$i]\n";
    }
    if (@warnings > $limit) {
        print " - ... ".(@warnings - $limit)." more warning(s); run scripts/check_ui_theme.sh --warnings-as-errors while tightening theme coverage.\n";
    }
    if ($warnings_as_errors) {
        exit 1;
    }
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

sub collect_color_warnings {
    my ($file, $lines, $warnings) = @_;
    return if theme_color_owner($file);

    for (my $i = 0; $i < @$lines; $i++) {
        my $line = $lines->[$i];
        next if $line =~ /leafreader-theme-ok|leafreader-theme-warning-ok/;

        if ($line =~ /\.contentTintColor\s*=\s*NSColor\s*\(/) {
            push @$warnings, sprintf(
                "%s:%d: fixed NSColor assigned to contentTintColor; prefer a theme-derived color or document with leafreader-theme-warning-ok",
                $file,
                $i + 1
            );
            next;
        }

        next unless $line =~ /(?:\.textColor|\.backgroundColor|\.borderColor|foregroundColor:)\s*=?\s*(?:is[A-Za-z0-9_]+\s*\?\s*)?NSColor\s*\(/;
        next if nearby_theme_handling($lines, $i, '');

        push @$warnings, sprintf(
            "%s:%d: fixed NSColor on visible UI outside a theme helper; confirm original, eyeCare, and dark handling or document with leafreader-theme-warning-ok",
            $file,
            $i + 1
        );
    }
}

sub theme_color_owner {
    my ($file) = @_;
    return $file =~ m{/(?:ReaderTheme|.*Theme|.*Palette|.*Style|Themed.*|SettingsTabsView|SelectionActionToolbar|ReadAloud.*HintView|RecentDocumentsPanelController\+Cards)\.swift$};
}
PERL
