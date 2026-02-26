#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Navigate;
use Bmux::CDP;

# goto builds Page.navigate command
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Navigate::cmd_goto($cdp, 'https://example.com');
    my $msg = decode_json($json);

    is($msg->{method}, 'Page.navigate', 'goto uses Page.navigate');
    is($msg->{params}{url}, 'https://example.com', 'goto url param');
}

# back builds history.back() via Runtime.evaluate
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Navigate::cmd_back($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.evaluate', 'back uses Runtime.evaluate');
    like($msg->{params}{expression}, qr/history\.back/, 'back expression');
}

# forward builds history.forward() via Runtime.evaluate
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Navigate::cmd_forward($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.evaluate', 'forward uses Runtime.evaluate');
    like($msg->{params}{expression}, qr/history\.forward/, 'forward expression');
}

# reload builds Page.reload
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Navigate::cmd_reload($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Page.reload', 'reload uses Page.reload');
}

done_testing;
