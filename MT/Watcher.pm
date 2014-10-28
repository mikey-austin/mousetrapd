#!/usr/bin/perl

package MT::Watcher;

use strict;
use warnings;
use MT::Config;
use MT::Logger;

sub new {
    my $class = shift;
    my $self = {
        _name          => shift,
        _source        => shift,
        _parent_handle => shift,
    };
    bless $self, $class;
}

sub start {
    my $self = shift;

    MT::Logger->write('Starting watcher for ' . $self->{_name}
        . ' -> ' . $self->{_source}->{file});

    #
    # These signals are considered abnormal, so return an exit code
    # greater than 0 so the parent knows something went wrong.
    #
    $SIG{'INT'} = $SIG{'TERM'} = sub { exit(1); };

    #
    # We use the following signal to indicate an expected reload.
    #
    $SIG{'HUP'} = sub { exit(0); };

    for(;;) {

    }

    # Not reached.
}

1;
