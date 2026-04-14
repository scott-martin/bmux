#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Tab;
use Bmux::Session;
use File::Path qw(rmtree);

# This test verifies that tab targeting is stable when Chrome's /json
# endpoint returns tabs in a different order. The bug: attach to tab 2,
# Chrome reorders tabs, next command hits the wrong tab.

# Two /json responses with the SAME tabs in DIFFERENT order.
my $order_a = encode_json([
    { id => 'AAA', type => 'page', title => 'Google',     url => 'https://google.com',     webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/AAA' },
    { id => 'BBB', type => 'page', title => 'Data Queue',  url => 'https://app.com/data-queue', webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/BBB' },
    { id => 'CCC', type => 'page', title => 'Settings',    url => 'https://app.com/settings',   webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/CCC' },
]);

my $order_b = encode_json([
    { id => 'CCC', type => 'page', title => 'Settings',    url => 'https://app.com/settings',   webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/CCC' },
    { id => 'AAA', type => 'page', title => 'Google',     url => 'https://google.com',     webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/AAA' },
    { id => 'BBB', type => 'page', title => 'Data Queue',  url => 'https://app.com/data-queue', webSocketDebuggerUrl => 'ws://localhost:9222/devtools/page/BBB' },
]);

# Index-based lookup is NOT stable across reorders
{
    my @tabs_a = Bmux::Tab::parse_tab_list($order_a);
    my @tabs_b = Bmux::Tab::parse_tab_list($order_b);

    my $tab_a2 = Bmux::Tab::find_by_index(\@tabs_a, 2);
    my $tab_b2 = Bmux::Tab::find_by_index(\@tabs_b, 2);

    is($tab_a2->{id}, 'BBB', 'order A: index 2 = BBB (Data Queue)');
    is($tab_b2->{id}, 'AAA', 'order B: index 2 = AAA (Google) — DIFFERENT tab!');
    isnt($tab_a2->{id}, $tab_b2->{id}, 'index-based lookup is unstable across reorders');
}

# ID-based lookup IS stable across reorders
{
    my @tabs_a = Bmux::Tab::parse_tab_list($order_a);
    my @tabs_b = Bmux::Tab::parse_tab_list($order_b);

    my $tab_a = Bmux::Tab::find_by_id(\@tabs_a, 'BBB');
    my $tab_b = Bmux::Tab::find_by_id(\@tabs_b, 'BBB');

    is($tab_a->{id}, 'BBB', 'order A: find BBB by id');
    is($tab_b->{id}, 'BBB', 'order B: find BBB by id');
    is($tab_a->{title}, $tab_b->{title}, 'same tab regardless of order');
    is($tab_a->{url}, $tab_b->{url}, 'same URL regardless of order');
}

# --- Attached target format: session=targetid ---

my $tmpdir = "$FindBin::Bin/tmp_tab_stability_$$";
END { rmtree($tmpdir) if -d $tmpdir }

# New format: session=targetid stores and retrieves the target ID
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    $mgr->save_attached('edge=BBB');
    my $attached = $mgr->load_attached();
    is($attached, 'edge=BBB', 'new format round-trips');
}

# Session name extracted from new format
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    $mgr->save_attached('edge=BBB');
    my $attached = $mgr->load_attached();
    my ($session) = $attached =~ /^(\w+)/;
    is($session, 'edge', 'session name extracted from new format');
}

# Target ID extracted from new format
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    $mgr->save_attached('edge=BBB');
    my $attached = $mgr->load_attached();
    my ($target_id) = $attached =~ /=(.+)$/;
    is($target_id, 'BBB', 'target ID extracted from new format');
}

# Legacy format still parses (backwards compat)
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    $mgr->save_attached('edge:3');
    my $attached = $mgr->load_attached();
    ok($attached !~ /=/, 'legacy format has no =');
    my ($tab) = $attached =~ /:(\d+)$/;
    is($tab, 3, 'legacy index extracted');
}

# Session-only format (no tab) still works
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    $mgr->save_attached('edge');
    my $attached = $mgr->load_attached();
    ok($attached !~ /[=:]/, 'session-only has no separator');
    my ($session) = $attached =~ /^(\w+)/;
    is($session, 'edge', 'session-only name extracted');
}

# End-to-end: attach by index, look up by ID across reordered tab lists
{
    my @tabs_a = Bmux::Tab::parse_tab_list($order_a);
    my @tabs_b = Bmux::Tab::parse_tab_list($order_b);

    # Simulate: user runs "bmux attach edge:2" when order is A
    my $chosen = Bmux::Tab::find_by_index(\@tabs_a, 2);
    is($chosen->{id}, 'BBB', 'initial attach picks BBB');

    # Store as session=targetid
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    $mgr->save_attached("edge=$chosen->{id}");

    # Later: Chrome returns tabs in order B
    my $attached = $mgr->load_attached();
    my ($target_id) = $attached =~ /=(.+)$/;
    my $reconnected = Bmux::Tab::find_by_id(\@tabs_b, $target_id);

    is($reconnected->{id}, 'BBB', 'reconnected to same tab after reorder');
    is($reconnected->{title}, 'Data Queue', 'still Data Queue');
    is($reconnected->{url}, 'https://app.com/data-queue', 'still same URL');
}

done_testing;
