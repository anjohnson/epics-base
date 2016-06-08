#!/usr/bin/perl

use lib '@TOP@/lib/perl';

use Test::More tests => 17;

use DBD::Record;
use DBD::Recordtype;
use DBD::Recfield;

# Create a Recordtype for testing
my $rtyp = DBD::Recordtype->new('test');

my $fld1 = DBD::Recfield->new('NAME', 'DBF_STRING');
$fld1->add_attribute("size", "41");
$fld1->check_valid;
$rtyp->add_field($fld1);

my $fld2 = DBD::Recfield->new('DTYP', 'DBF_DEVICE');
$fld2->check_valid;
$rtyp->add_field($fld2);


my $rec = DBD::Record->new($rtyp, 'test');
isa_ok $rec, 'DBD::Record';
is $rec->name, 'test', 'Record name';
is $rec->recordtype, $rtyp, 'Record type';
is $rec->aliases, 0, 'No aliases yet';

$rec->add_alias('check');
is $rec->aliases, 1, 'Alias added';

my @aliases = $rec->aliases;
is_deeply \@aliases, ['check'], 'Alias list';

is $rec->get_field('DTYP'), undef, 'DTYP Initially empty';
$rec->put_field('DTYP', '1');
is $rec->get_field('DTYP'), '1', 'DTYP can be set';

my @fields = $rec->recfields;
is_deeply \@fields, [$fld2], 'Field list';

my @names = $rec->field_names;
is_deeply \@names, ['DTYP'], 'Field name list';

is $rec->info_names, 0, 'No info tags yet';

$rec->add_info('key', 'value');
is $rec->info_names, 1, 'First info tag added';

my @tags = $rec->info_names;
is_deeply \@tags, ['key'], 'Info tag list';

is $rec->info_value('key'), 'value', 'Info tag value lookup';

is $rec->comments, 0, 'No cdefs yet';
$rec->add_comment('commentary');
is $rec->comments, 1, 'First comment added';

my @comments = $rec->comments;
is_deeply \@comments, ['commentary'], 'Comment list';
