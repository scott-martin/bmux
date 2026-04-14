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
use Bmux::Perf;
use Bmux::Browser;
use Bmux::WebDriver::Client;
use Bmux::WebDriver::Session;
use Bmux::WebDriver::Navigate;
use Bmux::WebDriver::Element;
use Bmux::WebDriver::Input;
use Bmux::WebDriver::Capture;
use Bmux::WebDriver::Eval;
use Bmux::WebDriver::Inspect;

my $session_mgr = Bmux::Session->new();

sub run {
    my ($class, @argv) = @_;
    die "Usage: bmux <command> [args...]\n" unless @argv;

    my $parsed = Bmux::Args::parse(@argv);
    my $verb = $parsed->{verb} // die "No command given\n";

    # Session management (no protocol needed)
    return _cmd_session($parsed)  if $verb eq 'session';
    return _cmd_attach($parsed)   if $verb eq 'attach';
    return _cmd_detach()          if $verb eq 'detach';
    return _cmd_tab($parsed)      if $verb eq 'tab';

    # Determine protocol based on session type
    my $session = _resolve_session($parsed);
    
    if (Bmux::Session::is_webdriver_session($session)) {
        _dispatch_webdriver($verb, $parsed, $session);
    } else {
        _dispatch_cdp($verb, $parsed, $session);
    }
}

sub _cmd_session {
    my ($parsed) = @_;
    my $action = $parsed->{action} // die "Usage: bmux session <new|list|kill>\n";

    if ($action eq 'list') {
        my $sessions = $session_mgr->load_sessions();
        if (!%$sessions) { print "No sessions.\n"; return }
        for my $name (sort keys %$sessions) {
            my $s = $sessions->{$name};
            my $type = $s->{type} // 'cdp';
            if ($type eq 'webdriver') {
                printf "%s  type=%s  port=%d  pid=%d  session=%s\n",
                    $name, $type, $s->{port}, $s->{pid}, $s->{session_id} // 'none';
            } else {
                printf "%s  type=%s  port=%d  pid=%d  bin=%s\n",
                    $name, $type, $s->{port}, $s->{pid}, $s->{bin} // 'unknown';
            }
        }
    } elsif ($action eq 'new') {
        my $name = $parsed->{opts}{s} // die "Usage: bmux session new -s <name>\n";
        _launch_session($name);
    } elsif ($action eq 'kill') {
        my $name = $parsed->{object} // die "Usage: bmux session kill <name>\n";
        my $sessions = $session_mgr->load_sessions();
        my $s = $sessions->{$name} // die "No session named '$name'\n";
        
        # For WebDriver sessions, delete the session first
        if (Bmux::Session::is_webdriver_session($s) && $s->{session_id}) {
            eval {
                my $client = Bmux::WebDriver::Client->new("http://localhost:$s->{port}", $s->{session_id});
                $client->delete("/session/$s->{session_id}");
            };
        }
        
        kill('TERM', $s->{pid}) if $s->{pid};
        $session_mgr->remove_session($name);
        print "Killed session '$name'.\n";
    }
}

sub _launch_session {
    my ($name) = @_;
    
    if (Bmux::Browser::is_webdriver_browser($name)) {
        _launch_webdriver_session($name);
    } else {
        _launch_cdp_session($name);
    }
}

