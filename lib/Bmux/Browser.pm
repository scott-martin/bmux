package Bmux::Browser;
use strict;
use warnings;

# Find Edge binary
sub find_edge {
    for my $path (
        'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
        'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
        '/usr/bin/microsoft-edge',
    ) {
        return $path if -f $path;
    }
    return 'msedge';
}

# Find Chrome binary
sub find_chrome {
    for my $path (
        'C:/Program Files/Google/Chrome/Application/chrome.exe',
        'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
        '/usr/bin/google-chrome',
    ) {
        return $path if -f $path;
    }
    return 'chrome';
}

# Get browser binary by name
sub find_by_name {
    my ($name) = @_;
    return find_edge()   if $name eq 'edge';
    return find_chrome() if $name eq 'chrome';
    die "Unknown browser: $name (try 'edge' or 'chrome')\n";
}

# Get a temp profile directory for isolated sessions
sub temp_profile {
    my ($name) = @_;
    my $tmp = $ENV{TEMP} // $ENV{TMP} // '/tmp';
    return "$tmp/bmux-$name";
}

# Spawn a browser process, return pid
sub spawn {
    my ($bin, @args) = @_;

    # On Windows/msys, use 'start' to launch detached
    my $cmd = qq{"$bin" } . join(' ', map { qq{"$_"} } @args);

    if ($^O eq 'msys' || $^O eq 'MSWin32' || $ENV{MSYSTEM}) {
        # On msys, fork+exec and system() both block.
        # Use bash's disown to fully detach the process.
        my $escaped = qq{"$bin" } . join(' ', map { qq{"$_"} } @args);
        my $bash_cmd = qq{($escaped &>/dev/null &)};
        `$bash_cmd`;
        sleep 2;
        return _find_pid($bin);
    } else {
        my $pid = fork();
        die "Fork failed: $!\n" unless defined $pid;
        if ($pid == 0) {
            require POSIX;
            POSIX::setsid();
            exec($bin, @args) or die "Cannot exec $bin: $!\n";
        }
        return $pid;
    }
}

# Find PID of a running process by binary name (Windows)
sub _find_pid {
    my ($bin) = @_;
    # Extract just the exe name
    my ($exe) = $bin =~ /([^\/\\]+)$/;
    my $out = `tasklist /FI "IMAGENAME eq $exe" /FO CSV /NH 2>nul`;
    for my $line (split /\n/, $out) {
        if ($line =~ /"[^"]+","(\d+)"/) {
            return int($1);
        }
    }
    return 0;  # unknown
}

1;
