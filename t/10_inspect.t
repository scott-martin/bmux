#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Inspect;
use Bmux::CDP;

# storage — builds Runtime.evaluate with localStorage enumeration
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_storage($cdp, 'localStorage');
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.evaluate', 'storage method');
    like($msg->{params}{expression}, qr/localStorage/, 'storage expression');
}

# storage --session uses sessionStorage
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_storage($cdp, 'sessionStorage');
    my $msg = decode_json($json);

    like($msg->{params}{expression}, qr/sessionStorage/, 'sessionStorage expression');
}

# cookies — builds Network.getCookies
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_cookies($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Network.getCookies', 'cookies method');
}

# style — builds CSS.getComputedStyleForNode
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_computed_style($cdp, 42);
    my $msg = decode_json($json);

    is($msg->{method}, 'CSS.getComputedStyleForNode', 'computed style method');
    is($msg->{params}{nodeId}, 42, 'computed style nodeId');
}

# style --matched builds CSS.getMatchedStylesForNode
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_matched_styles($cdp, 42);
    my $msg = decode_json($json);

    is($msg->{method}, 'CSS.getMatchedStylesForNode', 'matched styles method');
    is($msg->{params}{nodeId}, 42, 'matched styles nodeId');
}

# scripts — builds Page.getResourceTree
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_resource_tree($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Page.getResourceTree', 'resource tree method');
}

# console — builds Runtime.enable
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_enable_runtime($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.enable', 'runtime enable method');
}

# network — builds Network.enable
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Inspect::cmd_enable_network($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'Network.enable', 'network enable method');
}

# Format computed style for display
{
    my $styles = [
        { name => 'color', value => 'rgb(0, 0, 0)' },
        { name => 'font-size', value => '16px' },
        { name => 'display', value => 'block' },
    ];

    my $output = Bmux::Inspect::format_computed_style($styles);
    like($output, qr/color:\s*rgb\(0, 0, 0\)/, 'format has color');
    like($output, qr/font-size:\s*16px/, 'format has font-size');
}

# Filter computed style by property name
{
    my $styles = [
        { name => 'color', value => 'red' },
        { name => 'font-size', value => '16px' },
    ];

    my $output = Bmux::Inspect::format_computed_style($styles, 'color');
    like($output, qr/red/, 'filtered has color value');
    unlike($output, qr/font-size/, 'filtered excludes font-size');
}

# Format cookie list
{
    my $cookies = [
        { name => 'session', value => 'abc123', domain => '.example.com' },
        { name => 'pref', value => 'dark', domain => '.example.com' },
    ];
    my $output = Bmux::Inspect::format_cookies($cookies);
    like($output, qr/session=abc123/, 'format cookie name=value');
    like($output, qr/\.example\.com/, 'format cookie domain');
}

done_testing;
