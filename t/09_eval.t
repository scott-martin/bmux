#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Eval;
use Bmux::CDP;

# Build eval command
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Eval::cmd_evaluate($cdp, 'document.title');
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.evaluate', 'eval method');
    is($msg->{params}{expression}, 'document.title', 'eval expression');
    is($msg->{params}{returnByValue}, JSON::PP::true, 'eval returnByValue');
}

# Format string result
{
    my $result = { result => { type => 'string', value => 'Hello World' } };
    is(Bmux::Eval::format_result($result), 'Hello World', 'format string');
}

# Format number result
{
    my $result = { result => { type => 'number', value => 42 } };
    is(Bmux::Eval::format_result($result), '42', 'format number');
}

# Format object result
{
    my $result = { result => { type => 'object', value => { foo => 'bar' } } };
    my $out = Bmux::Eval::format_result($result);
    like($out, qr/"foo"/, 'format object has key');
    like($out, qr/"bar"/, 'format object has value');
}

# Format undefined
{
    my $result = { result => { type => 'undefined' } };
    is(Bmux::Eval::format_result($result), 'undefined', 'format undefined');
}

# Format null
{
    my $result = { result => { type => 'object', subtype => 'null', value => undef } };
    is(Bmux::Eval::format_result($result), 'null', 'format null');
}

# Format error/exception
{
    my $result = {
        exceptionDetails => {
            exception => { description => 'ReferenceError: foo is not defined' }
        }
    };
    my $out = Bmux::Eval::format_result($result);
    like($out, qr/ReferenceError/, 'format exception');
}

done_testing;
