#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Tab;

# Simulated /json response from Chrome
my $json_response = encode_json([
    {
        description => '',
        devtoolsFrontendUrl => '/devtools/inspector.html?ws=localhost:9222/devtools/page/ABC',
        id => 'ABC123',
        title => 'Google',
        type => 'page',
        url => 'https://www.google.com/',
        webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/ABC123',
    },
    {
        description => '',
        id => 'DEF456',
        title => '',
        type => 'background_page',
        url => 'chrome-extension://abcdef/background.html',
        webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/DEF456',
    },
    {
        description => '',
        id => 'GHI789',
        title => 'Omatic - Data Queue',
        type => 'page',
        url => 'https://see-dec.omaticcloud-dev.com/data-queue',
        webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/GHI789',
    },
    {
        description => '',
        id => 'JKL012',
        title => 'New Tab',
        type => 'page',
        url => 'edge://newtab/',
        webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/JKL012',
    },
]);

# Parse and filter to pages only
{
    my @tabs = Bmux::Tab::parse_tab_list($json_response);

    # Should filter out background_page
    is(scalar @tabs, 3, 'filtered to 3 page tabs');
}

# 1-based indexing
{
    my @tabs = Bmux::Tab::parse_tab_list($json_response);

    is($tabs[0]{index}, 1, 'first tab index is 1');
    is($tabs[1]{index}, 2, 'second tab index is 2');
    is($tabs[2]{index}, 3, 'third tab index is 3');
}

# Preserves fields
{
    my @tabs = Bmux::Tab::parse_tab_list($json_response);

    is($tabs[0]{id}, 'ABC123', 'tab 1 id');
    is($tabs[0]{title}, 'Google', 'tab 1 title');
    is($tabs[0]{url}, 'https://www.google.com/', 'tab 1 url');
    is($tabs[0]{ws_url}, 'ws://localhost:9222/devtools/page/ABC123', 'tab 1 ws_url');

    is($tabs[1]{id}, 'GHI789', 'tab 2 id');
    is($tabs[1]{title}, 'Omatic - Data Queue', 'tab 2 title');
    is($tabs[1]{url}, 'https://see-dec.omaticcloud-dev.com/data-queue', 'tab 2 url');
}

# Find tab by index
{
    my @tabs = Bmux::Tab::parse_tab_list($json_response);
    my $tab = Bmux::Tab::find_by_index(\@tabs, 2);

    is($tab->{id}, 'GHI789', 'find by index 2');
    is($tab->{title}, 'Omatic - Data Queue', 'find by index 2 title');
}

# Find tab by index — out of range
{
    my @tabs = Bmux::Tab::parse_tab_list($json_response);
    my $tab = Bmux::Tab::find_by_index(\@tabs, 99);

    is($tab, undef, 'out of range returns undef');
}

# Format tab list for display
{
    my @tabs = Bmux::Tab::parse_tab_list($json_response);
    my $output = Bmux::Tab::format_tab_list(\@tabs);

    like($output, qr/1:.*Google/, 'display has tab 1 Google');
    like($output, qr/2:.*Omatic/, 'display has tab 2 Omatic');
    like($output, qr/3:.*New Tab/, 'display has tab 3 New Tab');
}

# Empty response
{
    my @tabs = Bmux::Tab::parse_tab_list('[]');
    is(scalar @tabs, 0, 'empty list');
}

# --- tab kill: CDP command builder ---
{
    use Bmux::CDP;
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = $cdp->build_command('Target.closeTarget', { targetId => 'ABC123' });
    my $msg = decode_json($json);

    is($msg->{method}, 'Target.closeTarget', 'closeTarget method');
    is($msg->{params}{targetId}, 'ABC123', 'closeTarget targetId');
}

# --- tab kill: integration with mock CDP ---
{
    package MockCDPTab;
    sub new { bless { calls => [] }, shift }
    sub send_command {
        my ($self, $method, $params) = @_;
        push @{$self->{calls}}, { method => $method, params => $params };
        return { success => JSON::PP::true };
    }
    sub close {}

    package main;
    use Bmux::Tab;

    my $mock = MockCDPTab->new();
    Bmux::Tab::close_target($mock, 'GHI789');

    is(scalar @{$mock->{calls}}, 1, 'tab kill: one CDP call');
    is($mock->{calls}[0]{method}, 'Target.closeTarget', 'tab kill: correct method');
    is($mock->{calls}[0]{params}{targetId}, 'GHI789', 'tab kill: correct targetId');
}

done_testing;
