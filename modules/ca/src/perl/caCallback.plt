#!/usr/bin/env perl
#*************************************************************************
# Copyright (c) 2026 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# SPDX-License-Identifier: EPICS
# EPICS BASE is distributed subject to a Software License Agreement found
# in file LICENSE that is included with this distribution.
#*************************************************************************

# Stage 2: Asynchronous Channel Access - connection callbacks, get/put
# callbacks and monitor subscriptions. Callback completions are processed
# by CA->pend_event (not pend_io), so this file drives an event loop.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib '@TOP@/lib/perl';

use Test::More tests => 24;
use CA;
use EPICS::IOC;

# Set to 1 to echo all IOC and client communications
my $debug = 0;

$ENV{HARNESS_ACTIVE} = 1 if scalar @ARGV && shift eq '-tap';

# Keep all CA traffic on the loopback interface, on ports unique to this file.
$ENV{EPICS_CA_AUTO_ADDR_LIST}  = 'NO';
$ENV{EPICS_CA_ADDR_LIST}       = 'localhost';
$ENV{EPICS_CA_SERVER_PORT}     = 55066;
$ENV{EPICS_CAS_BEACON_PORT}    = 55067;
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


# --- Start the server and connect channels ------------------------------

my $softIoc = "$bin/softIoc";
$softIoc = "$bin/softIocPVA" unless -x $softIoc;
BAIL_OUT("Can't find a softIoc executable") unless -x $softIoc;

watchdog {
    $ioc->start($softIoc, '-m', "P=$prefix", '-d', $dbfile);
    $ioc->cmd;
} 15, kill_bail('starting softIoc');

my %chan = (
    dbl  => CA->new("$prefix:dbl"),
    long => CA->new("$prefix:long"),
);
watchdog { CA->pend_io(10) } 15, kill_bail('connecting channels');


# --- Connection callback ------------------------------------------------

my $up;
my $cc = CA->new("$prefix:dbl", sub { $up = $_[1] });
watchdog { pend_until { defined $up } } 15, kill_bail('connection callback');
ok($up, 'connection callback reports the channel is up');


# --- get_callback: default (native) type --------------------------------

$ioc->dbpf("$prefix:long", '11');
my ($gstatus, $gdata, $gdone);
$chan{long}->get_callback(sub { ($gstatus, $gdata) = @_[1, 2]; $gdone = 1 });
watchdog { pend_until { $gdone } } 15, kill_bail('get_callback');
is($gstatus, undef, 'get_callback status is undef on success');
is($gdata, 11, 'get_callback delivers the scalar value');


# --- get_callback: DBR_TIME_DOUBLE gives a hash with a timestamp --------

$ioc->dbpf("$prefix:dbl", '3.25');
my ($tdata, $tdone);
$chan{dbl}->get_callback(sub { $tdata = $_[2]; $tdone = 1 }, 'DBR_TIME_DOUBLE');
watchdog { pend_until { $tdone } } 15, kill_bail('DBR_TIME get_callback');
is(ref $tdata, 'HASH', 'compound type is delivered as a hash reference');
is($tdata->{TYPE}, 'DBR_TIME_DOUBLE', 'hash TYPE matches the request');
is($tdata->{COUNT}, 1, 'hash COUNT is 1 for a scalar');
cmp_ok($tdata->{value}, '==', 3.25, 'hash value is correct');
ok(defined $tdata->{stamp}, 'stamp present for a DBR_TIME type');
ok(defined $tdata->{stamp_fraction}, 'stamp_fraction present for a DBR_TIME type');
is($tdata->{severity}, undef, 'severity is undef when not in alarm');


# --- get_callback: DBR_CTRL_DOUBLE gives display/control metadata -------

my ($cdata, $cdone);
$chan{dbl}->get_callback(sub { $cdata = $_[2]; $cdone = 1 }, 'DBR_CTRL_DOUBLE');
watchdog { pend_until { $cdone } } 15, kill_bail('DBR_CTRL get_callback');
is($cdata->{units}, 'V', 'CTRL data reports engineering units');
is($cdata->{precision}, 3, 'CTRL data reports display precision');
cmp_ok($cdata->{upper_disp_limit}, '==', 10, 'CTRL upper display limit');
cmp_ok($cdata->{lower_disp_limit}, '==', -10, 'CTRL lower display limit');
cmp_ok($cdata->{upper_alarm_limit}, '==', 8, 'CTRL upper alarm limit (HIHI)');
cmp_ok($cdata->{upper_ctrl_limit}, '==', 100, 'CTRL upper control limit (DRVH)');


# --- put_callback -------------------------------------------------------

my ($pstatus, $pdone);
$chan{dbl}->put_callback(sub { $pstatus = $_[1]; $pdone = 1 }, 5.5);
watchdog { pend_until { $pdone } } 15, kill_bail('put_callback');
is($pstatus, undef, 'put_callback status is undef on success');
cmp_ok($ioc->dbgf("$prefix:dbl"), '==', 5.5, 'put_callback updated the record');


# --- Monitor subscription -----------------------------------------------

$ioc->dbpf("$prefix:long", '20');
my @events;
my $sub = $chan{long}->create_subscription('v',
    sub { push @events, $_[2] unless $_[1] });
isa_ok($sub, 'CA::Subscription', 'create_subscription return value');
watchdog { pend_until { scalar @events >= 1 } } 15, kill_bail('initial monitor');
is($events[0], 20, 'subscription delivers the initial value');

$ioc->dbpf("$prefix:long", '77');
watchdog { pend_until { scalar @events >= 2 } } 15, kill_bail('monitor update');
is($events[-1], 77, 'subscription delivers a changed value');

$sub->clear;
CA->flush_io;
my $n = scalar @events;
$ioc->dbpf("$prefix:long", '99');
CA->pend_event(1);
is(scalar @events, $n, 'no further events after the subscription is cleared');


# --- Housekeeping class methods -----------------------------------------

ok(CA->test_io, 'test_io is true when no IO is outstanding');
CA->flush_io;
CA->poll;
pass('flush_io and poll run without error');


# Silence the expected disconnect exception during shutdown.
CA->add_exception_event(sub {});
%chan = ();
undef $cc;

$ioc->exit;
