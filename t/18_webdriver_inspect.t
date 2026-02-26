#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Inspect;

# --- Get cookies request ---

{
    my $req = Bmux::WebDriver::Inspect::get_cookies_request('sess123');
    
    is($req->{method}, 'GET', 'get cookies is GET');
    is($req->{path}, '/session/sess123/cookie', 'get cookies path');
}

# --- Get named cookie request ---

{
    my $req = Bmux::WebDriver::Inspect::get_cookie_request('sess123', 'session_id');
    
    is($req->{method}, 'GET', 'get named cookie is GET');
    is($req->{path}, '/session/sess123/cookie/session_id', 'get named cookie path');
}

# --- Storage scripts ---

{
    my $script = Bmux::WebDriver::Inspect::local_storage_script();
    
    like($script, qr/localStorage/, 'local storage script uses localStorage');
    like($script, qr/JSON\.stringify/, 'local storage script stringifies');
}

{
    my $script = Bmux::WebDriver::Inspect::session_storage_script();
    
    like($script, qr/sessionStorage/, 'session storage script uses sessionStorage');
}

# --- High-level runners with mock ---

{
    package MockClient;
    sub new { 
        my ($class, %responses) = @_;
        bless { calls => [], responses => \%responses }, $class;
    }
    sub session_id { 'mock-session' }
    sub get {
        my ($self, $path) = @_;
        push @{$self->{calls}}, { method => 'GET', path => $path };
        return $self->{responses}{get};
    }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        return $self->{responses}{post};
    }
    sub calls { shift->{calls} }
    
    package main;
}

# run_cookies
{
    my $cookies = [
        { name => 'session', value => 'abc123', domain => '.example.com' },
        { name => 'prefs', value => 'dark', domain => '.example.com' },
    ];
    my $client = MockClient->new(get => $cookies);
    
    my $result = Bmux::WebDriver::Inspect::run_cookies($client);
    
    like($result, qr/session/, 'run_cookies output has cookie name');
    like($result, qr/abc123/, 'run_cookies output has cookie value');
    like($client->calls->[0]{path}, qr/\/cookie$/, 'run_cookies calls cookie endpoint');
}

# run_storage (localStorage)
{
    my $storage = '{"theme":"dark","lang":"en"}';
    my $client = MockClient->new(post => $storage);
    
    my $result = Bmux::WebDriver::Inspect::run_storage($client, 0);
    
    like($result, qr/theme/, 'run_storage returns localStorage');
    like($client->calls->[0]{path}, qr/execute/, 'run_storage executes script');
    like($client->calls->[0]{body}{script}, qr/localStorage/, 'run_storage script uses localStorage');
}

# run_storage (sessionStorage)
{
    my $storage = '{"temp":"value"}';
    my $client = MockClient->new(post => $storage);
    
    my $result = Bmux::WebDriver::Inspect::run_storage($client, 1);
    
    like($client->calls->[0]{body}{script}, qr/sessionStorage/, 'run_storage --session uses sessionStorage');
}

# --- Unsupported commands ---

{
    eval { Bmux::WebDriver::Inspect::run_console() };
    like($@, qr/not supported|unsupported/i, 'console not supported');
}

{
    eval { Bmux::WebDriver::Inspect::run_network() };
    like($@, qr/not supported|unsupported/i, 'network not supported');
}

{
    eval { Bmux::WebDriver::Inspect::run_scripts() };
    like($@, qr/not supported|unsupported/i, 'scripts not supported');
}

done_testing;
