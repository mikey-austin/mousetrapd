#!/usr/bin/perl

package MT::TokenBucket;

use strict;
use warnings;
use MT::Config;
use MT::Logger;

sub new {
    my $class = shift;
    my $self = {
        _buckets => {}
    };
    bless $self, $class;
}

sub check {
    my ($self, $label) = @_;
    my ($new, $now, $diff, $rate, $threshold) = (0, time, undef, undef, 0);

    return 1 if grep(/^$label$/, @{MT::Config->get('whitelist')});

    $new = 1 if not exists $self->{_buckets}->{$label};

    if(exists MT::Config->get('overrides')->{$label}) {
        if(MT::Config->get('overrides')->{$label}->{event_max}) {
            $self->{_buckets}->{$label}->{max} = MT::Config->get('overrides')->{$label}->{event_max};
        }
        else {
            $self->{_buckets}->{$label}->{max} = MT::Config->get('event_max');
        }

        if(MT::Config->get('overrides')->{$label}->{event_period}) {
            $self->{_buckets}->{$label}->{period} = MT::Config->get('overrides')->{$label}->{event_period};
        }
        else {
            $self->{_buckets}->{$label}->{period} = MT::Config->get('event_period');
        }

        if(MT::Config->get('overrides')->{$label}->{threshold}) {
            $threshold = MT::Config->get('overrides')->{$label}->{threshold};
        }
        else {
            $threshold = MT::Config->get('threshold');
        }
    }
    else {
        $self->{_buckets}->{$label}->{max} = MT::Config->get('event_max');
        $self->{_buckets}->{$label}->{period} = MT::Config->get('event_period');
        $threshold = MT::Config->get('threshold');
    }

    if($new) {
        $self->{_buckets}->{$label}->{allowance} = $self->{_buckets}->{$label}->{max};
        $self->{_buckets}->{$label}->{last_check} = $now;
        $self->{_buckets}->{$label}->{threshold} = $threshold;
    }

    $diff = ($now - $self->{_buckets}->{$label}->{last_check});
    $rate = (1.0 * $self->{_buckets}->{$label}->{max}) / $self->{_buckets}->{$label}->{period};
    $self->{_buckets}->{$label}->{last_check} = $now;

    # Top up the bucket to simulate adding (max / period) tokens per second.
    $self->{_buckets}->{$label}->{allowance} += ($diff * $rate);
    if($self->{_buckets}->{$label}->{allowance} > $self->{_buckets}->{$label}->{max}) {
        $self->{_buckets}->{$label}->{allowance} = $self->{_buckets}->{$label}->{max};
    }
    elsif($self->{_buckets}->{$label}->{allowance} < 0) {
        $self->{_buckets}->{$label}->{allowance} = 0;
    }

    if($self->{_buckets}->{$label}->{allowance} < 1.0) {
        #
        # This label has been trapped.
        #
        $self->{_buckets}->{$label}->{threshold} -= 1;
        if($self->{_buckets}->{$label}->{threshold} < 1.0) {
            $self->{_buckets}->{$label}->{threshold} = 0;
            return 0;
        }
    }
    else {
        # This label is still within the threshold.
        $self->{_buckets}->{$label}->{allowance} -= 1.0;
        $self->{_buckets}->{$label}->{threshold} += 1;
        if($self->{_buckets}->{$label}->{threshold} > $threshold) {
            $self->{_buckets}->{$label}->{threshold} = $threshold;
        }
    }

    MT::Logger->debug(
        'Label ' . $label . ': '
        . $self->{_buckets}->{$label}->{allowance} . ', '
        . $self->{_buckets}->{$label}->{threshold});

    return 1;
}

1;
