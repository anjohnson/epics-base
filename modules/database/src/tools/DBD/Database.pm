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

1;
