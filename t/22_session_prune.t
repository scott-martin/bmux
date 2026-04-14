#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Path qw(rmtree);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Session;
use Bmux::Browser;

my $tmpdir = "$FindBin::Bin/tmp_prune_$$";
END { rmtree($tmpdir) if -d $tmpdir }

# prune_stale exists
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    ok($mgr->can('prune_stale'), 'prune_stale method exists');
}

# prune_stale removes sessions with dead PIDs
SKIP: {
    skip 'WSL prune uses CDP port probes — tested via integration', 3
        if Bmux::Browser::is_wsl();

    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    # PID 99999999 should not exist on any system
    $mgr->save_session('dead', {
        type => 'cdp',
        port => 9222,
        pid  => 99999999,
        bin  => 'msedge.exe',
    });

    # Current process PID is alive
    $mgr->save_session('alive', {
        type => 'cdp',
        port => 9223,
        pid  => $$,
        bin  => 'msedge.exe',
    });

    my $pruned = $mgr->prune_stale();
    is($pruned, 1, 'pruned 1 stale session');

    my $sessions = $mgr->load_sessions();
    ok(!exists $sessions->{dead}, 'dead session removed');
    ok(exists $sessions->{alive}, 'alive session preserved');
}

# WSL: prune removes sessions whose CDP port is unreachable
SKIP: {
    skip 'WSL-only test', 2 unless Bmux::Browser::is_wsl();

    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    # Port 9299 — nothing should be listening here
    $mgr->save_session('stale_wsl', {
        type => 'cdp',
        port => 9299,
        pid  => 1,
        bin  => 'msedge.exe',
    });

    my $pruned = $mgr->prune_stale();
    is($pruned, 1, 'pruned unreachable WSL session');

    my $sessions = $mgr->load_sessions();
    ok(!exists $sessions->{stale_wsl}, 'stale WSL session removed');
}

# prune_stale returns 0 when nothing to prune
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    my $pruned = $mgr->prune_stale();
    is($pruned, 0, 'nothing to prune');
}

# prune_stale handles empty session file
{
    rmtree($tmpdir);
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    my $pruned = $mgr->prune_stale();
    is($pruned, 0, 'empty state returns 0');
}

done_testing;
