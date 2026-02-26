package Bmux::WebDriver::Client;
use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);

sub new {
    my ($class, $base_url, $session_id) = @_;
    $base_url =~ s{/$}{};  # strip trailing slash
    return bless {
        base_url   => $base_url,
        session_id => $session_id,
    }, $class;
}

sub session_id {
    my ($self) = @_;
    return $self->{session_id};
}

sub set_session_id {
    my ($self, $session_id) = @_;
    $self->{session_id} = $session_id;
}

sub build_url {
    my ($self, $path) = @_;
    return $self->{base_url} . $path;
}

sub session_path {
    my ($self, $suffix) = @_;
    die "No session ID set\n" unless $self->{session_id};
    return "/session/$self->{session_id}$suffix";
}

sub build_request {
    my ($self, $method, $path, $body) = @_;
    my $req = {
        method  => $method,
        url     => $self->build_url($path),
        headers => { 'Content-Type' => 'application/json' },
    };
    $req->{body} = $body if defined $body;
    return $req;
}

sub build_post {
    my ($self, $path, $body) = @_;
    return $self->build_request('POST', $path, $body);
}

sub build_get {
    my ($self, $path) = @_;
    return $self->build_request('GET', $path);
}

sub build_delete {
    my ($self, $path) = @_;
    return $self->build_request('DELETE', $path);
}

sub parse_response {
    my ($json) = @_;
    my $data = decode_json($json);
    my $value = $data->{value};
    
    # Check for error response
    if (ref $value eq 'HASH' && $value->{error}) {
        my $error = $value->{error};
        my $message = $value->{message} // '';
        die "WebDriver error: $error - $message\n";
    }
    
    return $value;
}

# HTTP execution (requires IO::Socket)
sub post {
    my ($self, $path, $body) = @_;
    my $req = $self->build_post($path, $body);
    return $self->_execute($req);
}

sub get {
    my ($self, $path) = @_;
    my $req = $self->build_get($path);
    return $self->_execute($req);
}

sub delete {
    my ($self, $path) = @_;
    my $req = $self->build_delete($path);
    return $self->_execute($req);
}

sub _execute {
    my ($self, $req) = @_;
    require IO::Socket::INET;
    
    my ($host, $port, $path) = $self->_parse_url($req->{url});
    
    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Cannot connect to $host:$port: $!\n";
    
    my $body_json = defined $req->{body} ? encode_json($req->{body}) : '';
    my $content_length = length($body_json);
    
    my $http = "$req->{method} $path HTTP/1.1\r\n";
    $http .= "Host: $host:$port\r\n";
    $http .= "Content-Type: application/json\r\n";
    $http .= "Content-Length: $content_length\r\n";
    $http .= "Connection: close\r\n";
    $http .= "\r\n";
    $http .= $body_json;
    
    print $sock $http;
    
    my $response = '';
    while (my $line = <$sock>) {
        $response .= $line;
    }
    close $sock;
    
    my ($headers, $body) = split /\r\n\r\n/, $response, 2;
    return parse_response($body);
}

sub _parse_url {
    my ($self, $url) = @_;
    if ($url =~ m{^https?://([^:/]+)(?::(\d+))?(.*)$}) {
        my $host = $1;
        my $port = $2 // 80;
        my $path = $3 || '/';
        return ($host, $port, $path);
    }
    die "Cannot parse URL: $url\n";
}

1;
