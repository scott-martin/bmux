#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Navigate;

# --- Navigate request ---

{
    my $req = Bmux::WebDriver::Navigate::navigate_request('sess123', 'https://example.com');
    
    is($req->{method}, 'POST', 'navigate is POST');
    is($req->{path}, '/session/sess123/url', 'navigate path');
    is($req->{body}{url}, 'https://example.com', 'navigate body has url');
}

{
    my $req = Bmux::WebDriver::Navigate::navigate_request('abc', 'https://other.com/page');
    
    is($req->{path}, '/session/abc/url', 'navigate uses session id');
    is($req->{body}{url}, 'https://other.com/page', 'navigate uses full url');
}

# --- Back request ---

{
    my $req = Bmux::WebDriver::Navigate::back_request('sess123');
    
    is($req->{method}, 'POST', 'back is POST');
    is($req->{path}, '/session/sess123/back', 'back path');
    is_deeply($req->{body}, {}, 'back has empty body');
}

# --- Forward request ---

{
    my $req = Bmux::WebDriver::Navigate::forward_request('sess123');
    
    is($req->{method}, 'POST', 'forward is POST');
    is($req->{path}, '/session/sess123/forward', 'forward path');
    is_deeply($req->{body}, {}, 'forward has empty body');
}

# --- Refresh request ---

{
    my $req = Bmux::WebDriver::Navigate::refresh_request('sess123');
    
    is($req->{method}, 'POST', 'refresh is POST');
    is($req->{path}, '/session/sess123/refresh', 'refresh path');
    is_deeply($req->{body}, {}, 'refresh has empty body');
}

# --- Get current URL request ---

{
    my $req = Bmux::WebDriver::Navigate::get_url_request('sess123');
    
    is($req->{method}, 'GET', 'get url is GET');
    is($req->{path}, '/session/sess123/url', 'get url path');
}

# --- Get title request ---

{
    my $req = Bmux::WebDriver::Navigate::get_title_request('sess123');
    
    is($req->{method}, 'GET', 'get title is GET');
    is($req->{path}, '/session/sess123/title', 'get title path');
}

# --- High-level runner with mock client ---

{
    package MockClient;
    sub new { bless { calls => [] }, shift }
    sub session_id { 'mock-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        return undef;  # navigate returns null on success
    }
    sub get {
        my ($self, $path) = @_;
        push @{$self->{calls}}, { method => 'GET', path => $path };
        return 'https://example.com';
    }
    sub calls { shift->{calls} }
    
    package main;
    
    my $client = MockClient->new();
    Bmux::WebDriver::Navigate::run_goto($client, 'https://example.com');
    
    is(scalar @{$client->calls}, 1, 'run_goto makes one call');
    is($client->calls->[0]{method}, 'POST', 'run_goto uses POST');
    is($client->calls->[0]{path}, '/session/mock-session/url', 'run_goto path');
    is($client->calls->[0]{body}{url}, 'https://example.com', 'run_goto sends url');
}

{
    my $client = MockClient->new();
    Bmux::WebDriver::Navigate::run_back($client);
    
    is($client->calls->[0]{path}, '/session/mock-session/back', 'run_back path');
}

{
    my $client = MockClient->new();
    Bmux::WebDriver::Navigate::run_forward($client);
    
    is($client->calls->[0]{path}, '/session/mock-session/forward', 'run_forward path');
}

{
    my $client = MockClient->new();
    Bmux::WebDriver::Navigate::run_reload($client);
    
    is($client->calls->[0]{path}, '/session/mock-session/refresh', 'run_reload path');
}

done_testing;