sub _launch_cdp_session {
    my ($name) = @_;
    my $bin = Bmux::Browser::find_by_name($name);
    die "Browser not found: $bin\n" unless -f $bin;

    # Remove sessions with dead PIDs (e.g. after reboot)
    my $pruned = $session_mgr->prune_stale();
    print "Pruned $pruned stale session(s).\n" if $pruned;

    my $sessions = $session_mgr->load_sessions();
    my %used = map { $_->{port} => 1 } values %$sessions;
    my $port = 9222;
    $port++ while $used{$port};

    my @launch_args = ("--remote-debugging-port=$port");
    # On WSL we kill existing Edge first, so we can use the default profile.
    # This lets links from other apps open in the bmux-controlled window.
    # On other platforms, use an isolated profile to avoid conflicts.
    push @launch_args, "--user-data-dir=" . Bmux::Browser::temp_profile($name)
        unless Bmux::Browser::is_wsl();

    my $pid = Bmux::Browser::spawn($bin, @launch_args);

    $session_mgr->save_session($name, { type => 'cdp', port => $port, pid => $pid, bin => $bin });

    # On WSL, ensure the portproxy/firewall bridge is working
    Bmux::Browser::ensure_cdp_bridge($port);

    my $cport = Bmux::Browser::cdp_port($port);
    my $ready = 0;
    for (1..20) {
        sleep 1;
        eval {
            my $r = HTTP::Tiny->new(timeout => 2)->get("http://${\Bmux::Browser::cdp_host()}:$cport/json/version");
            $ready = 1 if $r->{success};
        };
        last if $ready;
    }
    die "Browser did not start on port $port\n" unless $ready;
    print "Session '$name' started on port $port (pid $pid).\n";
}

sub _launch_webdriver_session {
    my ($name) = @_;
    
    my $sessions = $session_mgr->load_sessions();
    my %used = map { $_->{port} => 1 } values %$sessions;
    my $port = 4444;
    $port++ while $used{$port};
    
    # Start safaridriver
    my @cmd = Bmux::WebDriver::Session::driver_command($port);
    my $pid = fork();
    die "Fork failed: $!\n" unless defined $pid;
    
    if ($pid == 0) {
        # Child: run safaridriver
        require POSIX;
        POSIX::setsid();
        open STDIN,  '</dev/null';
        open STDOUT, '>/dev/null';
        open STDERR, '>/dev/null';
        exec(@cmd) or die "Cannot exec safaridriver: $!\n";
    }
    
    # Wait for safaridriver to be ready
    my $ready = 0;
    for (1..20) {
        sleep 1;
        eval {
            my $r = HTTP::Tiny->new(timeout => 2)->get("http://localhost:$port/status");
            if ($r->{success}) {
                my $status = decode_json($r->{content});
                $ready = 1 if $status->{value}{ready};
            }
        };
        last if $ready;
    }
    die "safaridriver did not start on port $port\n" unless $ready;
    
    # Create WebDriver session (this launches Safari)
    my $client = Bmux::WebDriver::Client->new("http://localhost:$port");
    my $caps = Bmux::WebDriver::Session::session_capabilities();
    my $response = $client->post('/session', $caps);
    my $session_id = $response->{sessionId} // die "Failed to create WebDriver session\n";
    
    $session_mgr->save_session($name, {
        type       => 'webdriver',
        port       => $port,
        pid        => $pid,
        session_id => $session_id,
    });
    
    print "Session '$name' started on port $port (pid $pid, session $session_id).\n";
}

