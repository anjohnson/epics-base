#!/usr/bin/env perl
#*************************************************************************
# Copyright (c) 2026 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# SPDX-License-Identifier: EPICS
# EPICS BASE is distributed subject to a Software License Agreement found
# in file LICENSE that is included with this distribution.
#*************************************************************************

# Stage 4a: Advanced client behaviour - server restart (disconnect and
# reconnect), exception handling, the printf handler, and access-rights
# events. This test stops and restarts the softIoc CA server, so it is the
# slowest and is expectedly skipped under CI (see the Makefile).

use strict;
use warnings;

use FindBin qw($RealBin);
use lib '@TOP@/lib/perl';

use Test::More tests => 13;
use CA;
use EPICS::IOC;

# Set to 1 to echo all IOC and client communications
my $debug = 0;

$ENV{HARNESS_ACTIVE} = 1 if scalar @ARGV && shift eq '-tap';

# Keep all CA traffic on the loopback interface, on ports unique to this file.
$ENV{EPICS_CA_AUTO_ADDR_LIST}  = 'NO';
$ENV{EPICS_CA_ADDR_LIST}       = 'localhost';
$ENV{EPICS_CA_SERVER_PORT}     = 55070;
$ENV{EPICS_CAS_BEACON_PORT}    = 55071;
$ENV{EPICS_CAS_INTF_ADDR_LIST} = 'localhost';

my $bin = '@TOP@/bin/@ARCH@';
my $prefix = "test-$$";
my $dbfile = "$RealBin/../caTest.db";

my $softIoc = "$bin/softIoc";
$softIoc = "$bin/softIocPVA" unless -x $softIoc;

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

sub start_ioc {
    watchdog {
        $ioc->start($softIoc, '-m', "P=$prefix", '-d', $dbfile);
        $ioc->cmd;
    } 15, kill_bail('starting softIoc');
}


BAIL_OUT("Can't find a softIoc executable") unless -x $softIoc;
start_ioc();


# --- Connect, tracking connection state and exceptions ------------------

# Capturing the exception events both tests add_exception_event and keeps
# the expected "virtual circuit disconnect" message off the console.
my @exceptions;
CA->add_exception_event(sub { push @exceptions, $_[2] });

my @conn;
my $chan = CA->new("$prefix:dbl", sub { push @conn, $_[1] ? 'UP' : 'DOWN' });
watchdog { pend_until { $chan->is_connected } } 15, kill_bail('initial connect');
ok($chan->is_connected, 'channel is connected to the first IOC');
is($conn[-1], 'UP', 'connection handler reported the channel up');


# --- Access-rights event (the name the XS actually exports) --------------

my @rights;
$chan->replace_access_rights_event(sub { @rights = @_[1, 2] });
watchdog { pend_until { scalar @rights } } 15, kill_bail('access rights');
ok($rights[0], 'access-rights handler reports read access');
ok($rights[1], 'access-rights handler reports write access');


# --- Take the server offline --------------------------------------------

$ioc->exit;
watchdog { pend_until { !$chan->is_connected } } 20, kill_bail('disconnect');
ok(!$chan->is_connected, 'channel disconnects when the server stops');
is($conn[-1], 'DOWN', 'connection handler reported the channel down');
ok(scalar @exceptions, 'exception handler fired on the disconnect');
like($exceptions[-1], qr/:55070/, 'exception context names the server address');


# --- Bring the server back on the same ports ----------------------------

start_ioc();
watchdog { pend_until { $chan->is_connected } 35 } 40, kill_bail('reconnect');
ok($chan->is_connected, 'channel reconnects when the server returns');
is($conn[-1], 'UP', 'connection handler reported the channel up again');

# Data flows again after the reconnection.
$chan->put(4.5);
$chan->get;
watchdog { CA->pend_io(10) } 15, kill_bail('get after reconnect');
cmp_ok($chan->value, '==', 4.5, 'get/put works again after reconnect');


# --- printf handler -----------------------------------------------------

# The client library only emits printf-handler output in situations that
# aren't deterministically reproducible here, so we just verify that the
# handler can be installed and removed cleanly.
my @printed;
CA->replace_printf_handler(sub { push @printed, $_[0] });
CA->poll;
CA->replace_printf_handler(undef);
pass('replace_printf_handler installs and restores without error');


# --- Removing the access-rights handler (the "cancels" path) ------------

$chan->replace_access_rights_event(undef);
pass('replace_access_rights_event(undef) removes the handler');


CA->add_exception_event(sub {});    # silence the shutdown disconnect
undef $chan;

$ioc->exit;
