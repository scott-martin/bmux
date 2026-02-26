package Bmux::WebDriver::Element;
use strict;
use warnings;
use JSON::PP qw(decode_json);

# WebDriver element ID key (from W3C spec)
my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';

sub selector_strategy {
    my ($selector) = @_;
    return 'xpath' if $selector =~ m{^/};
    return 'css selector';
}

sub find_element_request {
    my ($session_id, $selector) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/element",
        body   => {
            using => selector_strategy($selector),
            value => $selector,
        },
    };
}

sub find_elements_request {
    my ($session_id, $selector) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/elements",
        body   => {
            using => selector_strategy($selector),
            value => $selector,
        },
    };
}

sub extract_element_id {
    my ($json) = @_;
    my $data = decode_json($json);
    my $value = $data->{value};
    
    # Check for error
    if (ref $value eq 'HASH' && $value->{error}) {
        die "WebDriver error: $value->{error} - $value->{message}\n";
    }
    
    # Extract ID from WebDriver format
    return $value->{$ELEMENT_KEY};
}

sub extract_element_ids {
    my ($json) = @_;
    my $data = decode_json($json);
    my $value = $data->{value};
    
    return () unless ref $value eq 'ARRAY';
    return map { $_->{$ELEMENT_KEY} } @$value;
}

# High-level runners

sub run_find_element {
    my ($client, $selector) = @_;
    my $response = $client->post(
        "/session/" . $client->session_id . "/element",
        {
            using => selector_strategy($selector),
            value => $selector,
        }
    );
    return $response->{$ELEMENT_KEY};
}

sub run_find_elements {
    my ($client, $selector) = @_;
    my $response = $client->post(
        "/session/" . $client->session_id . "/elements",
        {
            using => selector_strategy($selector),
            value => $selector,
        }
    );
    return map { $_->{$ELEMENT_KEY} } @$response;
}

1;
