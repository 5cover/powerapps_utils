#!/usr/bin/env perl
use strict;
use warnings;

my $hex = shift @ARGV or die "Usage: $0 <hex_color>\n";

# Remove optional '#' prefix
$hex =~ s/^#//;

# Validate and parse the input
unless ($hex =~ /^([A-Fa-f0-9]{6})([A-Fa-f0-9]{2})?$/) {
    die "Invalid hex color format. Expected format: #RRGGBB or #RRGGBBAA\n";
}

my ($rgb, $alpha) = ($1, $2);
my ($r, $g, $b) = map { hex($_) } ($rgb =~ /../g);

# Alpha is optional; default to 255 (opaque)
my $a = defined $alpha ? hex($alpha) : 255;

# Convert alpha to Power Apps range (0-1)
my $alpha_float = sprintf("%.3f", $a / 255);

print "RGBA($r; $g; $b; $alpha_float)\n";
