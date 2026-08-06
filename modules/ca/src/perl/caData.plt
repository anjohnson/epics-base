#!/usr/bin/env perl
#*************************************************************************
# Copyright (c) 2026 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# SPDX-License-Identifier: EPICS
# EPICS BASE is distributed subject to a Software License Agreement found
# in file LICENSE that is included with this distribution.
#*************************************************************************

# Stage 3: Data types and arrays - waveform arrays, the DBF_CHAR/string
# special case, ENUM choice strings, and alarm status/severity metadata.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib '@TOP@/lib/perl';

use Test::More tests => 15;
use CA;
use EPICS::IOC;

# Set to 1 to echo all IOC and client communications
my $debug = 0;

$ENV{HARNESS_ACTIVE} = 1 if scalar @ARGV && shift eq '-tap';

# Keep all CA traffic on the loopback interface, on ports unique to this file.
$ENV{EPICS_CA_AUTO_ADDR_LIST}  = 'NO';
$ENV{EPICS_CA_ADDR_LIST}       = 'localhost';
$ENV{EPICS_CA_SERVER_PORT}     = 55068;
$ENV{EPICS_CAS_BEACON_PORT}    = 55069;
$ENV{EPICS_CAS_INTF_ADDR_LIST} = 'localhost';

my $bin = '@TOP@/bin/@ARCH@';
my $prefix = "test-$$";
my $dbfile = "$RealBin/../caTest.db";

my $ioc = EPICS::IOC->new();
$ioc->debug($debug);

$SIG{__DIE__} = $SIG{INT} = $SIG{QUIT} = sub {
    $ioc->exit;
    BAIL_OUT("Caught signal: $_[0]");
};
END { $ioc->exit if $ioc; }


# Watchdog utilities (from netget.plt) to bound any call that might block.

sub kill_bail {
    my $doing = shift;
    return sub {
        $ioc->exit;
        BAIL_OUT("Timeout $doing");
    }
}

sub watchdog (&$$) {
    my ($code, $timeout, $fail) = @_;
    my $bark = "Woof $$\n";
    my $result;
    eval {
        local $SIG{__DIE__};
        local $SIG{ALRM} = sub { die $bark };
        alarm $timeout;
        $result = &$code;
        alarm 0;
    };
    if ($@) {
        die if $@ ne $bark;
        $result = &$fail;
    }
    return $result;
}

# Pump the CA event loop until COND is true or MAX seconds elapse.
sub pend_until (&;$) {
    my ($cond, $max) = @_;
    $max ||= 10;
    for (1 .. 10 * $max) {
        return 1 if $cond->();
        CA->pend_event(0.1);
    }
    return $cond->();
}

# Issue a get_callback and return the delivered data (dies via watchdog on
# timeout). TYPE/COUNT are optional and passed straight through.
sub fetch {
    my ($chan, @args) = @_;
    my $data;
    $chan->get_callback(sub { $data = $_[2] }, @args);
    watchdog { pend_until { defined $data } } 15, kill_bail('get_callback');
    return $data;
}


# --- Start the server and connect channels ------------------------------

my $softIoc = "$bin/softIoc";
$softIoc = "$bin/softIocPVA" unless -x $softIoc;
BAIL_OUT("Can't find a softIoc executable") unless -x $softIoc;

watchdog {
    $ioc->start($softIoc, '-m', "P=$prefix", '-d', $dbfile);
    $ioc->cmd;
} 15, kill_bail('starting softIoc');

my %chan = map { $_ => CA->new("$prefix:$_") } qw(dbl enum wf wfl wfc wfs);
watchdog { CA->pend_io(10) } 15, kill_bail('connecting channels');


# --- Numeric arrays -----------------------------------------------------

$chan{wf}->put(1.5, 2.5, 3.5);
$chan{wfl}->put(10, 20, 30);
watchdog { CA->pend_io(10) } 15, kill_bail('array puts');

my $wf = fetch($chan{wf}, 3);
is(ref $wf, 'ARRAY', 'a multi-element get returns an array reference');
is_deeply([map { $_ + 0 } @$wf], [1.5, 2.5, 3.5], 'double array round-trips');

my $wfl = fetch($chan{wfl}, 3);
is_deeply([map { $_ + 0 } @$wfl], [10, 20, 30], 'long array round-trips');


# --- DBF_CHAR array: string by default, numbers as DBR_LONG -------------

$chan{wfc}->put('Hello');
watchdog { CA->pend_io(10) } 15, kill_bail('char put');

my $str = fetch($chan{wfc});
is($str, 'Hello', 'a DBF_CHAR array is delivered as a Perl string');

my $codes = fetch($chan{wfc}, 'DBR_LONG');
is(ref $codes, 'ARRAY', 'the same DBF_CHAR data as DBR_LONG is an array');
is_deeply([@{$codes}[0 .. 4]], [unpack 'C*', 'Hello'],
    'DBR_LONG delivers the individual byte values');


# --- ENUM: choice string and DBR_GR_ENUM metadata ----------------------

$ioc->dbpf("$prefix:enum", '2');
$chan{enum}->get;
watchdog { CA->pend_io(10) } 15, kill_bail('enum get');
is($chan{enum}->value, 'two', 'a native ENUM get widens to the choice string');

my $en = fetch($chan{enum}, 'DBR_GR_ENUM');
is($en->{no_str}, 4, 'DBR_GR_ENUM reports the number of choices');
is_deeply($en->{strs}, ['zero', 'one', 'two', 'three'],
    'DBR_GR_ENUM lists all the choice strings');
is($en->{value}, 'two', 'DBR_GR_ENUM value is usable as the choice string');
cmp_ok($en->{value}, '==', 2, 'DBR_GR_ENUM value is usable as the choice index');


# --- Alarm status and severity -----------------------------------------

$chan{dbl}->put(10);        # above HIHI (8) => MAJOR / HIHI
watchdog { CA->pend_io(10) } 15, kill_bail('alarm put');

my $al = fetch($chan{dbl}, 'DBR_TIME_DOUBLE');
is($al->{status}, 'HIHI', 'alarm status string reported');
is($al->{severity}, 'MAJOR', 'alarm severity usable as a string');
cmp_ok($al->{severity}, '==', 2, 'alarm severity usable as a number');


# --- Multi-element string put_callback ----------------------------------

my $done;
$chan{wfs}->put_callback(sub { $done = 1 }, 'dd', 'ee', 'ff');
watchdog { pend_until { $done } } 15, kill_bail('string put_callback');

my $back = fetch($chan{wfs}, 3);
is_deeply($back, ['dd', 'ee', 'ff'],
    'multi-element string put_callback sends each element intact');


# Silence the expected disconnect exception during shutdown.
CA->add_exception_event(sub {});
%chan = ();

$ioc->exit;
