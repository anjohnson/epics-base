package DBD::Expand;

use DBD::Base;
@ISA = qw(DBD::Base);

use Carp;

sub init {
    my ($this, $filename, $instance) = @_;
    $this->SUPER::init($instance, 'template instance');
    $this->{'FILENAME'} = $filename;
    $this->{'MACROS'} = {};
    $this->{'DBD::Database'} = undef;
    return $this;
}

sub identifier {
    my ($this, $id, $what) = @_;
    confess "DBD::Expand::identifier: $what undefined!"
        unless defined $id;
    if ($id !~ m/^$RXtmpid$/o) {
        my @message;
        push @message, "A $what may contain only letters, digits",
            "and these special characters: _ : -" unless $warned++;
        dieContext("Illegal $what '$id'", @message);
    }
    return $id;
}

sub filename {
    return shift->{'FILENAME'};
}

sub database {
    return shift->{'DBD::Database'};
}

sub link {
    my ($this, $db) = @_;
    confess "DBD::Expand::link: Not a DB"
        unless $db->isa('DBD::Database');
    $this->{'DBD::Database'} = $db;
}

sub add_macro {
    my ($this, $name, $value) = @_;
    $this->{'MACROS'}->{$name} = $value;
}

sub macros {
    return shift->{'MACROS'};
}

sub macro {
    my ($this, $macro_name) = @_;
    return $this->{'MACROS'}->{$macro_name};
}

sub equals {
    my ($a, $b) = @_;
    return $a->SUPER::equals($b)
        && $a->{'FILENAME'} eq $b->{'FILENAME'};
}

1;
