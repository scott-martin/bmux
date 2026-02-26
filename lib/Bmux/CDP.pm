package Bmux::CDP;
use strict;
use warnings;
use JSON::PP;

sub new {
    my ($class, %opts) = @_;
    return bless {
        next_id => 1,
        ws      => $opts{ws},       # Bmux::WebSocket connection
        events  => [],               # buffered events
    }, $class;
}

# Connect to a tab's WebSocket URL
sub connect {
    my ($class, $ws_url) = @_;
    require Bmux::WebSocket;
    my $ws = Bmux::WebSocket->connect($ws_url);
    return $class->new(ws => $ws);
}

# Send a CDP command and wait for its response.
# Events received while waiting are buffered.
sub send_command {
    my ($self, $method, $params) = @_;
    die "Not connected\n" unless $self->{ws};

    my ($id, $json) = $self->build_command($method, $params);
    $self->{ws}->send_text($json);

    # Read messages until we get our response
    while (1) {
        my $msg = $self->{ws}->recv_text();
        die "Connection closed while waiting for response\n" unless defined $msg;

        my $type = classify($msg);
        if ($type eq 'response') {
            my $resp = parse_response($msg);
            if ($resp->{id} == $id) {
                die "CDP error: $resp->{error}{message}\n" if $resp->{error};
                return $resp->{result};
            }
            # Response for a different id — shouldn't happen in serial use, ignore
        } else {
            # Buffer events for later
            push @{$self->{events}}, parse_event($msg);
        }
    }
}

# Drain buffered events
sub drain_events {
    my ($self) = @_;
    my @events = @{$self->{events}};
    $self->{events} = [];
    return @events;
}

# Close the connection
sub close {
    my ($self) = @_;
    $self->{ws}->close() if $self->{ws};
}

# Build a CDP command JSON string. Returns ($id, $json).
sub build_command {
    my ($self, $method, $params) = @_;
    my $id = $self->{next_id}++;

    my %msg = (
        id     => $id,
        method => $method,
    );
    $msg{params} = $params if defined $params;

    return ($id, encode_json(\%msg));
}

# Parse a CDP response (has "id" field)
sub parse_response {
    my ($json) = @_;
    return decode_json($json);
}

# Parse a CDP event (has "method" field, no "id")
sub parse_event {
    my ($json) = @_;
    return decode_json($json);
}

# Classify a raw JSON message as 'response' or 'event'
sub classify {
    my ($json) = @_;
    my $msg = decode_json($json);
    return (exists $msg->{id}) ? 'response' : 'event';
}

1;
