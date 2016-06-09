package DBD::Database;

use strict;
use warnings;

use DBD::Base;
use DBD::Record;

use Carp;

sub new {
    my ($class, $dbd) = @_;
    confess "DBD::Database::new: Not a DBD"
        unless $dbd->isa('DBD');
    my $this = {
        'DBD'             => $dbd,
        'DBD::Record'     => {},
        'DESCRIPTION'     => undef,
        'PORTS'           => {},
        'COMMENTS'        => [],
        'POD'             => []
    };
    bless $this, $class;
    return $this;
}

sub add {
    my ($this, $obj, $obj_name) = @_;
    my $obj_class = ref $obj;
    confess "DBD::Database::add: Unknown DB object type '$obj_class'"
        unless $obj_class =~ m/^DBD::/
        and exists $this->{$obj_class};
    $obj_name = $obj->name unless defined $obj_name;
    if (exists $this->{$obj_class}->{$obj_name}) {
        return if $obj->equals($this->{$obj_class}->{$obj_name});
        dieContext("A different $obj->{WHAT} named '$obj_name' already exists");
    }
    else {
        $this->{$obj_class}->{$obj_name} = $obj;
    }
}

sub dbd {
    return shift->{DBD};
}

sub description {
    my ($this, $desc) = @_;
    $this->{DESCRIPTION} = $desc
        if defined $desc;
    return $this->{DESCRIPTION};
}

sub is_template {
    my $this = shift;
    return defined $this->{DESCRIPTION};
}

sub add_comment {
    my $this = shift;
    push @{$this->{COMMENTS}}, @_;
}

sub comments {
    return @{shift->{COMMENTS}};
}

sub add_pod {
    my $this = shift;
    push @{$this->{POD}}, @_;
}

sub pod {
    return @{shift->{POD}};
}

sub records {
    return shift->{'DBD::Record'};
}
sub record {
    my ($this, $record_name) = @_;
    return $this->{'DBD::Record'}->{$record_name};
}

sub add_port {
    my ($this, $name, $value, $desc) = @_;
    $this->{'PORTS'}->{$name} = [$value, $desc];
}

sub ports {
    return shift->{'PORTS'};
}

sub port {
    my ($this, $port_name) = @_;
    return $this->{'PORTS'}->{$port_name};
}

1;