sub _cmd_attach {
    my ($parsed) = @_;
    my $t = $parsed->{target} // die "Usage: bmux attach <session[:tab]>\n";

    if (defined $t->{tab}) {
        # Resolve index to a stable target ID
        my $port = _resolve_port($parsed);
        my $r = HTTP::Tiny->new(timeout => 5)
            ->get("http://${\Bmux::Browser::cdp_host()}:$port/json");
        die "Cannot connect to browser on port $port\n" unless $r->{success};
        my @tabs = Bmux::Tab::parse_tab_list($r->{content});
        my $tab = Bmux::Tab::find_by_index(\@tabs, $t->{tab})
            // die "Tab $t->{tab} not found (" . scalar(@tabs) . " tabs)\n";
        my $str = "$t->{session}=$tab->{id}";
        $session_mgr->save_attached($str);
        print "Attached to $t->{session}:$t->{tab} ($tab->{title})\n";
    } else {
        $session_mgr->save_attached($t->{session});
        print "Attached to $t->{session}.\n";
    }
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
        my $r = HTTP::Tiny->new(timeout => 5)->get("http://${\Bmux::Browser::cdp_host()}:$port/json");
        die "Cannot connect to browser on port $port\n" unless $r->{success};
        my @tabs = Bmux::Tab::parse_tab_list($r->{content});
        print Bmux::Tab::format_tab_list(\@tabs) . "\n";
    } elsif ($action eq 'new') {
        HTTP::Tiny->new(timeout => 5)->put("http://${\Bmux::Browser::cdp_host()}:$port/json/new");
        print "New tab opened.\n";
    } elsif ($action eq 'kill') {
        my $idx = $parsed->{object} // $parsed->{target}{tab}
            // die "Usage: bmux tab kill <index>\n";
        my $r = HTTP::Tiny->new(timeout => 5)->get("http://${\Bmux::Browser::cdp_host()}:$port/json");
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
        my $r = HTTP::Tiny->new(timeout => 5)->get("http://${\Bmux::Browser::cdp_host()}:$port/json");
        die "Cannot connect to browser on port $port\n" unless $r->{success};
        my @tabs = Bmux::Tab::parse_tab_list($r->{content});
        my $tab = Bmux::Tab::find_by_index(\@tabs, $idx)
            // die "Tab $idx not found (" . scalar(@tabs) . " tabs)\n";
        $session_mgr->save_attached("$sess=$tab->{id}");
        print "Selected tab $idx ($tab->{title})\n";
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

sub _cmd_cdp {
    my ($cdp, $parsed) = @_;
    my $method = $parsed->{object} // die "Usage: bmux cdp <method> [json-params]\n";
    my $params;
    if (defined $parsed->{value}) {
        $params = eval { decode_json($parsed->{value}) };
        die "Invalid JSON params: $@\n" if $@;
    }
    my $result = $cdp->send_command($method, $params);
    print encode_json($result) . "\n";
}

sub _perf_get_metrics {
    my ($cdp) = @_;
    $cdp->send_command('Performance.enable');
    my $m = $cdp->send_command('Performance.getMetrics');
    return $m->{metrics};
}

sub _cmd_perf {
    my ($cdp, $parsed) = @_;
    my $action = $parsed->{action}
        // die "Usage: bmux perf <snapshot|listeners|heap|save|list|delete|compare>\n";

    if ($action eq 'snapshot') {
        print Bmux::Perf::format_snapshot(_perf_get_metrics($cdp));
    }
    elsif ($action eq 'listeners') {
        my $count = Bmux::Perf::extract_metric(_perf_get_metrics($cdp), 'JSEventListeners');
        print "JSEventListeners: $count\n";
    }
    elsif ($action eq 'heap') {
        my $used = Bmux::Perf::extract_metric(_perf_get_metrics($cdp), 'JSHeapUsedSize');
        print "JSHeapUsedSize: " . Bmux::Perf::format_bytes($used) . "\n";
    }
    elsif ($action eq 'save') {
        my $name = $parsed->{object} // die "Usage: bmux perf save <name>\n";
        Bmux::Perf::save_baseline($name, _perf_get_metrics($cdp));
        print "Saved ./perf/$name.json\n";
    }
    elsif ($action eq 'list') {
        my @names = Bmux::Perf::list_baselines();
        if (@names) { print "$_\n" for @names }
        else        { print "No baselines in ./perf/\n" }
    }
    elsif ($action eq 'delete') {
        my $name = $parsed->{object} // die "Usage: bmux perf delete <name>\n";
        Bmux::Perf::delete_baseline($name);
        print "Deleted ./perf/$name.json\n";
    }
    elsif ($action eq 'compare') {
        my $name1 = $parsed->{object} // die "Usage: bmux perf compare <name> [name2]\n";
        my $name2 = $parsed->{value};

        my $before = Bmux::Perf::load_baseline($name1)
            // die "No baseline '$name1'. Run: bmux perf save $name1\n";

        my $after;
        if ($name2) {
            $after = Bmux::Perf::load_baseline($name2)
                // die "No baseline '$name2'.\n";
        } else {
            $after = _perf_get_metrics($cdp);
        }

        print Bmux::Perf::format_diff(Bmux::Perf::diff_metrics($before, $after));
    }
    else {
        die "Unknown perf action: $action\n"
          . "Usage: bmux perf <snapshot|listeners|heap|save|list|delete|compare>\n";
    }
}

# --- Connection helpers ---

sub _connect {
    my ($parsed) = @_;
    my $port = _resolve_port($parsed);
    my $tab_ref = _resolve_tab($parsed);

    my $r = HTTP::Tiny->new(timeout => 5)->get("http://${\Bmux::Browser::cdp_host()}:$port/json");
    die "Cannot connect to browser on port $port\n" unless $r->{success};

    my @tabs = Bmux::Tab::parse_tab_list($r->{content});
    die "No tabs found\n" unless @tabs;

    my $tab;
    if (!defined $tab_ref) {
        $tab = $tabs[0];
    } elsif ($tab_ref->{type} eq 'id') {
        $tab = Bmux::Tab::find_by_id(\@tabs, $tab_ref->{value})
            // die "Tab with target ID $tab_ref->{value} not found (closed?)\n";
    } else {
        $tab = Bmux::Tab::find_by_index(\@tabs, $tab_ref->{value})
            // die "Tab $tab_ref->{value} not found (" . scalar(@tabs) . " tabs)\n";
    }

    my $cdp = Bmux::CDP->connect($tab->{ws_url});
    $cdp->{target_id} = $tab->{id};
    # Bring browser to foreground — Chrome throttles background tabs
    $cdp->send_command('Target.activateTarget', { targetId => $tab->{id} });
    select(undef, undef, undef, 0.1);
    return $cdp;
}

sub _resolve_port {
    my ($parsed) = @_;
    my $name = ($parsed->{target} && $parsed->{target}{session})
        // _attached_session()
        // die "Not attached. Run: bmux attach <session>\n";
    my $s = $session_mgr->load_sessions()->{$name}
        // die "No session named '$name'\n";
    return Bmux::Browser::cdp_port($s->{port});
}

# Returns { type => 'id', value => 'TARGETID' } or { type => 'index', value => N } or undef.
sub _resolve_tab {
    my ($parsed) = @_;
    # Explicit target on command line (e.g. edge:3) — resolve index to ID now
    if ($parsed->{target} && defined $parsed->{target}{tab}) {
        return { type => 'index', value => $parsed->{target}{tab} };
    }
    # Stored attachment — new format uses = for target ID
    my $a = $session_mgr->load_attached() // return undef;
    if ($a =~ /=(.+)$/) {
        return { type => 'id', value => $1 };
    }
    # Legacy format: session:index
    if ($a =~ /:(\d+)$/) {
        return { type => 'index', value => int($1) };
    }
    return undef;
}

sub _attached_session {
    my $a = $session_mgr->load_attached() // return undef;
    my ($s) = $a =~ /^(\w+)/;
    return $s;
}

sub _resolve_session {
    my ($parsed) = @_;
    my $name = ($parsed->{target} && $parsed->{target}{session})
        // _attached_session()
        // die "Not attached. Run: bmux attach <session>\n";
    my $sessions = $session_mgr->load_sessions();
    my $s = $sessions->{$name} // die "No session named '$name'\n";
    $s->{_name} = $name;  # stash name for later use
    return $s;
}

# --- CDP dispatch (existing behavior) ---

sub _dispatch_cdp {
    my ($verb, $parsed, $session) = @_;
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
    elsif ($verb eq 'cdp')     { _cmd_cdp($cdp, $parsed) }
    elsif ($verb eq 'perf')    { _cmd_perf($cdp, $parsed) }
    elsif ($verb eq 'console') { die "Console inspection requires --follow for CDP\n" }
    elsif ($verb eq 'network') { die "Network inspection requires --follow for CDP\n" }
    elsif ($verb eq 'scripts') { die "Script listing not implemented\n" }
    elsif ($verb eq 'style')   { die "Style inspection not implemented\n" }
    else { die "Unknown command: $verb\n" }

    $cdp->close();
}

# --- WebDriver dispatch (Safari) ---

sub _dispatch_webdriver {
    my ($verb, $parsed, $session) = @_;
    
    my $base_url = "http://localhost:$session->{port}";
    my $client = Bmux::WebDriver::Client->new($base_url, $session->{session_id});
    
    if    ($verb eq 'goto')    { _wd_goto($client, $parsed) }
    elsif ($verb eq 'back')    { Bmux::WebDriver::Navigate::run_back($client); print "Back.\n" }
    elsif ($verb eq 'forward') { Bmux::WebDriver::Navigate::run_forward($client); print "Forward.\n" }
    elsif ($verb eq 'reload')  { Bmux::WebDriver::Navigate::run_reload($client); print "Reloaded.\n" }
    elsif ($verb eq 'capture') { _wd_capture($client, $parsed) }
    elsif ($verb eq 'click')   { _wd_click($client, $parsed) }
    elsif ($verb eq 'fill')    { _wd_fill($client, $parsed) }
    elsif ($verb eq 'type')    { _wd_type($client, $parsed) }
    elsif ($verb eq 'wait')    { _wd_wait($client, $parsed) }
    elsif ($verb eq 'eval')    { _wd_eval($client, $parsed) }
    elsif ($verb eq 'storage') { _wd_storage($client, $parsed) }
    elsif ($verb eq 'cookies') { _wd_cookies($client) }
    elsif ($verb eq 'console') { Bmux::WebDriver::Inspect::run_console() }
    elsif ($verb eq 'network') { Bmux::WebDriver::Inspect::run_network() }
    elsif ($verb eq 'scripts') { Bmux::WebDriver::Inspect::run_scripts() }
    elsif ($verb eq 'style')   { die "Style inspection not yet implemented for WebDriver\n" }
    else { die "Unknown command: $verb\n" }
}

# --- WebDriver command handlers ---

sub _wd_goto {
    my ($client, $parsed) = @_;
    my $url = $parsed->{object} // die "Usage: bmux goto <url>\n";
    Bmux::WebDriver::Navigate::run_goto($client, $url);
    print "Navigated to $url\n";
}

sub _wd_capture {
    my ($client, $parsed) = @_;
    my $selector = $parsed->{object};
    my $text_only = $parsed->{opts}{p};
    my $html = Bmux::WebDriver::Capture::run_capture($client, $selector, $text_only);
    print "$html\n";
}

sub _wd_click {
    my ($client, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux click <selector>\n";
    Bmux::WebDriver::Input::run_click($client, $selector);
    print "Clicked $selector\n";
}

sub _wd_fill {
    my ($client, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux fill <selector> <value>\n";
    my $value = $parsed->{args}[0] // die "Usage: bmux fill <selector> <value>\n";
    Bmux::WebDriver::Input::run_fill($client, $selector, $value);
    print "Filled $selector\n";
}

sub _wd_type {
    my ($client, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux type <selector> <value>\n";
    my $value = $parsed->{args}[0] // die "Usage: bmux type <selector> <value>\n";
    Bmux::WebDriver::Input::run_type($client, $selector, $value);
    print "Typed into $selector\n";
}

sub _wd_wait {
    my ($client, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux wait <selector>\n";
    my $timeout = $parsed->{opts}{timeout} // 30;
    my $found = Bmux::WebDriver::Input::run_wait($client, $selector, $timeout, 1);
    if ($found) {
        print "Found $selector\n";
    } else {
        die "Timeout waiting for $selector\n";
    }
}

sub _wd_eval {
    my ($client, $parsed) = @_;
    my $expr = $parsed->{object} // die "Usage: bmux eval <expression>\n";
    my $result = Bmux::WebDriver::Eval::run_eval($client, $expr);
    print "$result\n";
}

sub _wd_storage {
    my ($client, $parsed) = @_;
    my $session_flag = $parsed->{opts}{session};
    my $result = Bmux::WebDriver::Inspect::run_storage($client, $session_flag);
    print "$result\n";
}

sub _wd_cookies {
    my ($client) = @_;
    my $result = Bmux::WebDriver::Inspect::run_cookies($client);
    print "$result\n";
}

1;
