package Bmux::Browser;
use strict;
use warnings;

my $IS_WINDOWS = $^O eq 'MSWin32' || $^O eq 'msys' || $ENV{MSYSTEM};
my $IS_DARWIN  = $^O eq 'darwin';
my $IS_WSL     = !$IS_WINDOWS && -f '/proc/version' && do {
    open my $fh, '<', '/proc/version'; my $v = <$fh>; close $fh; $v =~ /microsoft/i;
};

# Find Edge binary
sub find_edge {
    my @paths = $IS_DARWIN
        ? ('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge')
        : $IS_WINDOWS
        ? ('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
           'C:/Program Files/Microsoft/Edge/Application/msedge.exe')
        : $IS_WSL
        ? ('/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
           '/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe')
        : ('/usr/bin/microsoft-edge');

    for my $path (@paths) {
        return $path if -f $path;
    }
    return ($IS_WINDOWS || $IS_WSL) ? 'msedge.exe' : 'microsoft-edge';
}

# Find Chrome binary
sub find_chrome {
    my @paths = $IS_DARWIN
        ? ('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        : $IS_WINDOWS
        ? ('C:/Program Files/Google/Chrome/Application/chrome.exe',
           'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe')
        : $IS_WSL
        ? ('/mnt/c/Program Files/Google/Chrome/Application/chrome.exe',
           '/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe')
        : ('/usr/bin/google-chrome', '/usr/bin/chromium-browser');

    for my $path (@paths) {
        return $path if -f $path;
    }
    return 'chrome';
}

# Find Brave binary
sub find_brave {
    my @paths = $IS_DARWIN
        ? ('/Applications/Brave Browser.app/Contents/MacOS/Brave Browser')
        : $IS_WINDOWS
        ? ('C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe',
           'C:/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe')
        : $IS_WSL
        ? ('/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe',
           '/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe')
        : ('/usr/bin/brave-browser', '/usr/bin/brave');

    for my $path (@paths) {
        return $path if -f $path;
    }
    return 'brave';
}

# Find Safari (actually safaridriver)
sub find_safari {
    return 'safaridriver';
}

# Get browser binary by name
sub find_by_name {
    my ($name) = @_;
    return find_edge()   if $name eq 'edge';
    return find_chrome() if $name eq 'chrome';
    return find_brave()  if $name eq 'brave';
    return find_safari() if $name eq 'safari';
    die "Unknown browser: $name (try 'edge', 'chrome', 'brave', or 'safari')\n";
}

# Browser type detection
sub is_webdriver_browser {
    my ($name) = @_;
    return $name eq 'safari';
}

sub is_cdp_browser {
    my ($name) = @_;
    return $name =~ /^(chrome|edge|brave)$/;
}

# Get a temp profile directory for isolated sessions
# Return a Windows-native temp profile path for WSL, normal path otherwise
my $_wsl_tmp;
sub temp_profile {
    my ($name) = @_;
    my $tmp = $IS_DARWIN
        ? ($ENV{TMPDIR} // '/tmp')
        : $IS_WSL
        ? ($_wsl_tmp //= do {
            my $p = `powershell.exe -NoProfile -Command 'echo \$env:TEMP' 2>/dev/null`;
            chomp $p; $p =~ s/\r//g;
            $p =~ s|/|\\|g;  # keep Windows-native backslashes
            $p || 'C:\\Temp';
        })
        : ($ENV{TEMP} // $ENV{TMP} // '/tmp');
    $tmp =~ s{[/\\]$}{};
    return $IS_WSL ? "$tmp\\bmux-$name" : "$tmp/bmux-$name";
}

# CDP host — Windows host IP when in WSL, localhost otherwise
my $_wsl_host;
sub cdp_host {
    return 'localhost' unless $IS_WSL;
    return $_wsl_host if defined $_wsl_host;
    # Default gateway is the Windows host in WSL2 NAT mode
    if (open my $fh, '-|', 'ip route show default') {
        my $line = <$fh>;
        $_wsl_host = $1 if $line =~ /via\s+(\S+)/;
        close $fh;
    }
    $_wsl_host //= 'localhost';
    return $_wsl_host;
}

sub is_wsl { return $IS_WSL }

# In WSL, connect through portproxy (Edge on 9222, proxy on 19222)
sub cdp_port {
    my ($port) = @_;
    return $IS_WSL ? $port + 10000 : $port;
}

# Check if a browser is already running (Windows only)
sub _is_running_windows {
    my ($bin) = @_;
    my ($exe) = $bin =~ /([^\/\\]+)$/;
    my $out = `tasklist //FI "IMAGENAME eq $exe" //FO CSV //NH 2>nul`;
    return $out =~ /\Q$exe\E/i;
}

# Check if a browser is already running (WSL — queries Windows via powershell)
sub _is_running_wsl {
    my ($bin) = @_;
    my ($exe) = $bin =~ /([^\/\\]+)$/;
    my $out = `powershell.exe -Command "Get-Process -Name '${\( $exe =~ s/\.exe$//r )}' -ErrorAction SilentlyContinue | Select-Object -First 1 Id" 2>/dev/null`;
    return $out =~ /\d+/;
}

# Spawn a browser process, return pid
sub spawn {
    my ($bin, @args) = @_;

    if ($IS_WSL) {
        if (_is_running_wsl($bin)) {
            my ($exe) = $bin =~ /([^\/\\]+)$/;
            my $pname = $exe =~ s/\.exe$//r;
            print "Killing stray $exe processes...\n";
            `powershell.exe -Command "Stop-Process -Name '$pname' -Force -ErrorAction SilentlyContinue" 2>/dev/null`;
            # Wait until fully dead — Edge auto-restarts aggressively
            for (1..10) {
                last unless _is_running_wsl($bin);
                `powershell.exe -Command "Stop-Process -Name '$pname' -Force -ErrorAction SilentlyContinue" 2>/dev/null`;
                sleep 1;
            }
            if (_is_running_wsl($bin)) {
                die "Cannot stop $exe — it keeps restarting. Disable Edge auto-restore and retry.\n";
            }
        }
    }

    if ($IS_WINDOWS) {
        # Chrome/Edge merge into a running instance and ignore
        # --remote-debugging-port if one is already running.
        if (_is_running_windows($bin)) {
            my ($exe) = $bin =~ /([^\/\\]+)$/;
            die "Cannot start with debug port: $exe is already running.\n"
              . "Close all $exe windows first, then retry.\n";
        }

        # On msys, fork+exec and system() both block.
        # Use bash's disown to fully detach the process.
        my $escaped = qq{"$bin" } . join(' ', map { qq{"$_"} } @args);
        my $bash_cmd = qq{($escaped &>/dev/null &)};
        `$bash_cmd`;
        sleep 2;
        return _find_pid_windows($bin);
    } else {
        my $pid = fork();
        die "Fork failed: $!\n" unless defined $pid;
        if ($pid == 0) {
            require POSIX;
            POSIX::setsid();
            open STDIN,  '</dev/null';
            open STDOUT, '>/dev/null';
            open STDERR, '>/dev/null';
            exec($bin, @args) or die "Cannot exec $bin: $!\n";
        }
        return $pid;
    }
}

# Find PID of a running process by binary name (Windows)
sub _find_pid_windows {
    my ($bin) = @_;
    my ($exe) = $bin =~ /([^\/\\]+)$/;
    my $out = `tasklist /FI "IMAGENAME eq $exe" /FO CSV /NH 2>nul`;
    for my $line (split /\n/, $out) {
        if ($line =~ /"[^"]+","(\d+)"/) {
            return int($1);
        }
    }
    return 0;
}

1;
