package DBD::Expand;
use DBD::Base;
@ISA = qw(DBD::Base);

sub init {
    my ($this, $filename, $instance) = @_;
    $this->SUPER::init($instance, 'template instance');
    $this->{'FILENAME'} = $filename;
    $this->{'MACROS'} = {};
    return $this;
}

sub filename {
    return shift->{'FILENAME'};
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
