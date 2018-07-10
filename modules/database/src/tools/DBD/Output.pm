######################################################################
# SPDX-License-Identifier: EPICS
# EPICS BASE is distributed subject to a Software License Agreement
# found in file LICENSE that is included with this distribution.
######################################################################

package DBD::Output;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(&OutputDBD &OutputDB &FlattenDB &FlattenMacros);

our $debug = 0;

use DBD;
use DBD::Base;
use DBD::Breaktable;
use DBD::Database;
use DBD::Device;
use DBD::Driver;
use DBD::Link;
use DBD::Menu;
use DBD::Recordtype;
use DBD::Recfield;
use DBD::Record;
use DBD::Registrar;
use DBD::Function;
use DBD::Variable;

# Output Database Definitions

sub OutputDBD {
    my ($out, $dbd) = @_;
    OutputMenus($out, $dbd->menus);
    OutputRecordtypes($out, $dbd->recordtypes);
    OutputDrivers($out, $dbd->drivers);
    OutputLinks($out, $dbd->links);
    OutputRegistrars($out, $dbd->registrars);
    OutputFunctions($out, $dbd->functions);
    OutputVariables($out, $dbd->variables);
    OutputBreaktables($out, $dbd->breaktables);
}

sub OutputMenus {
    my ($out, $menus) = @_;
    for my $name (sort keys %{$menus}) {
        my $menu = $menus->{$name};
        printf $out "menu(%s) {\n", $name;
        printf $out "    choice(%s, \"%s\")\n", @{$_}
            foreach $menu->choices;
        print $out "}\n";
    }
}

sub OutputRecordtypes {
    my ($out, $recordtypes) = @_;
    for my $name (sort keys %{$recordtypes}) {
        my $recordtype = $recordtypes->{$name};
        printf $out "recordtype(%s) {\n", $name;
        print $out "    %$_\n"
            foreach $recordtype->cdefs;
        for my $field ($recordtype->fields) {
            printf $out "    field(%s, %s) {\n",
                $field->name, $field->dbf_type;
            my $attributes = $field->attributes;
            for my $attr (sort keys %{$attributes}) {
                my $val = $attributes->{$attr};
                printf $out "        %s(%s)\n", $attr, qval($val);
            }
            print $out "    }\n";
        }
        printf $out "}\n";
        printf $out "device(%s, %s, %s, \"%s\")\n",
            $name, $_->link_type, $_->name, $_->choice
            foreach $recordtype->devices;
    }
}

sub OutputDrivers {
    my ($out, $drivers) = @_;
    printf $out "driver(%s)\n", $_
        foreach sort keys %{$drivers};
}

sub OutputLinks {
    my ($out, $links) = @_;
    for my $name (sort keys %{$links}) {
        my $link = $links->{$name};
        printf $out "link(%s, %s)\n", $link->key, $name;
    }
}

sub OutputRegistrars {
    my ($out, $registrars) = @_;
    printf $out "registrar(%s)\n", $_
        foreach sort keys %{$registrars};
}

sub OutputFunctions {
    my ($out, $functions) = @_;
    printf $out "function(%s)\n", $_
        foreach sort keys %{$functions};
}

sub OutputVariables {
    my ($out, $variables) = @_;
    for my $name (sort keys %{$variables}) {
        my $variable = $variables->{$name};
        printf $out "variable(%s, %s)\n", $name, $variable->var_type;
    }
}

sub OutputBreaktables {
    my ($out, $breaktables) = @_;
    for my $name (sort keys %{$breaktables}) {
        my $breaktable = $breaktables->{$name};
        printf $out "breaktable(\"%s\") {\n", $name;
        printf $out "    %s, %s\n", @{$_}
            foreach $breaktable->points;
        print $out "}\n";
    }
}

# Output Database Instances

sub OutputDB {
    my ($out, $db) = @_;
    printf $out "# Expansion of %s\n\n", $db->name;
    if ($db->is_template) {
        printf $out "template(\"%s\") {\n", $db->description;
        for my $name (sort keys %{$db->ports}) {
            my $value = $db->ports->{$name};
            my $desc = $db->port_description($name);
            if ($desc eq '') {
                printf $out "    port(%s, \"%s\")\n", $name, $value;
            }
            else {
                printf $out "    port(%s, \"%s\", \"%s\")\n", $name, $value, $desc;
            }
        }
        print $out "}\n\n";
    }
    OutputRecords($out, $db->records);
    OutputExpands($out, $db->expands);
}

