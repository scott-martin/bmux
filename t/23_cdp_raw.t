#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::CDP;

# Raw CDP command: method only, no params
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = $cdp->build_command('Performance.getMetrics');
    my $msg = decode_json($json);

    is($msg->{method}, 'Performance.getMetrics', 'raw cdp method');
    ok(!exists $msg->{params}, 'no params when none given');
}

# Raw CDP command: method + params from parsed JSON
{
    my $cdp = Bmux::CDP->new();
    my $params = decode_json('{"expression":"1+1","returnByValue":true}');
    my ($id, $json) = $cdp->build_command('Runtime.evaluate', $params);
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.evaluate', 'raw cdp method with params');
    is($msg->{params}{expression}, '1+1', 'params expression');
    is($msg->{params}{returnByValue}, JSON::PP::true, 'params boolean');
}

# Raw CDP command: HeapProfiler domain (the one we need for memory testing)
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = $cdp->build_command('HeapProfiler.takeHeapSnapshot');
    my $msg = decode_json($json);

    is($msg->{method}, 'HeapProfiler.takeHeapSnapshot', 'heap profiler method');
}

# Raw CDP command: Performance.enable (idempotent, required before getMetrics)
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = $cdp->build_command('Performance.enable');
    my $msg = decode_json($json);

    is($msg->{method}, 'Performance.enable', 'performance enable method');
}

# Simulate the dispatch-layer JSON parsing (what _cmd_cdp will do)
{
    my $json_str = '{"prototypeObjectId":"12345"}';
    my $params = eval { decode_json($json_str) };
    ok(!$@, 'valid JSON parses without error');
    is($params->{prototypeObjectId}, '12345', 'parsed param value');
}

# Invalid JSON produces a useful error
{
    my $bad_json = '{not valid json}';
    my $params = eval { decode_json($bad_json) };
    ok($@, 'invalid JSON dies');
    like($@, qr/malformed|unexpected|error/i, 'error message is descriptive');
}

done_testing;
