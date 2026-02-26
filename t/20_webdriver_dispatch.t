#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Test the dispatch logic module (not full Bmux.pm which has side effects)
use Bmux::Session;
use Bmux::Browser;
use Bmux::WebDriver::Navigate;
use Bmux::WebDriver::Element;
use Bmux::WebDriver::Input;
use Bmux::WebDriver::Capture;
use Bmux::WebDriver::Eval;
use Bmux::WebDriver::Inspect;

# --- Dispatch routing logic ---

# Given a session, determine which protocol to use
sub dispatch_protocol {
    my ($session) = @_;
    return 'webdriver' if Bmux::Session::is_webdriver_session($session);
    return 'cdp' if Bmux::Session::is_cdp_session($session);
    return 'unknown';
}

{
    my $safari = { type => 'webdriver', port => 4444, session_id => 'abc' };
    my $chrome = { type => 'cdp', port => 9222, pid => 1234 };
    my $legacy = { port => 9222, pid => 1234 };  # no type field
    
    is(dispatch_protocol($safari), 'webdriver', 'safari dispatches to webdriver');
    is(dispatch_protocol($chrome), 'cdp', 'chrome dispatches to cdp');
    is(dispatch_protocol($legacy), 'cdp', 'legacy session dispatches to cdp');
}

# --- WebDriver command dispatch ---

# Mock client that records calls
{
    package MockWebDriverClient;
    my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';
    
    sub new { bless { calls => [], responses => {} }, shift }
    sub session_id { 'test-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        return { $ELEMENT_KEY => 'elem-id' } if $path =~ /\/element$/;
        return $self->{responses}{post} // undef;
    }
    sub get {
        my ($self, $path) = @_;
        push @{$self->{calls}}, { method => 'GET', path => $path };
        return $self->{responses}{get} // '<html></html>';
    }
    sub calls { shift->{calls} }
    sub set_response { my ($self, $k, $v) = @_; $self->{responses}{$k} = $v }
    
    package main;
}

# Dispatch navigation commands to WebDriver
{
    my $client = MockWebDriverClient->new();
    
    Bmux::WebDriver::Navigate::run_goto($client, 'https://example.com');
    like($client->calls->[-1]{path}, qr/\/url$/, 'goto dispatches to WebDriver navigate');
    
    Bmux::WebDriver::Navigate::run_back($client);
    like($client->calls->[-1]{path}, qr/\/back$/, 'back dispatches to WebDriver');
    
    Bmux::WebDriver::Navigate::run_forward($client);
    like($client->calls->[-1]{path}, qr/\/forward$/, 'forward dispatches to WebDriver');
    
    Bmux::WebDriver::Navigate::run_reload($client);
    like($client->calls->[-1]{path}, qr/\/refresh$/, 'reload dispatches to WebDriver');
}

# Dispatch input commands to WebDriver
{
    my $client = MockWebDriverClient->new();
    
    Bmux::WebDriver::Input::run_click($client, 'button');
    my @calls = @{$client->calls};
    like($calls[-1]{path}, qr/\/click$/, 'click dispatches to WebDriver');
}

{
    my $client = MockWebDriverClient->new();
    
    Bmux::WebDriver::Input::run_fill($client, 'input', 'text');
    my @calls = @{$client->calls};
    like($calls[-1]{path}, qr/\/value$/, 'fill dispatches to WebDriver');
}

# Dispatch capture to WebDriver
{
    my $client = MockWebDriverClient->new();
    $client->set_response(get => '<html><body>Test</body></html>');
    
    my $result = Bmux::WebDriver::Capture::run_capture($client, undef, 0);
    like($client->calls->[-1]{path}, qr/\/source$/, 'capture dispatches to WebDriver source');
}

# Dispatch eval to WebDriver
{
    my $client = MockWebDriverClient->new();
    $client->set_response(post => 'result');
    
    Bmux::WebDriver::Eval::run_eval($client, 'return 1');
    like($client->calls->[-1]{path}, qr/\/execute\/sync$/, 'eval dispatches to WebDriver execute');
}

# Dispatch cookies to WebDriver
{
    my $client = MockWebDriverClient->new();
    $client->set_response(get => [{ name => 'test', value => 'val' }]);
    
    Bmux::WebDriver::Inspect::run_cookies($client);
    like($client->calls->[-1]{path}, qr/\/cookie$/, 'cookies dispatches to WebDriver');
}

# Dispatch storage to WebDriver (via script)
{
    my $client = MockWebDriverClient->new();
    $client->set_response(post => '{"key":"value"}');
    
    Bmux::WebDriver::Inspect::run_storage($client, 0);
    like($client->calls->[-1]{path}, qr/\/execute/, 'storage dispatches via execute');
    like($client->calls->[-1]{body}{script}, qr/localStorage/, 'storage uses localStorage script');
}

# --- Unsupported commands error gracefully ---

{
    eval { Bmux::WebDriver::Inspect::run_console() };
    like($@, qr/not supported/i, 'console errors on WebDriver');
}

{
    eval { Bmux::WebDriver::Inspect::run_network() };
    like($@, qr/not supported/i, 'network errors on WebDriver');
}

{
    eval { Bmux::WebDriver::Inspect::run_scripts() };
    like($@, qr/not supported/i, 'scripts errors on WebDriver');
}

# --- Browser name to protocol mapping ---

{
    for my $browser (qw(chrome edge brave)) {
        ok(Bmux::Browser::is_cdp_browser($browser), "$browser -> CDP");
        ok(!Bmux::Browser::is_webdriver_browser($browser), "$browser not WebDriver");
    }
    
    ok(Bmux::Browser::is_webdriver_browser('safari'), 'safari -> WebDriver');
    ok(!Bmux::Browser::is_cdp_browser('safari'), 'safari not CDP');
}

done_testing;
