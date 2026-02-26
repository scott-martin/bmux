#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::CDP;

# --- Command building ---

{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = $cdp->build_command('Page.navigate', { url => 'https://example.com' });
    my $msg = decode_json($json);

    is($id, 1, 'first command id is 1');
    is($msg->{id}, 1, 'json has matching id');
    is($msg->{method}, 'Page.navigate', 'json has method');
    is($msg->{params}{url}, 'https://example.com', 'json has params');
}

{
    my $cdp = Bmux::CDP->new();
    my ($id1, $json1) = $cdp->build_command('Page.navigate', { url => 'a' });
    my ($id2, $json2) = $cdp->build_command('Runtime.evaluate', { expression => 'x' });

    is($id1, 1, 'auto-increment: first id');
    is($id2, 2, 'auto-increment: second id');
}

# Command with no params
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = $cdp->build_command('Page.reload');
    my $msg = decode_json($json);

    is($msg->{method}, 'Page.reload', 'no-params command method');
    ok(!exists $msg->{params}, 'no params key when none given');
}

# --- Response parsing ---

# Success response
{
    my $json = encode_json({
        id     => 1,
        result => { frameId => 'abc123', loaderId => 'def456' },
    });
    my $resp = Bmux::CDP::parse_response($json);

    is($resp->{id}, 1, 'response id');
    is($resp->{result}{frameId}, 'abc123', 'response result field');
    ok(!$resp->{error}, 'no error on success');
}

# Error response
{
    my $json = encode_json({
        id    => 2,
        error => { code => -32000, message => 'Cannot navigate' },
    });
    my $resp = Bmux::CDP::parse_response($json);

    is($resp->{id}, 2, 'error response id');
    is($resp->{error}{code}, -32000, 'error code');
    is($resp->{error}{message}, 'Cannot navigate', 'error message');
}

# --- Event parsing ---

{
    my $json = encode_json({
        method => 'Page.loadEventFired',
        params => { timestamp => 1234567.89 },
    });
    my $evt = Bmux::CDP::parse_event($json);

    is($evt->{method}, 'Page.loadEventFired', 'event method');
    is($evt->{params}{timestamp}, 1234567.89, 'event params');
}

# --- Message classification ---

{
    my $response_json = encode_json({ id => 1, result => {} });
    my $event_json    = encode_json({ method => 'Page.loadEventFired', params => {} });
    my $error_json    = encode_json({ id => 2, error => { code => -1, message => 'fail' } });

    is(Bmux::CDP::classify($response_json), 'response', 'classify response');
    is(Bmux::CDP::classify($event_json), 'event', 'classify event');
    is(Bmux::CDP::classify($error_json), 'response', 'classify error as response');
}

done_testing;
