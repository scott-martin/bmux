#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Eval;

# --- Execute request ---

{
    my $req = Bmux::WebDriver::Eval::execute_request('sess123', 'return 1 + 1');
    
    is($req->{method}, 'POST', 'execute is POST');
    is($req->{path}, '/session/sess123/execute/sync', 'execute path');
    is($req->{body}{script}, 'return 1 + 1', 'execute script');
    is_deeply($req->{body}{args}, [], 'execute args empty by default');
}

{
    my $req = Bmux::WebDriver::Eval::execute_request('sess123', 'return arguments[0] + arguments[1]', [1, 2]);
    
    is_deeply($req->{body}{args}, [1, 2], 'execute with args');
}

# --- Async execute request ---

{
    my $req = Bmux::WebDriver::Eval::execute_async_request('sess123', 'callback(42)');
    
    is($req->{method}, 'POST', 'execute async is POST');
    is($req->{path}, '/session/sess123/execute/async', 'execute async path');
}

# --- Format result ---

# Primitives
{
    is(Bmux::WebDriver::Eval::format_result(42), '42', 'format number');
    is(Bmux::WebDriver::Eval::format_result('hello'), 'hello', 'format string');
    is(Bmux::WebDriver::Eval::format_result(JSON::PP::true), 'true', 'format true');
    is(Bmux::WebDriver::Eval::format_result(JSON::PP::false), 'false', 'format false');
}

# Null and undefined
{
    is(Bmux::WebDriver::Eval::format_result(undef), 'null', 'format null');
}

# Objects and arrays
{
    my $obj = { foo => 'bar', num => 123 };
    my $result = Bmux::WebDriver::Eval::format_result($obj);
    like($result, qr/"foo"/, 'format object contains key');
    like($result, qr/"bar"/, 'format object contains value');
}

{
    my $arr = [1, 2, 3];
    my $result = Bmux::WebDriver::Eval::format_result($arr);
    is($result, '[1,2,3]', 'format array');
}

# Nested structure
{
    my $nested = { items => [1, 2], meta => { count => 2 } };
    my $result = Bmux::WebDriver::Eval::format_result($nested);
    like($result, qr/items/, 'format nested has items');
    like($result, qr/meta/, 'format nested has meta');
}

# --- High-level runner with mock ---

{
    package MockClient;
    sub new { 
        my ($class, $response) = @_;
        bless { calls => [], response => $response }, $class;
    }
    sub session_id { 'mock-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        return $self->{response};
    }
    sub calls { shift->{calls} }
    
    package main;
}

# run_eval returns formatted result
{
    my $client = MockClient->new('Document Title');
    my $result = Bmux::WebDriver::Eval::run_eval($client, 'return document.title');
    
    is($result, 'Document Title', 'run_eval returns string result');
    is($client->calls->[0]{body}{script}, 'return document.title', 'run_eval sends script');
}

{
    my $client = MockClient->new(42);
    my $result = Bmux::WebDriver::Eval::run_eval($client, 'return 6 * 7');
    
    is($result, '42', 'run_eval formats number');
}

{
    my $client = MockClient->new({ key => 'value' });
    my $result = Bmux::WebDriver::Eval::run_eval($client, 'return {key: "value"}');
    
    like($result, qr/"key"/, 'run_eval formats object');
}

{
    my $client = MockClient->new(undef);
    my $result = Bmux::WebDriver::Eval::run_eval($client, 'return undefined');
    
    is($result, 'null', 'run_eval formats undefined as null');
}

# --- Auto-wrap scripts without return ---

{
    my $wrapped = Bmux::WebDriver::Eval::wrap_script('document.title');
    like($wrapped, qr/^return\s/, 'wrap_script adds return');
    like($wrapped, qr/document\.title/, 'wrap_script preserves expression');
}

{
    my $wrapped = Bmux::WebDriver::Eval::wrap_script('return document.title');
    is($wrapped, 'return document.title', 'wrap_script leaves return intact');
}

{
    my $wrapped = Bmux::WebDriver::Eval::wrap_script('  return foo');
    is($wrapped, '  return foo', 'wrap_script handles leading whitespace with return');
}

{
    my $wrapped = Bmux::WebDriver::Eval::wrap_script('1 + 1');
    like($wrapped, qr/^return 1 \+ 1/, 'wrap_script wraps simple expression');
}

# run_eval uses wrap_script
{
    my $client = MockClient->new('wrapped result');
    Bmux::WebDriver::Eval::run_eval($client, 'document.title');
    
    like($client->calls->[0]{body}{script}, qr/^return/, 'run_eval wraps script');
}

done_testing;
