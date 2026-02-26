package Bmux::Capture;
use strict;
use warnings;

# Build DOM.getDocument command
sub cmd_get_document {
    my ($cdp) = @_;
    return $cdp->build_command('DOM.getDocument');
}

# Build DOM.getOuterHTML command for a specific node
sub cmd_get_outer_html {
    my ($cdp, $node_id) = @_;
    return $cdp->build_command('DOM.getOuterHTML', { nodeId => $node_id });
}

# Build DOM.querySelector command
sub cmd_query_selector {
    my ($cdp, $node_id, $selector) = @_;
    return $cdp->build_command('DOM.querySelector', {
        nodeId   => $node_id,
        selector => $selector,
    });
}

# Build DOM.querySelectorAll command
sub cmd_query_selector_all {
    my ($cdp, $node_id, $selector) = @_;
    return $cdp->build_command('DOM.querySelectorAll', {
        nodeId   => $node_id,
        selector => $selector,
    });
}

# Build DOM.performSearch for XPath queries
sub cmd_perform_search {
    my ($cdp, $query) = @_;
    return $cdp->build_command('DOM.performSearch', { query => $query });
}

# Detect if a selector is XPath (starts with / or //)
sub is_xpath {
    my ($selector) = @_;
    return ($selector =~ m{^/}) ? 1 : 0;
}

# Strip HTML tags, return text content
sub strip_html {
    my ($html) = @_;
    my $text = $html;
    $text =~ s/<[^>]*>//g;
    # Collapse runs of whitespace
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    return $text;
}

1;
