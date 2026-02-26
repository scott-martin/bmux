package Bmux::WebDriver::Navigate;
use strict;
use warnings;

sub navigate_request {
    my ($session_id, $url) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/url",
        body   => { url => $url },
    };
}

sub back_request {
    my ($session_id) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/back",
        body   => {},
    };
}

sub forward_request {
    my ($session_id) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/forward",
        body   => {},
    };
}

sub refresh_request {
    my ($session_id) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/refresh",
        body   => {},
    };
}

sub get_url_request {
    my ($session_id) = @_;
    return {
        method => 'GET',
        path   => "/session/$session_id/url",
    };
}

sub get_title_request {
    my ($session_id) = @_;
    return {
        method => 'GET',
        path   => "/session/$session_id/title",
    };
}

# High-level runners

sub run_goto {
    my ($client, $url) = @_;
    $client->post("/session/" . $client->session_id . "/url", { url => $url });
}

sub run_back {
    my ($client) = @_;
    $client->post("/session/" . $client->session_id . "/back", {});
}

sub run_forward {
    my ($client) = @_;
    $client->post("/session/" . $client->session_id . "/forward", {});
}

sub run_reload {
    my ($client) = @_;
    $client->post("/session/" . $client->session_id . "/refresh", {});
}

1;
