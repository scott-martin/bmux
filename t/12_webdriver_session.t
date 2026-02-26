#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Session;

# --- Driver command building ---

{
    my @cmd = Bmux::WebDriver::Session::driver_command(4444);
    
    is($cmd[0], 'safaridriver', 'driver command is safaridriver');
    is($cmd[1], '-p', 'driver has -p flag');
    is($cmd[2], 4444, 'driver has port');
}

{
    my @cmd = Bmux::WebDriver::Session::driver_command(9515);
    
    is($cmd[2], 9515, 'driver uses specified port');
}

# --- Session capabilities ---

{
    my $caps = Bmux::WebDriver::Session::session_capabilities();
    
    is(ref $caps, 'HASH', 'capabilities is hashref');
    ok(exists $caps->{capabilities}, 'has capabilities key');
    is($caps->{capabilities}{alwaysMatch}{browserName}, 'safari', 'browserName is safari');
}

# --- Create session request ---

{
    my $req = Bmux::WebDriver::Session::create_session_request();
    
    is($req->{method}, 'POST', 'create session is POST');
    is($req->{path}, '/session', 'create session path');
    is($req->{body}{capabilities}{alwaysMatch}{browserName}, 'safari', 'create session has safari capability');
}

# --- Parse create session response ---

{
    my $response = {
        sessionId => 'abc-123-def',
        capabilities => {
            browserName => 'safari',
            browserVersion => '17.0',
            platformName => 'macOS'
        }
    };
    my $json = encode_json({ value => $response });
    
    my $session_id = Bmux::WebDriver::Session::parse_create_response($json);
    
    is($session_id, 'abc-123-def', 'parse session id from response');
}

{
    my $response = {
        sessionId => 'xyz-789',
        capabilities => {}
    };
    my $json = encode_json({ value => $response });
    
    my $session_id = Bmux::WebDriver::Session::parse_create_response($json);
    
    is($session_id, 'xyz-789', 'parse different session id');
}

# --- Delete session request ---

{
    my $req = Bmux::WebDriver::Session::delete_session_request('sess-456');
    
    is($req->{method}, 'DELETE', 'delete session is DELETE');
    is($req->{path}, '/session/sess-456', 'delete session path includes id');
}

# --- Status request (for polling) ---

{
    my $req = Bmux::WebDriver::Session::status_request();
    
    is($req->{method}, 'GET', 'status is GET');
    is($req->{path}, '/status', 'status path');
}

# --- Parse status response ---

{
    my $json = encode_json({
        value => {
            ready => JSON::PP::true,
            message => 'ready to create session'
        }
    });
    
    my $ready = Bmux::WebDriver::Session::parse_status_response($json);
    
    ok($ready, 'parse ready status');
}

{
    my $json = encode_json({
        value => {
            ready => JSON::PP::false,
            message => 'not ready'
        }
    });
    
    my $ready = Bmux::WebDriver::Session::parse_status_response($json);
    
    ok(!$ready, 'parse not ready status');
}

done_testing;
