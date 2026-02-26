package Bmux::Session;
use strict;
use warnings;
use JSON::PP;
use File::Path qw(mkpath);

sub new {
    my ($class, %opts) = @_;
    my $state_dir = $opts{state_dir} // _default_state_dir();
    return bless { state_dir => $state_dir }, $class;
}

sub _default_state_dir {
    my $home = $ENV{HOME} // $ENV{USERPROFILE} // '.';
    return "$home/.bmux";
}

sub _sessions_file { return "$_[0]->{state_dir}/sessions.json" }
sub _attached_file  { return "$_[0]->{state_dir}/attached" }

sub _ensure_dir {
    my ($self) = @_;
    mkpath($self->{state_dir}) unless -d $self->{state_dir};
}

# Load all sessions from state file
sub load_sessions {
    my ($self) = @_;
    my $file = $self->_sessions_file();
    return {} unless -f $file;

    open my $fh, '<', $file or return {};
    local $/;
    my $json = <$fh>;
    close $fh;

    return eval { decode_json($json) } // {};
}

# Save a named session
sub save_session {
    my ($self, $name, $data) = @_;
    $self->_ensure_dir();

    my $sessions = $self->load_sessions();
    $sessions->{$name} = $data;
    $self->_write_sessions($sessions);
}

# Remove a named session
sub remove_session {
    my ($self, $name) = @_;
    my $sessions = $self->load_sessions();
    delete $sessions->{$name};
    $self->_write_sessions($sessions) if -d $self->{state_dir};
}

sub _write_sessions {
    my ($self, $sessions) = @_;
    $self->_ensure_dir();
    my $file = $self->_sessions_file();
    open my $fh, '>', $file or die "Cannot write $file: $!\n";
    print $fh encode_json($sessions);
    close $fh;
}

# Save the currently attached target (e.g. "edge:3")
sub save_attached {
    my ($self, $target) = @_;
    $self->_ensure_dir();
    my $file = $self->_attached_file();
    open my $fh, '>', $file or die "Cannot write $file: $!\n";
    print $fh $target;
    close $fh;
}

# Load the currently attached target
sub load_attached {
    my ($self) = @_;
    my $file = $self->_attached_file();
    return undef unless -f $file;

    open my $fh, '<', $file or return undef;
    my $target = <$fh>;
    close $fh;

    return undef unless defined $target && $target =~ /\S/;
    chomp $target;
    return $target;
}

# Clear the attached target (detach)
sub clear_attached {
    my ($self) = @_;
    my $file = $self->_attached_file();
    unlink $file if -f $file;
}

# Session type helpers

sub is_cdp_session {
    my ($session) = @_;
    return 0 unless ref $session eq 'HASH';
    # Explicit type check, or legacy sessions without type are assumed CDP
    return 1 if !exists $session->{type};
    return $session->{type} eq 'cdp';
}

sub is_webdriver_session {
    my ($session) = @_;
    return 0 unless ref $session eq 'HASH';
    return 0 unless exists $session->{type};
    return $session->{type} eq 'webdriver';
}

1;
