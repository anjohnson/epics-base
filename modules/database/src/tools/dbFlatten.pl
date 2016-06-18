#!/usr/bin/env perl

#*************************************************************************
# Copyright (c) 2016 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# EPICS BASE is distributed subject to a Software License Agreement found
# in file LICENSE that is included with this distribution.
#*************************************************************************

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../lib/perl";

use DBD;
use DBD::Database;
use DBD::Parser;
use DBD::Output;
use EPICS::Getopts;
use EPICS::Readfile;
use EPICS::macLib;

our ($opt_D, @opt_I, @opt_S, $opt_o, $opt_V);

getopts('DI@S@o:V') or
    die "Usage: dbFlatten.pl [-D] [-I dir] [-S macro=val] [-o out.db] in.dbd in.vdb";

my @path = map { split /[:;]/ } @opt_I; # FIXME: Broken on Win32?
my $macros = EPICS::macLib->new(@opt_S);
my $dbd = DBD->new();

$macros->suppressWarning(!$opt_V);
$DBD::Record::macrosOk = !$opt_V;

# Calculate filename for the dependency warning message below
my $dep = $opt_o;
my $dot_d = '';
if ($opt_D) {
    $dep =~ s{\.\./O\.Common/(.*)}{$1\$\(DEP\)};
    $dot_d = '.d';
} else {
    $dep = "\$(COMMON_DIR)/$dep";
}

die "dbFlatten.pl: No input DBD file given for $opt_o\n"
    unless @ARGV;

# First load the DBD file
my $file = shift @ARGV;
eval {
    ParseDBD($dbd, &Readfile($file, $macros, \@opt_I));
};
if ($@) {
    warn "dbFlatten.pl: $@";
    my $outfile = $opt_o ? " to create '$opt_o$dot_d'" : '';
    die "  while reading DBD file '$file'$outfile\n";
}

die "dbFlatten.pl: No input VDB file given for $opt_o\n"
    unless scalar(@ARGV) == 1;

my $top = $ARGV[0];     # Remember top VDB file

my $errors = 0;
my %databases;

# Now load the DB file
while (@ARGV) {
    my $file = shift @ARGV;
    next if exists $databases{$file};
    my $db = DBD::Database->new($dbd, $file);
    eval {
        &ParseDB($db, &Readfile($file, 0, \@opt_I));
    };
    if ($@) {
        warn "dbFlatten.pl: $@";
        my $outfile = $opt_o ? " to create '$opt_o$dot_d'" : '';
        warn "  while reading DB file '$file'$outfile\n";
        warn "  Your Makefile may need this dependency rule:\n",
            "    $dep: \$(COMMON_DIR)/$file\n"
            if $@ =~ m/Can't find file '$file'/;
        ++$errors;
    }
    else {
        $databases{$file} = $db;
        while (my ($instance, $exp) = each %{$db->expands}) {
            push @ARGV, $exp->filename;
        }
    }
}

if ($opt_D) {   # Output dependencies only, ignore errors
    my %filecount;
    my @uniqfiles = grep { not $filecount{$_}++ } @inputfiles;
    print "$opt_o: ", join(" \\\n    ", @uniqfiles), "\n\n";
    print map { "$_:\n" } @uniqfiles;
    exit 0;
}

die "dbFlatten.pl: Exiting due to errors\n" if $errors;

# Link all expands up to their databases
foreach my $db (values %databases) {
    while (my ($instance, $exp) = each %{$db->expands}) {
        my $file = $exp->filename;
        die "Database for $file not loaded"
            unless exists $databases{$file};
        $exp->link($databases{$file});
    }
}

my $out;
if ($opt_o) {
    open $out, '>', $opt_o
        or die "Can't create $opt_o: $!\n";
}
else {
    $out = *STDOUT;
}

FlattenDB($out, $databases{$top}, $macros);

if ($opt_o) {
    close $out or die "Closing $opt_o failed: $!\n";
}
exit 0;
