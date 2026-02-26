#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Capture;
use Bmux::CDP;

# Full DOM capture — builds DOM.getDocument
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Capture::cmd_get_document($cdp);
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.getDocument', 'get_document method');
}

# Get outer HTML of a node
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Capture::cmd_get_outer_html($cdp, 42);
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.getOuterHTML', 'get_outer_html method');
    is($msg->{params}{nodeId}, 42, 'get_outer_html nodeId');
}

# CSS selector query
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Capture::cmd_query_selector($cdp, 1, 'button.login');
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.querySelector', 'querySelector method');
    is($msg->{params}{nodeId}, 1, 'querySelector nodeId');
    is($msg->{params}{selector}, 'button.login', 'querySelector selector');
}

# Query selector all
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Capture::cmd_query_selector_all($cdp, 1, 'button');
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.querySelectorAll', 'querySelectorAll method');
    is($msg->{params}{selector}, 'button', 'querySelectorAll selector');
}

# XPath detection
{
    ok(Bmux::Capture::is_xpath('//button'), '// is xpath');
    ok(Bmux::Capture::is_xpath('/html/body'), '/ is xpath');
    ok(!Bmux::Capture::is_xpath('button'), 'bare word is not xpath');
    ok(!Bmux::Capture::is_xpath('div.class'), 'css selector is not xpath');
    ok(!Bmux::Capture::is_xpath('#id'), 'id selector is not xpath');
}

# XPath search
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Capture::cmd_perform_search($cdp, '//button[@class="login"]');
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.performSearch', 'performSearch method');
    is($msg->{params}{query}, '//button[@class="login"]', 'performSearch query');
}

# Strip HTML tags (-p flag)
{
    is(Bmux::Capture::strip_html('<p>Hello <b>world</b></p>'),
        'Hello world', 'strip simple tags');

    is(Bmux::Capture::strip_html('<div class="foo">text</div>'),
        'text', 'strip tags with attributes');

    is(Bmux::Capture::strip_html('no tags here'),
        'no tags here', 'no tags unchanged');

    is(Bmux::Capture::strip_html('<br/><br/>line1<br/>line2'),
        'line1line2', 'strip self-closing tags');

    is(Bmux::Capture::strip_html(''), '', 'empty string');
}

# Collapse whitespace in stripped text
{
    my $html = "<div>\n  <p>  hello  </p>\n  <p>  world  </p>\n</div>";
    my $text = Bmux::Capture::strip_html($html);
    like($text, qr/hello/, 'stripped has hello');
    like($text, qr/world/, 'stripped has world');
}

done_testing;
