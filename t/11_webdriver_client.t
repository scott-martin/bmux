#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Client;

# --- URL building ---

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'sess123');
    
    is($client->build_url('/session'), 'http://localhost:4444/session', 'build_url absolute path');
    is($client->build_url('/session/sess123/url'), 'http://localhost:4444/session/sess123/url', 'build_url with session');
}

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444/', 'sess123');
    
    is($client->build_url('/session'), 'http://localhost:4444/session', 'build_url strips trailing slash from base');
}

# --- Session ID accessor ---

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'abc-123-def');
    
    is($client->session_id, 'abc-123-def', 'session_id accessor');
}

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444');
    
    is($client->session_id, undef, 'session_id undef when not set');
}

# --- Request building ---

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'sess123');
    my $req = $client->build_request('POST', '/session/sess123/url', { url => 'https://example.com' });
    
    is($req->{method}, 'POST', 'request method');
    is($req->{url}, 'http://localhost:4444/session/sess123/url', 'request url');
    is($req->{body}{url}, 'https://example.com', 'request body');
    is($req->{headers}{'Content-Type'}, 'application/json', 'content-type header');
}

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'sess123');
    my $req = $client->build_request('GET', '/session/sess123/source');
    
    is($req->{method}, 'GET', 'GET request method');
    is($req->{url}, 'http://localhost:4444/session/sess123/source', 'GET request url');
    ok(!exists $req->{body}, 'GET request has no body');
}

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'sess123');
    my $req = $client->build_request('DELETE', '/session/sess123');
    
    is($req->{method}, 'DELETE', 'DELETE request method');
}

# --- Response parsing ---

# Success response
{
    my $json = encode_json({
        value => { sessionId => 'new-session-id', capabilities => {} }
    });
    my $result = Bmux::WebDriver::Client::parse_response($json);
    
    is($result->{sessionId}, 'new-session-id', 'parse success response value');
}

# Null value (valid for some commands)
{
    my $json = encode_json({ value => undef });
    my $result = Bmux::WebDriver::Client::parse_response($json);
    
    is($result, undef, 'parse null value response');
}

# String value
{
    my $json = encode_json({ value => '<html>...</html>' });
    my $result = Bmux::WebDriver::Client::parse_response($json);
    
    is($result, '<html>...</html>', 'parse string value response');
}

# Error response
{
    my $json = encode_json({
        value => {
            error => 'no such element',
            message => 'Unable to find element with selector: #missing',
            stacktrace => '...'
        }
    });
    
    eval { Bmux::WebDriver::Client::parse_response($json) };
    like($@, qr/no such element/, 'error response throws');
    like($@, qr/Unable to find element/, 'error includes message');
}

# Invalid session error
{
    my $json = encode_json({
        value => {
            error => 'invalid session id',
            message => 'Session not found'
        }
    });
    
    eval { Bmux::WebDriver::Client::parse_response($json) };
    like($@, qr/invalid session id/, 'invalid session error throws');
}

# --- Convenience methods build correct requests ---

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'sess123');
    
    my $post_req = $client->build_post('/session/sess123/url', { url => 'https://example.com' });
    is($post_req->{method}, 'POST', 'build_post method');
    is($post_req->{body}{url}, 'https://example.com', 'build_post body');
    
    my $get_req = $client->build_get('/session/sess123/source');
    is($get_req->{method}, 'GET', 'build_get method');
    
    my $del_req = $client->build_delete('/session/sess123');
    is($del_req->{method}, 'DELETE', 'build_delete method');
}

# --- Session path helper ---

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444', 'sess123');
    
    is($client->session_path('/url'), '/session/sess123/url', 'session_path appends to session');
    is($client->session_path('/element'), '/session/sess123/element', 'session_path for element');
}

{
    my $client = Bmux::WebDriver::Client->new('http://localhost:4444');
    
    eval { $client->session_path('/url') };
    like($@, qr/no session/i, 'session_path dies without session_id');
}

done_testing;
