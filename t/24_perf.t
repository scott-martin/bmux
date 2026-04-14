#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Perf;

# --- format_bytes ---

{
    is(Bmux::Perf::format_bytes(0), '0 B', 'format 0 bytes');
    is(Bmux::Perf::format_bytes(1023), '1023 B', 'format sub-KB');
    is(Bmux::Perf::format_bytes(1024), '1.0 KB', 'format 1 KB');
    is(Bmux::Perf::format_bytes(1048576), '1.0 MB', 'format 1 MB');
    is(Bmux::Perf::format_bytes(15728640), '15.0 MB', 'format 15 MB');
    is(Bmux::Perf::format_bytes(1073741824), '1.0 GB', 'format 1 GB');
}

# --- is_byte_metric ---

{
    ok(Bmux::Perf::is_byte_metric('JSHeapUsedSize'), 'heap used is bytes');
    ok(Bmux::Perf::is_byte_metric('JSHeapTotalSize'), 'heap total is bytes');
    ok(!Bmux::Perf::is_byte_metric('JSEventListeners'), 'listeners not bytes');
    ok(!Bmux::Perf::is_byte_metric('Nodes'), 'nodes not bytes');
}

# --- extract_metric ---

{
    my $metrics = [
        { name => 'JSEventListeners', value => 142 },
        { name => 'Nodes', value => 500 },
    ];
    is(Bmux::Perf::extract_metric($metrics, 'JSEventListeners'), 142, 'extract listeners');
    is(Bmux::Perf::extract_metric($metrics, 'Nodes'), 500, 'extract nodes');
    is(Bmux::Perf::extract_metric($metrics, 'Missing'), undef, 'extract missing returns undef');
}

# --- format_snapshot ---

{
    my $metrics = [
        { name => 'JSEventListeners', value => 142 },
        { name => 'JSHeapUsedSize',   value => 15728640 },
        { name => 'JSHeapTotalSize',  value => 33554432 },
        { name => 'Nodes',            value => 1523 },
        { name => 'Timestamp',        value => 1234567.89 },
    ];
    my $out = Bmux::Perf::format_snapshot($metrics);
    like($out, qr/JSEventListeners\s+142/, 'snapshot shows listeners');
    like($out, qr/JSHeapUsedSize\s+15\.0 MB/, 'snapshot shows heap human-readable');
    like($out, qr/Nodes\s+1523/, 'snapshot shows nodes');
}

# --- diff_metrics ---

# Normal diff
{
    my $before = [
        { name => 'JSEventListeners', value => 142 },
        { name => 'JSHeapUsedSize',   value => 15728640 },
        { name => 'Nodes',            value => 1523 },
    ];
    my $after = [
        { name => 'JSEventListeners', value => 98 },
        { name => 'JSHeapUsedSize',   value => 14680064 },
        { name => 'Nodes',            value => 1400 },
    ];
    my $diff = Bmux::Perf::diff_metrics($before, $after);
    my %by_name = map { $_->{name} => $_ } @$diff;

    is($by_name{JSEventListeners}{delta}, -44, 'diff listeners decreased');
    is($by_name{JSHeapUsedSize}{delta}, -1048576, 'diff heap decreased');
    is($by_name{Nodes}{delta}, -123, 'diff nodes decreased');
}

# No change
{
    my $same = [{ name => 'Nodes', value => 100 }];
    my $diff = Bmux::Perf::diff_metrics($same, $same);
    is($diff->[0]{delta}, 0, 'diff no change is zero');
}

# Increase (leak!)
{
    my $before = [{ name => 'JSEventListeners', value => 50 }];
    my $after  = [{ name => 'JSEventListeners', value => 70 }];
    my $diff = Bmux::Perf::diff_metrics($before, $after);
    is($diff->[0]{delta}, 20, 'diff increase is positive');
}

# --- format_diff ---

{
    my $diff = [
        { name => 'JSEventListeners', before => 142, after => 98,       delta => -44 },
        { name => 'JSHeapUsedSize',   before => 15728640, after => 14680064, delta => -1048576 },
        { name => 'Nodes',            before => 1523, after => 1400,    delta => -123 },
    ];
    my $out = Bmux::Perf::format_diff($diff);
    like($out, qr/JSEventListeners.*142.*98.*-44/, 'diff format listeners');
    like($out, qr/JSHeapUsedSize.*15\.0 MB.*14\.0 MB.*-1\.0 MB/, 'diff format heap');
}

# Positive delta gets + prefix
{
    my $diff = [
        { name => 'JSEventListeners', before => 50, after => 70, delta => 20 },
    ];
    my $out = Bmux::Perf::format_diff($diff);
    like($out, qr/\+20/, 'positive delta has + prefix');
}

# --- save_baseline / load_baseline ---

# Round-trip
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $metrics = [
        { name => 'JSEventListeners', value => 142 },
        { name => 'Nodes', value => 1523 },
    ];

    Bmux::Perf::save_baseline('before-fix', $metrics, $tmpdir);
    my $loaded = Bmux::Perf::load_baseline('before-fix', $tmpdir);

    is(scalar @$loaded, 2, 'round-trip count');
    is($loaded->[0]{name}, 'JSEventListeners', 'round-trip name');
    is($loaded->[0]{value}, 142, 'round-trip value');
}

# Creates perf/ subdir automatically
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    ok(! -d "$tmpdir/perf", 'perf dir does not exist yet');
    Bmux::Perf::save_baseline('test', [{ name => 'Nodes', value => 1 }], $tmpdir);
    ok(-d "$tmpdir/perf", 'perf dir created on save');
    ok(-f "$tmpdir/perf/test.json", 'baseline file created');
}

# Multiple named baselines coexist
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    Bmux::Perf::save_baseline('a', [{ name => 'Nodes', value => 10 }], $tmpdir);
    Bmux::Perf::save_baseline('b', [{ name => 'Nodes', value => 20 }], $tmpdir);
    is(Bmux::Perf::load_baseline('a', $tmpdir)->[0]{value}, 10, 'baseline a');
    is(Bmux::Perf::load_baseline('b', $tmpdir)->[0]{value}, 20, 'baseline b');
}

# Overwrite existing name
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    Bmux::Perf::save_baseline('x', [{ name => 'Nodes', value => 1 }], $tmpdir);
    Bmux::Perf::save_baseline('x', [{ name => 'Nodes', value => 99 }], $tmpdir);
    is(Bmux::Perf::load_baseline('x', $tmpdir)->[0]{value}, 99, 'overwrite baseline');
}

# Load nonexistent → undef
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $loaded = Bmux::Perf::load_baseline('nope', $tmpdir);
    is($loaded, undef, 'load missing returns undef');
}

# --- list_baselines ---

{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    Bmux::Perf::save_baseline('alpha', [{ name => 'Nodes', value => 1 }], $tmpdir);
    Bmux::Perf::save_baseline('beta',  [{ name => 'Nodes', value => 2 }], $tmpdir);
    my @names = Bmux::Perf::list_baselines($tmpdir);
    is_deeply([sort @names], ['alpha', 'beta'], 'list baselines');
}

# List with no perf dir → empty
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my @names = Bmux::Perf::list_baselines($tmpdir);
    is_deeply(\@names, [], 'list empty');
}

# --- delete_baseline ---

{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    Bmux::Perf::save_baseline('gone', [{ name => 'Nodes', value => 1 }], $tmpdir);
    ok(-f "$tmpdir/perf/gone.json", 'file exists before delete');
    Bmux::Perf::delete_baseline('gone', $tmpdir);
    ok(! -f "$tmpdir/perf/gone.json", 'file gone after delete');
}

done_testing;
