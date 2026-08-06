#!/usr/bin/env perl
#*************************************************************************
# Copyright (c) 2026 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# SPDX-License-Identifier: EPICS
# EPICS BASE is distributed subject to a Software License Agreement found
# in file LICENSE that is included with this distribution.
#*************************************************************************

# Stage 1: Basic Channel Access client functionality of the CA Perl module.
# Exercises channel construction, introspection, synchronous get/put and
# error handling against a softIoc CA server loaded with caTest.db.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib '@TOP@/lib/perl';

use Test::More tests => 31;
use CA;
use EPICS::IOC;

# Set to 1 to echo all IOC and client communications
my $debug = 0;

$ENV{HARNESS_ACTIVE} = 1 if scalar @ARGV && shift eq '-tap';

# Keep all CA traffic on the loopback interface using non-default ports so
# these tests can't see or be seen by any other IOC on the network.
$ENV{EPICS_CA_AUTO_ADDR_LIST}  = 'NO';
$ENV{EPICS_CA_ADDR_LIST}       = 'localhost';
$ENV{EPICS_CA_SERVER_PORT}     = 55064;
$ENV{EPICS_CAS_BEACON_PORT}    = 55065;
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


# --- Tests that need no server ------------------------------------------

like(CA->version, qr/^ EPICS \s+ \d+ \. \d+ \. \d+ /x,
    'CA->version reports an EPICS version string');

# A channel for a PV that will never connect (no server yet).
my $bad = CA->new('no-such-pv');
isa_ok($bad, 'CA', 'CA->new returns a CA object');
is($bad->name, 'no-such-pv', 'name returns the requested PV name');
is($bad->field_type, 'TYPENOTCONN', 'field_type is TYPENOTCONN when unconnected');
is($bad->element_count, 0, 'element_count is 0 when unconnected');
is($bad->host_name, '<disconnected>', 'host_name is <disconnected> when unconnected');
is($bad->state, 'never connected', 'state is "never connected" initially');
ok(!$bad->is_connected, 'is_connected is false when unconnected');

# pend_io must time out (and die with ECA_TIMEOUT) waiting for that channel.
my $err;
{
    local $SIG{__DIE__};
    eval { CA->pend_io(0.1) };
    $err = $@;
}
like($err, qr/^ECA_TIMEOUT/, 'pend_io dies with ECA_TIMEOUT for a missing PV');
undef $bad;     # clear the channel so it won't disturb later pend_io calls


# --- Start the CA server ------------------------------------------------

my $softIoc = "$bin/softIoc";
$softIoc = "$bin/softIocPVA" unless -x $softIoc;
BAIL_OUT("Can't find a softIoc executable") unless -x $softIoc;

watchdog {
    $ioc->start($softIoc, '-m', "P=$prefix", '-d', $dbfile);
    $ioc->cmd;  # Wait for iocInit to finish and the first prompt
} 15, kill_bail('starting softIoc');

# watchdog evaluates its block in scalar context, so reduce to a count inside.
my $found = watchdog {
    scalar grep { $_ eq "$prefix:dbl" } $ioc->dbl;
} 10, kill_bail('running dbl');
ok($found, 'IOC loaded the test database');


# --- Connection and introspection --------------------------------------

my %chan = (
    dbl  => CA->new("$prefix:dbl"),
    long => CA->new("$prefix:long"),
    str  => CA->new("$prefix:str"),
    enum => CA->new("$prefix:enum"),
    wf   => CA->new("$prefix:wf"),
);

watchdog { CA->pend_io(10) } 15, kill_bail('connecting channels');

ok($chan{dbl}->is_connected, 'channel connects to the server');
is($chan{dbl}->state, 'connected', 'state is "connected" once connected');
is($chan{dbl}->field_type,  'DBR_DOUBLE', 'field_type of ao is DBR_DOUBLE');
is($chan{long}->field_type, 'DBR_LONG',   'field_type of longout is DBR_LONG');
is($chan{str}->field_type,  'DBR_STRING', 'field_type of stringout is DBR_STRING');
is($chan{enum}->field_type, 'DBR_ENUM',   'field_type of mbbo is DBR_ENUM');
is($chan{dbl}->element_count, 1,  'scalar element_count is 1');
is($chan{wf}->element_count, 10, 'waveform element_count matches NELM');
like($chan{dbl}->host_name, qr/:55064$/, 'host_name reports the server port');
ok($chan{dbl}->read_access,  'client has read access');
ok($chan{dbl}->write_access, 'client has write access');


# --- Synchronous get / value -------------------------------------------

# Seed known values from the IOC side, then read them back over CA.
$ioc->dbpf("$prefix:dbl", '1.5');
$ioc->dbpf("$prefix:long", '42');
$ioc->dbpf("$prefix:str", 'hello');

$chan{$_}->get for qw(dbl long str);
watchdog { CA->pend_io(10) } 15, kill_bail('getting values');

cmp_ok($chan{dbl}->value, '==', 1.5, 'get/value returns the double value');
is($chan{long}->value, 42, 'get/value returns the long value');
is($chan{str}->value, 'hello', 'get/value returns the string value');

# A DBF_ENUM read with the default (native) type widens to a string.
$ioc->dbpf("$prefix:enum", '2');
$chan{enum}->get;
watchdog { CA->pend_io(10) } 15, kill_bail('getting enum');
is($chan{enum}->value, 'two', 'enum get/value returns the choice string');


# --- Synchronous put ----------------------------------------------------

$chan{dbl}->put(2.5);
$chan{long}->put(-7);
$chan{str}->put('world');

# Read the values back over CA. A get is ordered behind the put on the
# circuit, so its completion guarantees the server has applied the put
# before we cross-check the record from the IOC side.
$chan{$_}->get for qw(dbl long str);
watchdog { CA->pend_io(10) } 15, kill_bail('putting values');

cmp_ok($chan{dbl}->value, '==', 2.5, 'get after put returns the new double value');
is($chan{long}->value, -7, 'get after put returns the new long value');
is($chan{str}->value, 'world', 'get after put returns the new string value');

# Cross-check against the IOC's own view of the records.
cmp_ok($ioc->dbgf("$prefix:dbl"), '==', 2.5, 'put updated the double record (via dbgf)');
is($ioc->dbgf("$prefix:long"), -7, 'put updated the long record (via dbgf)');
is($ioc->dbgf("$prefix:str"), 'world', 'put updated the string record (via dbgf)');

# Silence the expected "Virtual circuit disconnect" exception the client
# logs when the server is stopped while channels are still open.
CA->add_exception_event(sub {});
%chan = ();

$ioc->exit;
