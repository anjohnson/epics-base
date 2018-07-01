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
    while (my ($name, $menu) = each %{$menus}) {
        printf $out "menu(%s) {\n", $name;
        printf $out "    choice(%s, \"%s\")\n", @{$_}
            foreach $menu->choices;
        print $out "}\n";
    }
}

sub OutputRecordtypes {
    my ($out, $recordtypes) = @_;
    while (my ($name, $recordtype) = each %{$recordtypes}) {
        printf $out "recordtype(%s) {\n", $name;
        print $out "    %$_\n"
            foreach $recordtype->cdefs;
        foreach my $field ($recordtype->fields) {
            printf $out "    field(%s, %s) {\n",
                $field->name, $field->dbf_type;
            while (my ($attr, $val) = each %{$field->attributes}) {
                $val = "\"$val\""
                    if $val !~ m/^$RXname$/x
                       || $attr eq 'prompt'
                       || $attr eq 'initial';
                printf $out "        %s(%s)\n", $attr, $val;
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
        foreach keys %{$drivers};
}

sub OutputLinks {
    my ($out, $links) = @_;
    while (my ($name, $link) = each %{$links}) {
        printf $out "link(%s, %s)\n", $link->key, $name;
    }
}

sub OutputRegistrars {
    my ($out, $registrars) = @_;
    printf $out "registrar(%s)\n", $_
        foreach keys %{$registrars};
}

sub OutputFunctions {
    my ($out, $functions) = @_;
    printf $out "function(%s)\n", $_
        foreach keys %{$functions};
}

sub OutputVariables {
    my ($out, $variables) = @_;
    while (my ($name, $variable) = each %{$variables}) {
        printf $out "variable(%s, %s)\n", $name, $variable->var_type;
    }
}

sub OutputBreaktables {
    my ($out, $breaktables) = @_;
    while (my ($name, $breaktable) = each %{$breaktables}) {
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
        while (my ($name, $value) = each %{$db->ports}) {
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
    my ($out, $db, $vars) = @_;
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
        my $macros = $exp->instance_vars->{$instance};
        die "Macros not defined for $instance"
            unless $macros;
        # Expand the child template instance
        printf $flat "\n# expand(\"%s\", %s)\n", $exp->filename, $instance;
        FlattenDB($flat, $exp->database, $macros);
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
    my ($db, $vars) = @_;
    printf "FlattenMacros(%s)\n", $db->name if $debug;
    my $undefs = 0;
    # Go through each child template instance to be expanded
    while (my ($instance, $exp) = each %{$db->expands}) {
        die "Database not loaded for $instance"
            unless $exp->database;
        # Set up the macros to be passed down
        my $macros;
        if (exists $exp->instance_vars->{$instance}) {
            $macros = $exp->instance_vars->{$instance};
        }
        else {
            $macros = EPICS::macLib->new();
            $exp->instance_vars->{$instance} = $macros;
        }
        $macros->suppressWarning($vars->{noWarn});
        while (my ($name, $raw) = each %{$exp->macros}) {
            # Expand macros in macro value using the parent's context
            my $value = $vars->expandString($raw);
            $macros->putValue($name, $value);
            $undefs++ if $value =~ m/ \$ [\(\{] /x;
            print "  Macro $name = $value\n" if $debug;
        }
        # Collect the port values from this template instance
        while (my ($name, $raw) = each %{$exp->database->ports}) {
            # Expand macros in the port value using the child's context
            my $value = $macros->expandString($raw);
            $vars->putValue("$instance.$name", $value);
            $undefs++ if $value =~ m/ \$ [\(\{] /x;
            print "  Port $instance.$name = $value\n" if $debug;
        }
        # Recurse into child template instances
        $undefs += FlattenMacros($exp->database, $macros);
        $macros->reportMacros if $debug;
    }
    printf "FlattenMacros(%s) returning %d\n", $db->name, $undefs if $debug;
    return $undefs;
}

sub OutputRecords {
    my ($out, $records) = @_;
    while (my ($name, $rec) = each %{$records}) {
        next if $name ne $rec->name; # Alias
        printf $out "record(%s, \"%s\") {\n", $rec->recordtype->name, $name;
        printf $out "    alias(\"%s\")\n", $_
            foreach $rec->aliases;
        foreach my $recfield ($rec->recfields) {
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
    while (my ($instance, $exp) = each %{$expands}) {
        printf $out "expand(\"%s\", %s) {\n", $exp->filename, $instance;
        printf $out "    macro(%s, \"%s\")\n", $_, $exp->macro($_)
            foreach keys %{$exp->macros};
        print $out "}\n";
    }
}

1;
