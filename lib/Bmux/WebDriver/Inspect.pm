package Bmux::WebDriver::Inspect;
use strict;
use warnings;
use JSON::PP qw(encode_json);

sub get_cookies_request {
    my ($session_id) = @_;
    return {
        method => 'GET',
        path   => "/session/$session_id/cookie",
    };
}

sub get_cookie_request {
    my ($session_id, $name) = @_;
    return {
        method => 'GET',
        path   => "/session/$session_id/cookie/$name",
    };
}

sub local_storage_script {
    return 'return JSON.stringify(localStorage);';
}

sub session_storage_script {
    return 'return JSON.stringify(sessionStorage);';
}

# High-level runners

sub run_cookies {
    my ($client) = @_;
    my $session_id = $client->session_id;
    my $cookies = $client->get("/session/$session_id/cookie");
    return encode_json($cookies);
}

sub run_storage {
    my ($client, $session_flag) = @_;
    my $session_id = $client->session_id;
    my $script = $session_flag ? session_storage_script() : local_storage_script();
    
    my $result = $client->post(
        "/session/$session_id/execute/sync",
        {
            script => $script,
            args   => [],
        }
    );
    return $result;
}

# Unsupported commands (WebDriver has no equivalent)

sub run_console {
    die "Console inspection is not supported in WebDriver (Safari)\n";
}

sub run_network {
    die "Network inspection is not supported in WebDriver (Safari)\n";
}

sub run_scripts {
    die "Script listing is not supported in WebDriver (Safari)\n";
}

1;
