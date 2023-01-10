#!/usr/bin/perl

use lib '@TOP@/lib/perl';

use Test::More tests => 54;

use DBD;
use DBD::Parser;
use DBD::Output;
use EPICS::macLib;

my $otxt;

my $dbd = DBD->new;

note 'Comments and POD';

ParseDBD($dbd, <<"__END__");
# Comment
=pod text

=cut

__END__

is_deeply [$dbd->comments], [' Comment'], 'Comment';
is_deeply [$dbd->pod], ['=pod text', ''], 'POD text';


note 'Menu parsing';

my $m_dbd = <<'__END__';
menu(m) {
    choice(m0, "Zero")
    choice(m1, "One")
}
__END__
ParseDBD($dbd, $m_dbd);

my $m = $dbd->menu('m');
ok $m, 'menu';
is $m->choices, 2, 'Two choices';

open my $ofh, '>', \$otxt
    or die "Internal error, $@";
OutputDBD($ofh, $dbd);
close $ofh;
is $otxt, $m_dbd, "Menu output matches input";


note 'Record type parsing';

my $r_dbd = <<'__END__';
recordtype(r) {
    field(NAME, DBF_STRING) {
        size(20)
    }
    field(VAL, DBF_MENU) {
        initial(One)
        menu(m)
    }
    field(FLNK, DBF_FWDLINK) {
    }
}
__END__
ParseDBD($dbd, $r_dbd);

my $t = $dbd->recordtype('r');
ok $t, 'recordtype';
is $t->fields, 3, 'Three fields';
my $f = $t->field('VAL');
is $f->dbf_type, 'DBF_MENU', 'VAL is DBF_MENU';
is $f->attribute('initial'), 'One', 'Default value correct';
ok $f->{MENU}->legal_choice('Zero'), 'Zero is legal choice';

open my $ofh, '>', \$otxt
    or die "Internal error, $@";
OutputDBD($ofh, $dbd);
close $ofh;
is $otxt, $m_dbd.$r_dbd, "Recordtype output matches input";


note 'Template database';

my $a_db = <<'__END__';
template("testplate") {
    port(VAL, "$(P):a.VAL", "Value field")
}

record(r, "${P}:a") {
    field(VAL, Zero)
    field(FLNK, "$(FLNK)")
    info("r", ["mat","ion","${Q}"])
}
__END__

$DBD::Base::macrosOk = 1;
my $dba = DBD::Database->new($dbd, 'a.db');
ParseDB($dba, $a_db);

my $r = $dba->record('${P}:a');
ok $r, 'record';
is $r->recfields, 2, 'Two field values set';
is_deeply [$r->info_names], ['r'], 'Info item found';

ok $dba->is_template, 'Database a defines a template';
my $p = $dba->ports();
is_deeply [keys %$p], ['VAL'], 'VAL port defined';

open my $ofh, '>', \$otxt
    or die "Internal error, $@";
OutputDB($ofh, $dba);
close $ofh;
is $otxt, "# Expansion of a.db\n\n$a_db", "Database output matches input";


note 'Template and parent database';

my $b_db = <<'__END__';
template("parent") {
    port(VAL1, "$(a1.VAL)", "Value field #1")
    port(VAL2, "${a2.VAL}", "Value field #2")
}
expand("a.db", a1) {
    macro(P, "$(P):a1")
    macro(Q, "$(Q1)")
}
expand("a.db", a2) {
    macro(P, "$(P):a2")
    macro(Q, "${Q2}")
}
__END__

my $dbb = DBD::Database->new($dbd, 'b.db');
ParseDB($dbb, $b_db);

ok $dbb->is_template, 'Database b defines a template';

my $e = $dbb->expands;
is_deeply [sort keys %$e], ['a1', 'a2'], 'Has template expansions';

my $e1 = $e->{a1};
is $e1->filename, 'a.db', 'Filename correct';
is_deeply [sort keys %{$e1->macros}], ['P', 'Q'], 'Has expected macros';
is $e1->macro('P'), '$(P):a1', 'Macro value';

my $e2 = $e->{a2};
is $e2->filename, 'a.db', 'Filename correct';
is_deeply [sort keys %{$e2->macros}], ['P', 'Q'], 'Has expected macros';
is $e2->macro('P'), '$(P):a2', 'Macro value';


note 'Parent non-template database';

my $c_db = <<'__END__';
expand("b.db", b1) {
    macro(P, "$(P):b1")
    macro(Q1, "$(b1.VAL2)")
    macro(Q2, "$(b1.VAL1)")
}
expand("b.db", b2) {
    macro(P, "$(P):b2")
    macro(Q1, "$(b2.VAL2)")
    macro(Q2, "$(b2.VAL1)")
}
__END__

my $dbc = DBD::Database->new($dbd, 'c.db');
ParseDB($dbc, $c_db);

ok !$dbc->is_template, 'Database c does not define a template';

my $e = $dbc->expands;
is_deeply [sort keys %$e], ['b1', 'b2'], 'Has two template expansions';

my $e3 = $e->{b1};
is $e3->filename, 'b.db', 'Filename correct';
is_deeply [sort keys %{$e3->macros}], ['P', 'Q1', 'Q2'], 'Has expected macros';
is $e3->macro('P'), '$(P):b1', 'Macro value';

my $e4 = $e->{b2};
is $e4->filename, 'b.db', 'Filename correct';
is_deeply [sort keys %{$e4->macros}], ['P', 'Q1', 'Q2'], 'Has expected macros';
is $e4->macro('P'), '$(P):b2', 'Macro value';


note 'Flattening';

# Prepare for flattening
my $macros = EPICS::macLib->new();
$macros->suppressWarning(1);
$macros->installMacros('P=Test');

# Link the expand objects to their database(s)
$e1->link($dba);
$e2->link($dba);
$e3->link($dbb);
$e4->link($dbb);

ok !FlattenMacros($dbc, $macros), 'No undefined ports/macros';

my $e_db;
open my $ofh, '>', \$e_db
    or die "Internal error, $@";
FlattenDB($ofh, $dbc, $macros);
close $ofh;

# Now parse the flattened database and check the results
my $dbe = DBD::Database->new($dbd, 'e.db');
ParseDB($dbe, $e_db);

ok !$dbe->is_template, 'Expanded database does not define a template';
ok !scalar %{$dbe->expands}, 'Expanded database is flat';

ok $dbe->record("Test:$_:a"), "Record Test:$_:a exists"
    for ('b1:a1', 'b1:a2', 'b2:a1', 'b2:a2');


note 'JSON parser';

json_ok('null');
json_ok('true');
json_ok('false');
json_ok('0');
json_ok('{}');
json_ok('{a:1}');
json_ok('{a:2,}');
json_ok('{"a":"b",}');
json_ok('{"a":{"b":0},}');
json_ok('{a:[0,1]}');
json_ok('[1]');
json_ok('[1,]');
json_ok('[1,2]');
json_ok('[1,2,]');

sub json_ok {
    my ($json) = @_;
    my $j_db = <<"__END__";
    record(r, "j") {
        info("j", $json)
    }
__END__
    my $dbj = DBD::Database->new($dbd, 'j.db');
    ParseDB($dbj, $j_db);
    is $dbj->record('j')->info_value('j'), $json, "JSON: $json"
}
