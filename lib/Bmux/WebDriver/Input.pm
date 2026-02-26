package Bmux::WebDriver::Input;
use strict;
use warnings;
use Bmux::WebDriver::Element;

# WebDriver element ID key
my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';

sub click_request {
    my ($session_id, $element_id) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/element/$element_id/click",
        body   => {},
    };
}

sub clear_request {
    my ($session_id, $element_id) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/element/$element_id/clear",
        body   => {},
    };
}

sub send_keys_request {
    my ($session_id, $element_id, $text) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/element/$element_id/value",
        body   => { text => $text },
    };
}

# High-level runners

sub _find_element {
    my ($client, $selector) = @_;
    my $response = $client->post(
        "/session/" . $client->session_id . "/element",
        {
            using => Bmux::WebDriver::Element::selector_strategy($selector),
            value => $selector,
        }
    );
    return $response->{$ELEMENT_KEY};
}

sub run_click {
    my ($client, $selector) = @_;
    my $element_id = _find_element($client, $selector);
    $client->post("/session/" . $client->session_id . "/element/$element_id/click", {});
}

sub run_fill {
    my ($client, $selector, $value) = @_;
    my $element_id = _find_element($client, $selector);
    my $session_id = $client->session_id;
    $client->post("/session/$session_id/element/$element_id/clear", {});
    $client->post("/session/$session_id/element/$element_id/value", { text => $value });
}

sub run_type {
    my ($client, $selector, $value) = @_;
    # WebDriver doesn't distinguish type from fill at protocol level
    run_fill($client, $selector, $value);
}

sub run_wait {
    my ($client, $selector, $timeout, $interval) = @_;
    $timeout  //= 30;
    $interval //= 1;
    
    my $elapsed = 0;
    while ($elapsed < $timeout) {
        eval { _find_element($client, $selector) };
        return 1 unless $@;  # Found
        
        sleep $interval if $interval > 0;
        $elapsed += ($interval || 1);
    }
    return 0;  # Timeout
}

1;
