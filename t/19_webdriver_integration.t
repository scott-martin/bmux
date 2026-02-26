#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Session;
use Bmux::Browser;

# --- Session.pm: type field ---

{
    my $dir = tempdir(CLEANUP => 1);
    my $sess = Bmux::Session->new(state_dir => $dir);
    
    # Save CDP session (existing style, with type)
    $sess->save_session('edge', {
        type => 'cdp',
        port => 9222,
        pid  => 1234,
        bin  => '/path/to/edge',
    });
    
    my $sessions = $sess->load_sessions();
    is($sessions->{edge}{type}, 'cdp', 'CDP session has type field');
    is($sessions->{edge}{port}, 9222, 'CDP session has port');
}

{
    my $dir = tempdir(CLEANUP => 1);
    my $sess = Bmux::Session->new(state_dir => $dir);
    
    # Save WebDriver session (new style)
    $sess->save_session('safari', {
        type       => 'webdriver',
        port       => 4444,
        pid        => 5678,
        session_id => 'wd-session-abc123',
    });
    
    my $sessions = $sess->load_sessions();
    is($sessions->{safari}{type}, 'webdriver', 'WebDriver session has type field');
    is($sessions->{safari}{port}, 4444, 'WebDriver session has port');
    is($sessions->{safari}{session_id}, 'wd-session-abc123', 'WebDriver session has session_id');
}

# --- Session type helpers ---

{
    ok(Bmux::Session::is_cdp_session({ type => 'cdp' }), 'is_cdp_session true for cdp');
    ok(!Bmux::Session::is_cdp_session({ type => 'webdriver' }), 'is_cdp_session false for webdriver');
    ok(Bmux::Session::is_cdp_session({ port => 9222 }), 'is_cdp_session true when no type (legacy)');
}

{
    ok(Bmux::Session::is_webdriver_session({ type => 'webdriver' }), 'is_webdriver_session true for webdriver');
    ok(!Bmux::Session::is_webdriver_session({ type => 'cdp' }), 'is_webdriver_session false for cdp');
    ok(!Bmux::Session::is_webdriver_session({ port => 9222 }), 'is_webdriver_session false when no type');
}

# --- Browser.pm: Safari support ---

{
    my $bin = Bmux::Browser::find_safari();
    is($bin, 'safaridriver', 'find_safari returns safaridriver');
}

{
    my $bin = Bmux::Browser::find_by_name('safari');
    is($bin, 'safaridriver', 'find_by_name(safari) works');
}

# --- Browser type detection ---

{
    ok(Bmux::Browser::is_webdriver_browser('safari'), 'safari is webdriver browser');
    ok(!Bmux::Browser::is_webdriver_browser('chrome'), 'chrome is not webdriver browser');
    ok(!Bmux::Browser::is_webdriver_browser('edge'), 'edge is not webdriver browser');
    ok(!Bmux::Browser::is_webdriver_browser('brave'), 'brave is not webdriver browser');
}

{
    ok(Bmux::Browser::is_cdp_browser('chrome'), 'chrome is cdp browser');
    ok(Bmux::Browser::is_cdp_browser('edge'), 'edge is cdp browser');
    ok(Bmux::Browser::is_cdp_browser('brave'), 'brave is cdp browser');
    ok(!Bmux::Browser::is_cdp_browser('safari'), 'safari is not cdp browser');
}

# --- Multiple sessions of different types ---

{
    my $dir = tempdir(CLEANUP => 1);
    my $sess = Bmux::Session->new(state_dir => $dir);
    
    $sess->save_session('chrome', {
        type => 'cdp',
        port => 9222,
        pid  => 1000,
    });
    
    $sess->save_session('safari', {
        type       => 'webdriver',
        port       => 4444,
        pid        => 2000,
        session_id => 'safari-sess',
    });
    
    my $sessions = $sess->load_sessions();
    
    is(scalar keys %$sessions, 2, 'two sessions stored');
    is($sessions->{chrome}{type}, 'cdp', 'chrome is cdp');
    is($sessions->{safari}{type}, 'webdriver', 'safari is webdriver');
    
    ok(Bmux::Session::is_cdp_session($sessions->{chrome}), 'chrome session detected as cdp');
    ok(Bmux::Session::is_webdriver_session($sessions->{safari}), 'safari session detected as webdriver');
}

done_testing;