sub FlattenDB {
    my ($out, $db, $vars, $home) = @_;
    $home = 'top' unless $home;
    printf $out "# %s\n\n", $db->name;
    my $flattened_content;
    open my $flat, '>', \$flattened_content
        or die "Internal error, $@";
    # Convert our record instances to $flattened_content
    OutputRecords($flat, $db->records);
    # Go through each child template instance to be expanded
    while (my ($instance, $exp) = each %{$db->expands}) {
        die "Database not loaded for $instance"
            unless $exp->database;
        # Get the macros to be passed down
        my $where = "$home/$instance";
        my $macros = $exp->instance_vars->{$where};
        die "Macros not defined for $where"
            unless $macros;
        # Expand the child template instance
        printf $flat "\n# expand(\"%s\", %s)\n", $exp->filename, $instance;
        FlattenDB($flat, $exp->database, $macros, $where);
        printf $flat "# end(%s)\n", $instance;
    }
    close $flat;
    # Finally expand any ports and macros in the generated output
    my $cooked = $vars->expandString($flattened_content);
    die "Undefined macros present with -V\n"
        unless defined $cooked;
    print $out $cooked;
}

sub FlattenMacros {
    my ($db, $macros) = @_;
    my $undefs = ExpandMacros($db, $macros);
    my $again = $undefs;
    while ($again) {
        # Repeat until all have been expanded or progress has stopped
        $again = ExpandMacros($db, $macros);
        ($again, $undefs) = ($again && ($again < $undefs), $again);
    }
    return $undefs;
}

sub ExpandMacros {
    my ($db, $vars, $home) = @_;
    $home = 'top' unless $home;
    printf "ExpandMacros(%s)\n", $home if $debug;
    my $undefs = 0;
    # Go through each child template instance to be expanded
    while (my ($instance, $exp) = each %{$db->expands}) {
        die "Database not loaded for $instance"
            unless $exp->database;
        # Set up the macros to be passed down
        my $macros;
        my $where = "$home/$instance";
        if (exists $exp->instance_vars->{$where}) {
            $macros = $exp->instance_vars->{$where};
            print "$where: Macros found:\n" if $debug;
            $macros->reportMacros($where) if $debug;
        }
        else {
            $macros = EPICS::macLib->new();
            $macros->suppressWarning($vars->{noWarn});
            $exp->instance_vars->{$where} = $macros;
            print "$where: No macros yet\n" if $debug;
        }
        while (my ($name, $raw) = each %{$exp->macros}) {
            # Expand macros in macro value using the parent's context
            my $value = $vars->expandString($raw);
            $macros->putValue($name, $value);
            $undefs++ if $macros->expandString($value) =~ m/ \$ [({] /x;
            print "  $where: Macro $name := $raw => $value\n" if $debug;
        }
        # Collect the port values from this template instance
        while (my ($name, $raw) = each %{$exp->database->ports}) {
            # Expand macros in the port value using the child's context
            my $value = $macros->expandString($raw);
            $vars->putValue("$instance.$name", $value);
            $undefs++ if $macros->expandString($value) =~ m/ \$ [({] /x;
            print "  $where: Port $instance.$name := $raw => $value\n" if $debug;
        }
        # Recurse into child template instances
        $undefs += ExpandMacros($exp->database, $macros, $where);
        print "$where: Macros on exit:\n" if $debug;
        $macros->reportMacros($where) if $debug;
    }
    printf "ExpandMacros(%s) returning %d\n", $home, $undefs if $debug;
    return $undefs;
}

sub OutputRecords {
    my ($out, $records) = @_;
    for my $name (sort keys %{$records}) {
        my $rec = $records->{$name};
        next if $name ne $rec->name; # Alias
        printf $out "record(%s, \"%s\") {\n", $rec->recordtype->name, $name;
        printf $out "    alias(\"%s\")\n", $_
            foreach $rec->aliases;
        for my $recfield ($rec->recfields) {
            my $field_name = $recfield->name;
            my $value = $rec->get_field($field_name);
            printf $out "    field(%s, %s)\n", $field_name, qval($value)
                if defined $value;
        }
        printf $out "    info(\"%s\", %s)\n", $_, qval($rec->info_value($_))
            foreach $rec->info_names;
        print $out "}\n";
    }
}

sub qval {
    local ($_) = @_;
    return $_
        if m/^ (?: \{ .* \} | \[ .* \] | " .* " ) $/x;

    return "\"$_\""
        if m/[^a-zA-Z0-9_\-+.]/x;

    return $_;
}

sub OutputExpands {
    my ($out, $expands) = @_;
    for my $instance (sort keys %{$expands}) {
        my $exp = $expands->{$instance};
        printf $out "expand(\"%s\", %s) {\n", $exp->filename, $instance;
        printf $out "    macro(%s, \"%s\")\n", $_, $exp->macro($_)
            foreach keys %{$exp->macros};
        print $out "}\n";
    }
}

1;
