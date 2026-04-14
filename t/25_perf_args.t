#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Args;

# --- cdp verb ---

# cdp with method only
{
    my $r = Bmux::Args::parse(qw(cdp Performance.getMetrics));
    is($r->{verb}, 'cdp', 'cdp verb');
    is($r->{object}, 'Performance.getMetrics', 'cdp method as object');
}

# cdp with method + JSON params
{
    my $r = Bmux::Args::parse('cdp', 'Runtime.evaluate', '{"expression":"1+1"}');
    is($r->{verb}, 'cdp', 'cdp verb with params');
    is($r->{object}, 'Runtime.evaluate', 'cdp method');
    is($r->{value}, '{"expression":"1+1"}', 'cdp JSON params as value');
}

# cdp with target
{
    my $r = Bmux::Args::parse('cdp', 'edge:3', 'Performance.getMetrics');
    is($r->{verb}, 'cdp', 'cdp verb with target');
    is($r->{target}{session}, 'edge', 'cdp target session');
    is($r->{target}{tab}, 3, 'cdp target tab');
    is($r->{object}, 'Performance.getMetrics', 'cdp method after target');
}

# cdp with target + method + params
{
    my $r = Bmux::Args::parse('cdp', 'edge:3', 'Runtime.evaluate', '{"expression":"1+1"}');
    is($r->{verb}, 'cdp', 'cdp full form verb');
    is($r->{target}{session}, 'edge', 'cdp full form session');
    is($r->{target}{tab}, 3, 'cdp full form tab');
    is($r->{object}, 'Runtime.evaluate', 'cdp full form method');
    is($r->{value}, '{"expression":"1+1"}', 'cdp full form params');
}

# cdp with no args
{
    my $r = Bmux::Args::parse(qw(cdp));
    is($r->{verb}, 'cdp', 'bare cdp verb');
    is($r->{object}, undef, 'bare cdp no object');
}

# --- perf verb ---

# perf snapshot
{
    my $r = Bmux::Args::parse(qw(perf snapshot));
    is($r->{verb}, 'perf', 'perf snapshot verb');
    is($r->{action}, 'snapshot', 'perf snapshot action');
}

# perf listeners
{
    my $r = Bmux::Args::parse(qw(perf listeners));
    is($r->{verb}, 'perf', 'perf listeners verb');
    is($r->{action}, 'listeners', 'perf listeners action');
}

# perf heap
{
    my $r = Bmux::Args::parse(qw(perf heap));
    is($r->{verb}, 'perf', 'perf heap verb');
    is($r->{action}, 'heap', 'perf heap action');
}

# perf save <name>
{
    my $r = Bmux::Args::parse(qw(perf save before-fix));
    is($r->{verb}, 'perf', 'perf save verb');
    is($r->{action}, 'save', 'perf save action');
    is($r->{object}, 'before-fix', 'perf save name as object');
}

# perf list
{
    my $r = Bmux::Args::parse(qw(perf list));
    is($r->{verb}, 'perf', 'perf list verb');
    is($r->{action}, 'list', 'perf list action');
}

# perf delete <name>
{
    my $r = Bmux::Args::parse(qw(perf delete before-fix));
    is($r->{verb}, 'perf', 'perf delete verb');
    is($r->{action}, 'delete', 'perf delete action');
    is($r->{object}, 'before-fix', 'perf delete name as object');
}

# perf compare <name>
{
    my $r = Bmux::Args::parse(qw(perf compare before-fix));
    is($r->{verb}, 'perf', 'perf compare verb');
    is($r->{action}, 'compare', 'perf compare action');
    is($r->{object}, 'before-fix', 'perf compare name as object');
}

# perf compare <name1> <name2>
{
    my $r = Bmux::Args::parse(qw(perf compare before-fix after-nav));
    is($r->{verb}, 'perf', 'perf compare two names verb');
    is($r->{action}, 'compare', 'perf compare two names action');
    is($r->{object}, 'before-fix', 'perf compare first name');
    is($r->{value}, 'after-nav', 'perf compare second name as value');
}

# bare perf
{
    my $r = Bmux::Args::parse(qw(perf));
    is($r->{verb}, 'perf', 'bare perf verb');
    is($r->{action}, undef, 'bare perf no action');
}

done_testing;
