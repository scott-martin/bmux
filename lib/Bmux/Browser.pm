package Bmux::Browser;
use strict;
use warnings;

my $IS_WINDOWS = $^O eq 'MSWin32' || $^O eq 'msys' || $ENV{MSYSTEM};
my $IS_DARWIN  = $^O eq 'darwin';

# Find Edge binary
sub find_edge {
    my @paths = $IS_DARWIN
        ? ('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge')
        : $IS_WINDOWS
        ? ('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
           'C:/Program Files/Microsoft/Edge/Application/msedge.exe')
        : ('/usr/bin/microsoft-edge');

    for my $path (@paths) {
        return $path if -f $path;
    }
    return $IS_WINDOWS ? 'msedge' : 'microsoft-edge';
}

# Find Chrome binary
sub find_chrome {
    my @paths = $IS_DARWIN
        ? ('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        : $IS_WINDOWS
        ? ('C:/Program Files/Google/Chrome/Application/chrome.exe',
           'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe')
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
sub temp_profile {
    my ($name) = @_;
    my $tmp = $IS_DARWIN
        ? ($ENV{TMPDIR} // '/tmp')
        : ($ENV{TEMP} // $ENV{TMP} // '/tmp');
    $tmp =~ s{/$}{};  # strip trailing slash from macOS TMPDIR
    return "$tmp/bmux-$name";
}

# Spawn a browser process, return pid
sub spawn {
    my ($bin, @args) = @_;

    if ($IS_WINDOWS) {
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
