#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Browser;

# --- Unit tests for WSL bridge logic (run on any platform) ---

# cdp_port adds 10000 offset on WSL, returns unchanged otherwise
{
    my $port = Bmux::Browser::cdp_port(9222);
    if (Bmux::Browser::is_wsl()) {
        is($port, 19222, 'cdp_port adds 10000 on WSL');
    } else {
        is($port, 9222, 'cdp_port unchanged on non-WSL');
    }
}

# cdp_host returns non-empty string
{
    my $host = Bmux::Browser::cdp_host();
    ok(defined $host && length($host), 'cdp_host returns a value');
    if (Bmux::Browser::is_wsl()) {
        like($host, qr/^\d+\.\d+\.\d+\.\d+$/, 'cdp_host returns IP on WSL');
    } else {
        is($host, 'localhost', 'cdp_host returns localhost on non-WSL');
    }
}

# ensure_cdp_bridge returns immediately on non-WSL
SKIP: {
    skip 'WSL-only tests', 1 if Bmux::Browser::is_wsl();
    eval { Bmux::Browser::ensure_cdp_bridge(9222) };
    ok(!$@, 'ensure_cdp_bridge is a no-op on non-WSL');
}

# ensure_cdp_bridge exists and is callable
{
    ok(Bmux::Browser->can('ensure_cdp_bridge'), 'ensure_cdp_bridge exists');
}

done_testing;
