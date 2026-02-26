#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Args;

# Session management
{
    my $r = Bmux::Args::parse(qw(session new -s edge));
    is($r->{verb}, 'session', 'session verb');
    is($r->{action}, 'new', 'session action');
    is($r->{opts}{s}, 'edge', 'session name flag');
}

{
    my $r = Bmux::Args::parse(qw(session list));
    is($r->{verb}, 'session', 'session list verb');
    is($r->{action}, 'list', 'session list action');
}

{
    my $r = Bmux::Args::parse(qw(session kill edge));
    is($r->{verb}, 'session', 'session kill verb');
    is($r->{action}, 'kill', 'session kill action');
    is($r->{object}, 'edge', 'session kill target name');
}

# Attach / detach
{
    my $r = Bmux::Args::parse(qw(attach edge));
    is($r->{verb}, 'attach', 'attach verb');
    is($r->{target}{session}, 'edge', 'attach session');
    is($r->{target}{tab}, undef, 'attach no tab');
}

{
    my $r = Bmux::Args::parse(qw(attach edge:3));
    is($r->{verb}, 'attach', 'attach verb with tab');
    is($r->{target}{session}, 'edge', 'attach session');
    is($r->{target}{tab}, 3, 'attach tab');
}

{
    my $r = Bmux::Args::parse(qw(detach));
    is($r->{verb}, 'detach', 'detach verb');
}

# Tab management
{
    my $r = Bmux::Args::parse(qw(tab new));
    is($r->{verb}, 'tab', 'tab verb');
    is($r->{action}, 'new', 'tab new action');
}

{
    my $r = Bmux::Args::parse(qw(tab new edge));
    is($r->{verb}, 'tab', 'tab verb');
    is($r->{action}, 'new', 'tab new action');
    is($r->{target}{session}, 'edge', 'tab new with session');
}

{
    my $r = Bmux::Args::parse(qw(tab list));
    is($r->{verb}, 'tab', 'tab list');
    is($r->{action}, 'list', 'tab list action');
}

{
    my $r = Bmux::Args::parse(qw(tab select 3));
    is($r->{verb}, 'tab', 'tab select verb');
    is($r->{action}, 'select', 'tab select action');
    is($r->{object}, '3', 'tab select index');
}

{
    my $r = Bmux::Args::parse(qw(tab select edge:3));
    is($r->{verb}, 'tab', 'tab select verb');
    is($r->{action}, 'select', 'tab select action');
    is($r->{target}{session}, 'edge', 'tab select session');
    is($r->{target}{tab}, 3, 'tab select tab from target');
}

# Navigation
{
    my $r = Bmux::Args::parse('goto', 'https://example.com');
    is($r->{verb}, 'goto', 'goto verb');
    is($r->{object}, 'https://example.com', 'goto url');
}

{
    my $r = Bmux::Args::parse('goto', 'edge:3', 'https://example.com');
    is($r->{verb}, 'goto', 'goto with target');
    is($r->{target}{session}, 'edge', 'goto session');
    is($r->{target}{tab}, 3, 'goto tab');
    is($r->{object}, 'https://example.com', 'goto url after target');
}

{
    my $r = Bmux::Args::parse(qw(back));
    is($r->{verb}, 'back', 'back verb');
}

{
    my $r = Bmux::Args::parse(qw(forward));
    is($r->{verb}, 'forward', 'forward verb');
}

{
    my $r = Bmux::Args::parse(qw(reload));
    is($r->{verb}, 'reload', 'reload verb');
}

# Capture
{
    my $r = Bmux::Args::parse(qw(capture));
    is($r->{verb}, 'capture', 'bare capture');
    is($r->{object}, undef, 'no selector');
    ok(!$r->{opts}{p}, 'no -p');
}

{
    my $r = Bmux::Args::parse(qw(capture button -p));
    is($r->{verb}, 'capture', 'capture with selector');
    is($r->{object}, 'button', 'capture selector');
    ok($r->{opts}{p}, 'capture -p flag');
}

{
    my $r = Bmux::Args::parse('capture', 'edge:3', 'div.login');
    is($r->{verb}, 'capture', 'capture with target and selector');
    is($r->{target}{session}, 'edge', 'capture session');
    is($r->{target}{tab}, 3, 'capture tab');
    is($r->{object}, 'div.login', 'capture selector after target');
}

