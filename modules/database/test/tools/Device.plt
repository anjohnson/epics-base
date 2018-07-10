#!/usr/bin/env perl
######################################################################
# SPDX-License-Identifier: EPICS
# EPICS BASE is distributed subject to a Software License Agreement
# found in file LICENSE that is included with this distribution.
######################################################################

use lib '@TOP@/lib/perl';

use Test::More tests => 22;

use DBD::Device;

my $dev = DBD::Device->new('VME_IO', 'test', 'Device');
isa_ok $dev, 'DBD::Device';
is $dev->name, 'test', 'Device name';
is $dev->link_type, 'VME_IO', 'Link type';
is $dev->choice, 'Device', 'Choice string';
ok $dev->legal_addr('#C0xFEED S123 @xxx'), 'Address legal';
my %dev_addrs = (
    CONSTANT  => ['12345', '[1,2,3]', '["a"]', '["a","b",]'],
    PV_LINK   => ['PV:Name', 'Any:Record.NAME CPP.MS'],
    JSON_LINK => ['{const:[1,2,3,4,5]}','{l:{a:b,c:d},}'],
    VME_IO    => ['# C1 S2 @Anything'],
    CAMAC_IO  => ['# B1 C2 N3 A4 F5 @Anything'],
    RF_IO     => ['# R1 M2 D3 E4'],
    AB_IO     => ['# L1 A2 C3 S4 @Anything'],
    GPIB_IO   => ['# L1 A2 @Anything'],
    BITBUS_IO => ['# L1 N2 P3 S4 @Anything'],
    BBGPIB_IO => ['# L1 B2 G3 @Anything'],
    VXI_IO    => ['# V1 C2 S3 @Anything'],
    INST_IO   => ['@Anything']
);
while (my ($link, $addrs) = each(%dev_addrs)) {
    $dev->init($link, 'test', 'Device');
    ok $dev->legal_addr($_), "$link address '$_'" foreach @{$addrs};
}
