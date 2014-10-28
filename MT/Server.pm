#!/usr/bin/perl

package MT::Server;

use strict;
use warnings;
use MT::Config;
use MT::Logger;
use MT::Watcher;
use MT::TokenBucket;
use IO::Select;
use IO::Handle;
use POSIX ();

use constant {
    DEFAULTS => [
        '/etc/mousetrap/mousetrap.conf',
        '/etc/mousetrap/mousetrap.yaml',
        ]
};

sub new {
    my ($class, $options) = @_;
    my $self = {
        _watchers        => {},
        _watcher_pids    => {},
        _watcher_handles => {},
        _options         => {},
        _token_bucket    => undef
    };

    # Load the configuration.
    MT::Config->new($options->{config}, $class->DEFAULTS);
    MT::Logger->info('Loading configuration from '
        . MT::Config->new->{_file});

    $self->{_options}->{pidfile} =
        $options->{pidfile} || MT::Config->get('pid_file');
    MT::Config->set('pidfile', $self->{_options}->{pidfile});

    # Set remaining options.
    $self->{_options}->{$_} = $options->{$_} for qw|daemonize user group config|;

    $self->{_token_bucket} = MT::TokenBucket->new;

    bless $self, $class;
}

sub start {
    my $self = shift;

    die MT::Logger->err('PID file exists, exiting...')
        if -e MT::Config->get('pidfile');

    if($self->{_options}->{daemonize}) {
        $self->daemonize;
    }

    $self->save_pid;

    # Start watcher processes.
    MT::Logger->write('Started mousetrap');

    $self->{_select} = IO::Select->new;
    $self->start_watchers;

    # Set the various signal handlers after the sender has been forked.
    $self->register_signals;

    # Start monitoring file descriptors.
    for(;;) {
        my @ready = $self->{_select}->can_read;
        foreach my $handle (@ready) {
            my $name = $self->{_watcher_handles}->{fileno($handle)};
            if(defined(my $label = <$handle>)) {
                chomp $label;
                if(not $self->{_token_bucket}->check($label)) {
                    $self->execute_action($name, $label);
                }
                else {
                    MT::Logger->debug("$name:$label is OK");
                }
            }
        }
    }

    # Not reached.
}

sub execute_action {
    my ($self, $name, $label) = @_;

    my $action = MT::Config->get('sources')->{$name}->{action};
    $action =~ s/%L/$label/;

    if((my $pid = fork()) == 0) {
        # In child.
        exec $action or die "Could not execute $action";
    }
    elsif(not defined $pid) {
        MT::Logger->err("Could not fork action for $name");
    }

    # In parent.
    MT::Logger->info("Executed action for $name: $action");
}

sub daemonize {
    my $self = shift;

    # Log to syslog.
    MT::Config->set('logging_facility', 'syslog');

    # Drop privileges.
    if(defined $self->{_options}->{user}) {
        my $uid = getpwnam($self->{_options}->{user});
        POSIX::setuid($uid)
            or die MT::Logger->err("Could not setuid to $uid, exiting...", 'err');
    }

    if(defined $self->{_options}->{group}) {
        my $gid = getgrnam($self->{_options}->{group});
        POSIX::setgid($gid)
            or die MT::Logger->err("Could not setgid to $gid, exiting...", 'err');
    }

    # Become session leader.
    POSIX::setsid or die MT::Logger->err("Could not setsid: $!");

    # Fork a child process.
    my $pid = fork();
    if($pid < 0) {
        die MT::Logger->err("Could not fork: $!");
    }
    elsif($pid) {
        exit;
    }

    # Change root directory and clear file creation mask.
    chdir('/');
    umask(0);

    # Clear all file descriptors.
    foreach(0 .. (POSIX::sysconf(&POSIX::_SC_OPEN_MAX) || 1024)) {
        POSIX::close($_);
    }

    open(STDIN, "</dev/null");
    open(STDOUT, ">/dev/null");
    open(STDERR, ">&STDOUT");

    MT::Logger->write("Daemonized with pid $$");
}

