#!/usr/bin/perl

use lib '@TOP@/lib/perl';

use Test::More tests => 14;

use DBD;
use DBD::Parser;
use DBD::Output;

my $dbd = DBD->new;

ParseDBD($dbd, <<"__END__");
# Comment
=pod text

=cut

__END__

is_deeply [$dbd->comments], [' Comment'], 'Comment';
is_deeply [$dbd->pod], ['=pod text', ''], 'POD text';

ParseDBD($dbd, <<"__END__");
    menu(m) {
        #Menu Comments
        choice(m0, "Zero")
        choice(m1, "One")
    }
__END__

my $m = $dbd->menu('m');
ok $m, 'menu';
is $m->choices, 2, 'Two choices';
is_deeply [$m->comments], ['Menu Comments'], 'Menu Comments';

ParseDBD($dbd, <<'__END__');
    recordtype(r) {
        field(NAME, DBF_STRING) {
            size(20)
        }
        field(VAL, DBF_MENU) {
            menu(m)
            initial("One")
        }
        field(FLNK, DBF_FWDLINK) {}
    }
__END__

my $t = $dbd->recordtype('r');
ok $t, 'recordtype';
is $t->fields, 3, 'Three fields';
my $f = $t->field('VAL');
is $f->dbf_type, 'DBF_MENU', 'VAL is DBF_MENU';
ok $f->{MENU}->legal_choice('Zero'), 'Zero is legal choice';

$DBD::Record::macrosOk = 1;
my $db = DBD::Database->new($dbd, 'a.db');
ParseDB($db, <<'__END__');
    record(r, "$(P):a") {
        field(VAL, "Zero")
        field(FLNK, $(FLNK))
        info(r, ["mat", "ion", ])
    }
    template("testplate") {
        port(VAL, "$(P):a.VAL", "Value field")
    }
__END__

my $r = $db->record('$(P):a');
ok $r, 'record';
is $r->recfields, 2, 'Two field values set';
is_deeply [$r->info_names], ['r'], 'Info item found';

ok $db->is_template, 'Database defines a template';
my $p = $db->ports();
is_deeply [keys $p], ['VAL'], 'VAL port defined';

OutputDB(*STDOUT, $db);
