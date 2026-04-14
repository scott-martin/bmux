package Bmux::Tab;
use strict;
use warnings;
use JSON::PP;
use Bmux::Browser;

# Parse the /json endpoint response into a filtered, indexed tab list.
# Only includes targets of type "page".
# Returns list of hashrefs: { index, id, title, url, ws_url }
sub parse_tab_list {
    my ($json_str) = @_;
    my $raw = decode_json($json_str);

    my @tabs;
    my $idx = 1;
    for my $entry (@$raw) {
        next unless ($entry->{type} // '') eq 'page';
        push @tabs, {
            index  => $idx++,
            id     => $entry->{id},
            title  => $entry->{title} // '',
            url    => $entry->{url} // '',
            ws_url => _rewrite_ws_url($entry->{webSocketDebuggerUrl} // ''),
        };
    }

    return @tabs;
}

# Find a tab by 1-based index. Returns hashref or undef.
sub find_by_index {
    my ($tabs, $index) = @_;
    for my $tab (@$tabs) {
        return $tab if $tab->{index} == $index;
    }
    return undef;
}

# Find a tab by CDP target ID. Returns hashref or undef.
sub find_by_id {
    my ($tabs, $id) = @_;
    for my $tab (@$tabs) {
        return $tab if $tab->{id} eq $id;
    }
    return undef;
}

# Format tab list for human-readable display.
sub format_tab_list {
    my ($tabs) = @_;
    my @lines;
    for my $tab (@$tabs) {
        my $title = $tab->{title} || '(untitled)';
        # Truncate long titles
        $title = substr($title, 0, 50) . '...' if length($title) > 50;
        my $url = $tab->{url};
        $url = substr($url, 0, 60) . '...' if length($url) > 60;
        push @lines, sprintf("%d: %s  %s", $tab->{index}, $title, $url);
    }
    return join("\n", @lines);
}

# Close a tab via CDP Target.closeTarget
sub close_target {
    my ($cdp, $target_id) = @_;
    $cdp->send_command('Target.closeTarget', { targetId => $target_id });
}

sub _rewrite_ws_url {
    my ($url) = @_;
    return $url unless $url && Bmux::Browser::is_wsl();
    my $host = Bmux::Browser::cdp_host();
    # Only rewrite host — portproxy already returns the correct port
    $url =~ s{^(ws://)([^:]+)}{$1$host};
    return $url;
}

1;
