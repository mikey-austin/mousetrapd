#!/usr/bin/perl

package MT::Logger;

use strict;
use warnings;
use POSIX qw(strftime);
use MT::Config;
use Sys::Syslog qw(:standard :macros);

sub err {
    my ($class, $message) = @_;
    return $class->write($message, 'err');
}

sub debug {
    my ($class, $message) = @_;
    return $class->write($message, 'debug');
}

sub info {
    my ($class, $message) = @_;
    return $class->write($message, 'info');
}

sub write {
    my ($class, $message, $priority) = @_;

    $priority ||= 'warning';

    if(defined MT::Config->get('logging_facility')
       and MT::Config->get('logging_facility') eq 'syslog')
    {
        # Setup syslog.
        openlog(MT::Config->name, MT::Config->get('syslog_options'), 'user');
        syslog($priority, '%s', $message);
        closelog();
    }
    else {
        # Just log to the console.
        my $timestamp = strftime "%F %T", localtime;
        print "[$timestamp]: $message\n";
    }

    return $message;
}

1;
