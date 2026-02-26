package Bmux::WebDriver::Session;
use strict;
use warnings;
use JSON::PP qw(decode_json);

sub driver_command {
    my ($port) = @_;
    return ('safaridriver', '-p', $port);
}

sub session_capabilities {
    return {
        capabilities => {
            alwaysMatch => {
                browserName => 'safari',
            }
        }
    };
}

sub create_session_request {
    return {
        method => 'POST',
        path   => '/session',
        body   => session_capabilities(),
    };
}

sub parse_create_response {
    my ($json) = @_;
    my $data = decode_json($json);
    my $value = $data->{value};
    
    if (ref $value eq 'HASH' && $value->{error}) {
        die "WebDriver error: $value->{error} - $value->{message}\n";
    }
    
    return $value->{sessionId};
}

sub delete_session_request {
    my ($session_id) = @_;
    return {
        method => 'DELETE',
        path   => "/session/$session_id",
    };
}

sub status_request {
    return {
        method => 'GET',
        path   => '/status',
    };
}

sub parse_status_response {
    my ($json) = @_;
    my $data = decode_json($json);
    my $value = $data->{value};
    return $value->{ready} ? 1 : 0;
}

1;
