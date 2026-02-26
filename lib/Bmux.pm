package Bmux;
use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP;
use Bmux::Args;
use Bmux::Session;
use Bmux::Tab;
use Bmux::CDP;
use Bmux::Navigate;
use Bmux::Capture;
use Bmux::Input;
use Bmux::Eval;
use Bmux::Browser;

my $session_mgr = Bmux::Session->new();

sub run {
    my ($class, @argv) = @_;
    die "Usage: bmux <command> [args...]\n" unless @argv;

    my $parsed = Bmux::Args::parse(@argv);
    my $verb = $parsed->{verb} // die "No command given\n";

    # Session management (no CDP needed)
    return _cmd_session($parsed)  if $verb eq 'session';
    return _cmd_attach($parsed)   if $verb eq 'attach';
    return _cmd_detach()          if $verb eq 'detach';
    return _cmd_tab($parsed)      if $verb eq 'tab';

    # Everything else needs CDP
    my $cdp = _connect($parsed);

    if    ($verb eq 'goto')    { _cmd_goto($cdp, $parsed) }
    elsif ($verb eq 'back')    { $cdp->send_command('Runtime.evaluate', { expression => 'history.back()' }) }
    elsif ($verb eq 'forward') { $cdp->send_command('Runtime.evaluate', { expression => 'history.forward()' }) }
    elsif ($verb eq 'reload')  { $cdp->send_command('Page.reload'); print "Reloaded.\n" }
    elsif ($verb eq 'capture') { _cmd_capture($cdp, $parsed) }
    elsif ($verb eq 'click')   { Bmux::Input::run_click($cdp, $parsed) }
    elsif ($verb eq 'fill')    { Bmux::Input::run_fill($cdp, $parsed) }
    elsif ($verb eq 'type')    { Bmux::Input::run_type($cdp, $parsed) }
    elsif ($verb eq 'wait')    { Bmux::Input::run_wait($cdp, $parsed) }
    elsif ($verb eq 'eval')    { _cmd_eval($cdp, $parsed) }
    elsif ($verb eq 'storage') { _cmd_storage($cdp, $parsed) }
    elsif ($verb eq 'cookies') { _cmd_cookies($cdp) }
    else { die "Unknown command: $verb\n" }

    $cdp->close();
}

sub _cmd_session {
    my ($parsed) = @_;
    my $action = $parsed->{action} // die "Usage: bmux session <new|list|kill>\n";

    if ($action eq 'list') {
        my $sessions = $session_mgr->load_sessions();
        if (!%$sessions) { print "No sessions.\n"; return }
        for my $name (sort keys %$sessions) {
            my $s = $sessions->{$name};
            printf "%s  port=%d  pid=%d  bin=%s\n", $name, $s->{port}, $s->{pid}, $s->{bin};
        }
    } elsif ($action eq 'new') {
        my $name = $parsed->{opts}{s} // die "Usage: bmux session new -s <name>\n";
        _launch_session($name);
    } elsif ($action eq 'kill') {
        my $name = $parsed->{object} // die "Usage: bmux session kill <name>\n";
        my $sessions = $session_mgr->load_sessions();
        my $s = $sessions->{$name} // die "No session named '$name'\n";
        kill('TERM', $s->{pid}) if $s->{pid};
        $session_mgr->remove_session($name);
        print "Killed session '$name'.\n";
    }
}

sub _launch_session {
    my ($name) = @_;
    my $bin = Bmux::Browser::find_by_name($name);
    die "Browser not found: $bin\n" unless -f $bin;

    my $sessions = $session_mgr->load_sessions();
    my %used = map { $_->{port} => 1 } values %$sessions;
    my $port = 9222;
    $port++ while $used{$port};

    my $pid = Bmux::Browser::spawn($bin,
        "--remote-debugging-port=$port",
        "--user-data-dir=" . Bmux::Browser::temp_profile($name),
    );

    $session_mgr->save_session($name, { port => $port, pid => $pid, bin => $bin });

    my $ready = 0;
    for (1..20) {
        sleep 1;
        eval {
            my $r = HTTP::Tiny->new(timeout => 2)->get("http://localhost:$port/json/version");
            $ready = 1 if $r->{success};
        };
        last if $ready;
    }
    die "Browser did not start on port $port\n" unless $ready;
    print "Session '$name' started on port $port (pid $pid).\n";
}

sub _cmd_attach {
    my ($parsed) = @_;
    my $t = $parsed->{target} // die "Usage: bmux attach <session[:tab]>\n";
    my $str = defined $t->{tab} ? "$t->{session}:$t->{tab}" : $t->{session};
    $session_mgr->save_attached($str);
    print "Attached to $str.\n";
}

sub _cmd_detach {
    $session_mgr->clear_attached();
    print "Detached.\n";
}