{
    my $r = Bmux::Args::parse(qw(capture -p));
    is($r->{verb}, 'capture', 'capture -p only');
    ok($r->{opts}{p}, 'capture -p');
    is($r->{object}, undef, 'no selector with -p only');
}

# Input
{
    my $r = Bmux::Args::parse('click', 'button#login');
    is($r->{verb}, 'click', 'click verb');
    is($r->{object}, 'button#login', 'click selector');
}

{
    my $r = Bmux::Args::parse('fill', 'input#email', 'scott@omatic.com');
    is($r->{verb}, 'fill', 'fill verb');
    is($r->{object}, 'input#email', 'fill selector');
    is($r->{value}, 'scott@omatic.com', 'fill value');
}

{
    my $r = Bmux::Args::parse('fill', 'edge:3', 'input#email', 'scott@omatic.com');
    is($r->{verb}, 'fill', 'fill with target');
    is($r->{target}{session}, 'edge', 'fill session');
    is($r->{object}, 'input#email', 'fill selector after target');
    is($r->{value}, 'scott@omatic.com', 'fill value after target');
}

{
    my $r = Bmux::Args::parse('type', 'input#search', 'hello world');
    is($r->{verb}, 'type', 'type verb');
    is($r->{object}, 'input#search', 'type selector');
    is($r->{value}, 'hello world', 'type value');
}

{
    my $r = Bmux::Args::parse('wait', 'div.loaded');
    is($r->{verb}, 'wait', 'wait verb');
    is($r->{object}, 'div.loaded', 'wait selector');
}

# Eval
{
    my $r = Bmux::Args::parse('eval', 'localStorage');
    is($r->{verb}, 'eval', 'eval verb');
    is($r->{object}, 'localStorage', 'eval expression');
}

{
    my $r = Bmux::Args::parse('eval', 'edge:3', 'document.title');
    is($r->{verb}, 'eval', 'eval with target');
    is($r->{target}{session}, 'edge', 'eval session');
    is($r->{object}, 'document.title', 'eval expression after target');
}

# Debugging nouns
{
    my $r = Bmux::Args::parse(qw(storage));
    is($r->{verb}, 'storage', 'storage noun');
    ok(!$r->{opts}{session}, 'no --session');
}

{
    my $r = Bmux::Args::parse(qw(storage --session));
    is($r->{verb}, 'storage', 'storage with --session');
    ok($r->{opts}{session}, 'storage --session flag');
}

{
    my $r = Bmux::Args::parse(qw(cookies));
    is($r->{verb}, 'cookies', 'cookies noun');
}

{
    my $r = Bmux::Args::parse(qw(cookies edge));
    is($r->{verb}, 'cookies', 'cookies with session');
    is($r->{target}{session}, 'edge', 'cookies session target');
}

{
    my $r = Bmux::Args::parse(qw(console --follow));
    is($r->{verb}, 'console', 'console noun');
    ok($r->{opts}{follow}, 'console --follow');
}

{
    my $r = Bmux::Args::parse('network', 'edge:3', '*/api/*', '--follow');
    is($r->{verb}, 'network', 'network with all parts');
    is($r->{target}{session}, 'edge', 'network session');
    is($r->{target}{tab}, 3, 'network tab');
    is($r->{object}, '*/api/*', 'network filter');
    ok($r->{opts}{follow}, 'network --follow');
}

{
    my $r = Bmux::Args::parse('style', 'div.header', 'color');
    is($r->{verb}, 'style', 'style noun');
    is($r->{object}, 'div.header', 'style selector');
    is($r->{value}, 'color', 'style property');
}

{
    my $r = Bmux::Args::parse('style', 'div.header', '--matched');
    is($r->{verb}, 'style', 'style matched');
    is($r->{object}, 'div.header', 'style selector');
    ok($r->{opts}{matched}, 'style --matched');
}

{
    my $r = Bmux::Args::parse(qw(screenshot));
    is($r->{verb}, 'screenshot', 'screenshot noun');
}

# Target disambiguation — a word with : is a target, URLs are objects
{
    my $r = Bmux::Args::parse('goto', 'https://example.com:8080/path');
    is($r->{verb}, 'goto', 'url with port not confused with target');
    is($r->{object}, 'https://example.com:8080/path', 'url preserved as object');
    is($r->{target}, undef, 'no target from url');
}

done_testing;
