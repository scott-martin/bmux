package Bmux::Inspect;
use strict;
use warnings;
use JSON::PP;

# --- CDP command builders ---

sub cmd_storage {
    my ($cdp, $which) = @_;
    return $cdp->build_command('Runtime.evaluate', {
        expression    => "JSON.stringify($which)",
        returnByValue => JSON::PP::true,
    });
}

sub cmd_cookies {
    my ($cdp) = @_;
    return $cdp->build_command('Network.getCookies');
}

sub cmd_computed_style {
    my ($cdp, $node_id) = @_;
    return $cdp->build_command('CSS.getComputedStyleForNode', {
        nodeId => $node_id,
    });
}

sub cmd_matched_styles {
    my ($cdp, $node_id) = @_;
    return $cdp->build_command('CSS.getMatchedStylesForNode', {
        nodeId => $node_id,
    });
}

sub cmd_resource_tree {
    my ($cdp) = @_;
    return $cdp->build_command('Page.getResourceTree');
}

sub cmd_enable_runtime {
    my ($cdp) = @_;
    return $cdp->build_command('Runtime.enable');
}

sub cmd_enable_network {
    my ($cdp) = @_;
    return $cdp->build_command('Network.enable');
}

# --- Formatters ---

sub format_computed_style {
    my ($styles, $filter_prop) = @_;
    my @lines;
    for my $s (@$styles) {
        next if defined $filter_prop && $s->{name} ne $filter_prop;
        push @lines, "$s->{name}: $s->{value}";
    }
    return join("\n", @lines);
}

sub format_cookies {
    my ($cookies) = @_;
    my @lines;
    for my $c (@$cookies) {
        my $line = sprintf "%s=%s  domain=%s  path=%s",
            $c->{name}, $c->{value},
            $c->{domain} // '', $c->{path} // '/';
        $line .= "  secure" if $c->{secure};
        $line .= "  httpOnly" if $c->{httpOnly};
        push @lines, $line;
    }
    return join("\n", @lines);
}

1;
