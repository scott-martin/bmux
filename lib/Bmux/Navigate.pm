package Bmux::Navigate;
use strict;
use warnings;

sub cmd_goto {
    my ($cdp, $url) = @_;
    return $cdp->build_command('Page.navigate', { url => $url });
}

sub cmd_back {
    my ($cdp) = @_;
    return $cdp->build_command('Runtime.evaluate', {
        expression => 'history.back()',
    });
}

sub cmd_forward {
    my ($cdp) = @_;
    return $cdp->build_command('Runtime.evaluate', {
        expression => 'history.forward()',
    });
}

sub cmd_reload {
    my ($cdp) = @_;
    return $cdp->build_command('Page.reload');
}

1;
