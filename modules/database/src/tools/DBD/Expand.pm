package DBD::Expand;
use DBD::Base;
@ISA = qw(DBD::Base);

sub init {
    my ($this, $filename, $instance) = @_;
    $this->SUPER::init($instance, 'template instance');
    $this->{'FILENAME'} = $filename;
    $this->{'MACROS'} = {};
    $this->{'DBD::Database'} = undef;
    return $this;
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
        unless $dbd->isa('DBD::Database');
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
