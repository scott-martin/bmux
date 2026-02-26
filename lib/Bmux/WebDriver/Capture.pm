package Bmux::WebDriver::Capture;
use strict;
use warnings;
use Bmux::WebDriver::Element;

# WebDriver element ID key
my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';

sub get_source_request {
    my ($session_id) = @_;
    return {
        method => 'GET',
        path   => "/session/$session_id/source",
    };
}

sub execute_request {
    my ($session_id, $script, $args) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/execute/sync",
        body   => {
            script => $script,
            args   => $args // [],
        },
    };
}

sub outer_html_script {
    return 'return arguments[0].outerHTML;';
}

sub strip_html {
    my ($html) = @_;
    
    # Remove script and style blocks
    $html =~ s/<script[^>]*>.*?<\/script>//gsi;
    $html =~ s/<style[^>]*>.*?<\/style>//gsi;
    
    # Remove all tags
    $html =~ s/<[^>]+>//g;
    
    # Decode common entities
    $html =~ s/&nbsp;/ /g;
    $html =~ s/&amp;/&/g;
    $html =~ s/&lt;/</g;
    $html =~ s/&gt;/>/g;
    $html =~ s/&quot;/"/g;
    
    # Collapse whitespace
    $html =~ s/\s+/ /g;
    $html =~ s/^\s+//;
    $html =~ s/\s+$//;
    
    return $html;
}

# High-level runners

sub run_capture {
    my ($client, $selector, $plain) = @_;
    my $session_id = $client->session_id;
    my $html;
    
    if ($selector) {
        # Find element, then get its outerHTML via script
        my $response = $client->post(
            "/session/$session_id/element",
            {
                using => Bmux::WebDriver::Element::selector_strategy($selector),
                value => $selector,
            }
        );
        my $element_id = $response->{$ELEMENT_KEY};
        
        # Execute script to get outerHTML
        # WebDriver requires element reference in special format
        my $element_ref = { $ELEMENT_KEY => $element_id };
        $html = $client->post(
            "/session/$session_id/execute/sync",
            {
                script => outer_html_script(),
                args   => [$element_ref],
            }
        );
    } else {
        # Full page source
        $html = $client->get("/session/$session_id/source");
    }
    
    return $plain ? strip_html($html) : $html;
}

1;