sub save_pid {
    my $self = shift;

    open(PID, '>' . MT::Config->get('pidfile'))
        or die 'Could not open ' . MT::Config->get('pidfile')
        . ' for writing';
    print PID $$;
    close PID;
}

sub start_watchers {
    my $self = shift;

    foreach my $source_name (keys %{MT::Config->get('sources')}) {
        $self->start_watcher($source_name);
    }
}

sub start_watcher {
    my ($self, $name) = @_;
    my ($pid, $read, $write, $source);

    $source = MT::Config->get('sources')->{$name};
    pipe($read, $write);

    if(($pid = fork()) == 0) {
        # In child.
        my $watcher = MT::Watcher->new($name, $source, $write);
        close($read);
        $watcher->start;
    }
    elsif($pid < 0) {
        die MT::Logger->err('Could not fork watcher process, exiting...');
    }
    else {
        close($write);
        $self->{_select}->add($read);
        $self->{_watcher_pids}->{$pid} = $name;
        $self->{_watcher_handles}->{fileno($read)} = $name;
        $self->{_watchers}->{$name} = {
            _pid  => $pid,
            _read => $read
        };
    }

    return $read;
}

sub stop_watchers {
    my ($self, $sig) = @_;

    # Default to SIGTERM.
    $sig ||= 'TERM';

    foreach my $name (keys %{$self->{_watchers}}) {
        $self->stop_watcher($sig, $name);
    }
}

sub stop_watcher {
    my ($self, $sig, $name) = @_;

    # Default to SIGTERM.
    $sig ||= 'TERM';

    MT::Logger->write("Stopping watcher $name");
    my $pid = $self->{_watchers}->{$name}->{_pid};
    my $read = $self->{_watchers}->{$name}->{_read};
    $self->{_select}->remove($read);

    kill($sig, $pid) if defined $pid;
}

sub register_signals {
    my $self = shift;

    $SIG{'INT'} = $SIG{'TERM'} = sub {
        $self->shutdown;
        exit;
    };

    #
    # Reload the sender process on HUP.
    #
    $SIG{'HUP'} = sub {
        MT::Logger->write('Received HUP, reloading configuration...');
        MT::Config->reload($self->{_options}->{config}, $self->DEFAULTS);

        # Override any options set via command line.
        MT::Config->set('socket_path', $self->{_options}->{socket});
        MT::Config->set('pidfile', $self->{_options}->{pidfile});

        # The watchers will restart.
        $self->stop_watchers('HUP');
    };

    $SIG{'PIPE'} = sub {
        # Ignore, but maybe catch and restart the watcher?
    };

    #
    # Handle the deaths of the known child processes.
    #
    $SIG{'CHLD'} = sub {
        my ($child, $exit_status, $name);

        do {
            $child = waitpid(-1, POSIX::WNOHANG);
            $exit_status = POSIX::WEXITSTATUS($?);
            $name = $self->{_watcher_pids}->{$child};

            if(defined $name) {
                my $read = $self->{_watchers}->{$name}->{_read};
                delete $self->{_watcher_handles}->{fileno($read)};
                delete $self->{_watchers}->{$name};
                delete $self->{_watcher_pids}->{$child};

                if($exit_status != 0) {
                    MT::Logger->err('Watcher process died, exiting...');
                    $self->shutdown;
                    exit(1);
                }
                else {
                    MT::Logger->err('Watcher process restarting...');
                    $self->start_watcher($name);
                }
            }
        } while($child > 0);
    };
}

sub shutdown {
    my $self = shift;

    MT::Logger->write("Shutting down mousetrap $$...");
    $self->stop_watchers;

    # Clean up socket and pidfile.
    unlink(MT::Config->get('pidfile')) if -e MT::Config->get('pidfile');
}

1;
