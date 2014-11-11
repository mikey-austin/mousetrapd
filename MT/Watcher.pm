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
        _read          => undef,
        _tail_pid      => undef
    };
    bless $self, $class;
}

sub start {
    my $self = shift;
    my @matches;

    MT::Logger->write('Starting watcher for ' . $self->{_name}
        . ' -> ' . $self->{_source}->{file});

    #
    # These signals are considered abnormal, so return an exit code
    # greater than 0 so the parent knows something went wrong.
    #
    $SIG{'INT'} = $SIG{'TERM'} = $SIG{'CHLD'} = $SIG{'PIPE'} = sub {
        $self->shutdown(1);
    };

    #
    # We use the following signal to indicate an expected reload.
    #
    $SIG{'HUP'} = sub {
        $self->shutdown(0);
    };

    $self->start_tail;

    my @patterns;

    # Add default pattern/index combo if they exist.
    my $pat = $self->{_source}->{pattern};
    my $ind   = $self->{_source}->{index} || 0;
    push @patterns, { pattern => $pat, index => $ind }
        if(defined $pat and defined $ind);

    if(defined $self->{_source}->{patterns}
       and ref $self->{_source}->{patterns} eq 'ARRAY')
    {
        foreach my $subpat (@{$self->{_source}->{patterns}}) {
            if(defined $subpat->{pattern}) {
                $subpat->{index} ||= 0;
                push @patterns, $subpat;
            }
        }
    }

    if(@patterns == 0) {
        MT::Logger->err("No configured patterns for " . $self->{_name});
        $self->shutdown(1);
    }

    while(my $buf = readline($self->{_read})) {
        foreach $pat (@patterns) {
            my ($pattern, $index) = ($pat->{pattern}, $pat->{index});
            if((@matches = ($buf =~ /$pattern/)) and $matches[$index]) {
                print { $self->{_parent_handle} } $matches[$index] . "\n";
                $self->{_parent_handle}->flush;
                last;
            }
        }
    }

    exit(1);
}

sub start_tail {
    my $self = shift;
    my ($read, $write, $pid);

    pipe($read, $write);
    $self->{_read} = $read;

    if(($pid = fork()) == 0) {
        # In child.
        close($read);
        close(STDERR);
        close(STDIN);

        # Ensure tail's stdout is sent through the pipe.
        if(fileno($write) != fileno(STDOUT)) {
            POSIX::dup2(fileno($write), POSIX::STDOUT_FILENO);
            close($write);
        }

        my $cmd = MT::Config->get('tail_file') . ' '
            . MT::Config->get('tail_args') . ' '
            . $self->{_source}->{file};

        exec $cmd or die "Could not exec $cmd";

        # Not reached.
    }
    elsif(not defined $pid) {
        die "Could not fork tail";
    }

    # In parent.
    $self->{_tail_pid} = $pid;
    close($write);
}

sub shutdown {
    my ($self, $ret_code) = @_;

    kill('KILL', $self->{_tail_pid})
        if defined $self->{_tail_pid};

    exit $ret_code;
}

1;
