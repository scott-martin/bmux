#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Path qw(rmtree);
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Session;

my $tmpdir = "$FindBin::Bin/tmp_session_$$";
END { rmtree($tmpdir) if -d $tmpdir }

# Save and load a session
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    $mgr->save_session('edge', {
        port => 9222,
        pid  => 1234,
        bin  => 'msedge.exe',
    });

    my $sessions = $mgr->load_sessions();
    ok(exists $sessions->{edge}, 'session saved');
    is($sessions->{edge}{port}, 9222, 'port preserved');
    is($sessions->{edge}{pid}, 1234, 'pid preserved');
    is($sessions->{edge}{bin}, 'msedge.exe', 'bin preserved');
}

# Save multiple sessions
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    $mgr->save_session('chrome', {
        port => 9223,
        pid  => 5678,
        bin  => 'chrome.exe',
    });

    my $sessions = $mgr->load_sessions();
    ok(exists $sessions->{edge}, 'edge still exists');
    ok(exists $sessions->{chrome}, 'chrome added');
    is($sessions->{chrome}{port}, 9223, 'chrome port');
}

# Remove a session
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    $mgr->remove_session('edge');
    my $sessions = $mgr->load_sessions();
    ok(!exists $sessions->{edge}, 'edge removed');
    ok(exists $sessions->{chrome}, 'chrome still exists');
}

# Remove non-existent session — no error
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    eval { $mgr->remove_session('firefox') };
    ok(!$@, 'removing non-existent session does not error');
}

# Load from non-existent state dir — empty hash
{
    my $mgr = Bmux::Session->new(state_dir => "$tmpdir/nonexistent");
    my $sessions = $mgr->load_sessions();
    is(ref $sessions, 'HASH', 'returns hash ref');
    is(scalar keys %$sessions, 0, 'empty when no state dir');
}

# Save and load attached target
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    $mgr->save_attached('edge:3');
    my $attached = $mgr->load_attached();
    is($attached, 'edge:3', 'attached round-trips');
}

# Update attached
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    $mgr->save_attached('chrome:1');
    is($mgr->load_attached(), 'chrome:1', 'attached updated');
}

# Clear attached (detach)
{
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);

    $mgr->clear_attached();
    my $attached = $mgr->load_attached();
    is($attached, undef, 'attached cleared');
}

# Load attached when no file exists
{
    rmtree($tmpdir);
    my $mgr = Bmux::Session->new(state_dir => $tmpdir);
    my $attached = $mgr->load_attached();
    is($attached, undef, 'no attached file returns undef');
}

# State dir created automatically on save
{
    my $newdir = "$tmpdir/auto_create";
    my $mgr = Bmux::Session->new(state_dir => $newdir);

    $mgr->save_session('edge', { port => 9222, pid => 99, bin => 'msedge.exe' });
    ok(-d $newdir, 'state dir auto-created');

    my $sessions = $mgr->load_sessions();
    is($sessions->{edge}{port}, 9222, 'session saved to auto-created dir');
}

done_testing;