sub _cmd_tab {
    my ($parsed) = @_;
    my $action = $parsed->{action} // die "Usage: bmux tab <new|list|select|kill>\n";
    my $port = _resolve_port($parsed);

    if ($action eq 'list') {
        my $r = HTTP::Tiny->new(timeout => 5)->get("http://localhost:$port/json");
        die "Cannot connect to browser on port $port\n" unless $r->{success};
        my @tabs = Bmux::Tab::parse_tab_list($r->{content});
        print Bmux::Tab::format_tab_list(\@tabs) . "\n";
    } elsif ($action eq 'new') {
        HTTP::Tiny->new(timeout => 5)->put("http://localhost:$port/json/new");
        print "New tab opened.\n";
    } elsif ($action eq 'kill') {
        my $idx = $parsed->{object} // $parsed->{target}{tab}
            // die "Usage: bmux tab kill <index>\n";
        my $r = HTTP::Tiny->new(timeout => 5)->get("http://localhost:$port/json");
        die "Cannot connect to browser on port $port\n" unless $r->{success};
        my @tabs = Bmux::Tab::parse_tab_list($r->{content});
        my $tab = Bmux::Tab::find_by_index(\@tabs, $idx)
            // die "Tab $idx not found (" . scalar(@tabs) . " tabs)\n";
        my $cdp = Bmux::CDP->connect($tab->{ws_url});
        Bmux::Tab::close_target($cdp, $tab->{id});
        $cdp->close();
        print "Closed tab $idx.\n";
    } elsif ($action eq 'select') {
        my $idx = $parsed->{object} // $parsed->{target}{tab}
            // die "Usage: bmux tab select <index>\n";
        my $sess = _attached_session() // die "Not attached. Run: bmux attach <session>\n";
        $session_mgr->save_attached("$sess:$idx");
        print "Selected tab $idx.\n";
    }
}

sub _cmd_goto {
    my ($cdp, $parsed) = @_;
    my $url = $parsed->{object} // die "Usage: bmux goto <url>\n";
    $cdp->send_command('Page.navigate', { url => $url });
    print "Navigated to $url\n";
}

sub _cmd_capture {
    my ($cdp, $parsed) = @_;
    my $selector = $parsed->{object};
    my $text_only = $parsed->{opts}{p};

    my $doc = $cdp->send_command('DOM.getDocument');
    my $root_id = $doc->{root}{nodeId};
    my $html;

    if ($selector) {
        my @node_ids;
        if (Bmux::Capture::is_xpath($selector)) {
            my $s = $cdp->send_command('DOM.performSearch', { query => $selector });
            my $count = $s->{resultCount} // 0;
            if ($count == 0) { print "No matches for: $selector\n"; return }
            my $r = $cdp->send_command('DOM.getSearchResults', {
                searchId => $s->{searchId}, fromIndex => 0, toIndex => $count,
            });
            @node_ids = @{$r->{nodeIds} // []};
        } else {
            my $r = $cdp->send_command('DOM.querySelectorAll', {
                nodeId => $root_id, selector => $selector,
            });
            @node_ids = @{$r->{nodeIds} // []};
        }
        if (!@node_ids) { print "No matches for: $selector\n"; return }
        $html = join("\n", map {
            my $r = $cdp->send_command('DOM.getOuterHTML', { nodeId => $_ });
            $r->{outerHTML} // '';
        } @node_ids);
    } else {
        my $r = $cdp->send_command('DOM.getOuterHTML', { nodeId => $root_id });
        $html = $r->{outerHTML} // '';
    }

    print $text_only ? Bmux::Capture::strip_html($html) . "\n" : "$html\n";
}

sub _cmd_eval {
    my ($cdp, $parsed) = @_;
    my $expr = $parsed->{object} // die "Usage: bmux eval <expression>\n";
    my $result = $cdp->send_command('Runtime.evaluate', {
        expression => $expr, returnByValue => JSON::PP::true,
    });
    print Bmux::Eval::format_result($result) . "\n";
}

sub _cmd_storage {
    my ($cdp, $parsed) = @_;
    my $which = $parsed->{opts}{session} ? 'sessionStorage' : 'localStorage';
    my $r = $cdp->send_command('Runtime.evaluate', {
        expression => "JSON.stringify($which)", returnByValue => JSON::PP::true,
    });
    print $r->{result}{value} // '{}', "\n";
}

sub _cmd_cookies {
    my ($cdp) = @_;
    my $r = $cdp->send_command('Network.getCookies');
    print encode_json($r->{cookies} // []) . "\n";
}

# --- Connection helpers ---

sub _connect {
    my ($parsed) = @_;
    my $port = _resolve_port($parsed);
    my $tab_idx = _resolve_tab($parsed);

    my $r = HTTP::Tiny->new(timeout => 5)->get("http://localhost:$port/json");
    die "Cannot connect to browser on port $port\n" unless $r->{success};

    my @tabs = Bmux::Tab::parse_tab_list($r->{content});
    die "No tabs found\n" unless @tabs;

    my $tab = defined $tab_idx
        ? (Bmux::Tab::find_by_index(\@tabs, $tab_idx)
           // die "Tab $tab_idx not found (" . scalar(@tabs) . " tabs)\n")
        : $tabs[0];

    my $cdp = Bmux::CDP->connect($tab->{ws_url});
    $cdp->{target_id} = $tab->{id};
    return $cdp;
}

sub _resolve_port {
    my ($parsed) = @_;
    my $name = ($parsed->{target} && $parsed->{target}{session})
        // _attached_session()
        // die "Not attached. Run: bmux attach <session>\n";
    my $s = $session_mgr->load_sessions()->{$name}
        // die "No session named '$name'\n";
    return $s->{port};
}

sub _resolve_tab {
    my ($parsed) = @_;
    return $parsed->{target}{tab} if $parsed->{target} && defined $parsed->{target}{tab};
    my $a = $session_mgr->load_attached() // return undef;
    my ($tab) = $a =~ /:(\d+)$/;
    return $tab;
}

sub _attached_session {
    my $a = $session_mgr->load_attached() // return undef;
    my ($s) = $a =~ /^(\w+)/;
    return $s;
}

1;
