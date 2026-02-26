package Bmux::WebSocket;
use strict;
use warnings;
use MIME::Base64;
use Digest::SHA qw(sha1);
use IO::Socket::INET;

# WebSocket opcodes
use constant {
    OP_TEXT  => 1,
    OP_CLOSE => 8,
    OP_PING  => 9,
    OP_PONG  => 10,
};

# Build a masked text frame (client → server)
sub build_frame {
    my ($payload) = @_;
    my $len = length($payload);

    # FIN=1, opcode=text
    my $header = pack('C', 0x81);

    # Mask bit always set for client frames
    if ($len < 126) {
        $header .= pack('C', 0x80 | $len);
    } elsif ($len < 65536) {
        $header .= pack('C', 0x80 | 126);
        $header .= pack('n', $len);
    } else {
        $header .= pack('C', 0x80 | 127);
        $header .= pack('NN', 0, $len);  # 64-bit, high 32 bits = 0
    }

    # Generate 4-byte masking key
    my @mask = map { int(rand(256)) } 1..4;
    $header .= pack('C4', @mask);

    # Mask the payload
    my $masked = '';
    for my $i (0 .. $len - 1) {
        $masked .= chr(ord(substr($payload, $i, 1)) ^ $mask[$i % 4]);
    }

    return $header . $masked;
}

# Build a masked close frame
sub build_close_frame {
    # FIN=1, opcode=close, mask=1, length=0
    my @mask = map { int(rand(256)) } 1..4;
    return pack('C2', 0x88, 0x80) . pack('C4', @mask);
}

# Parse an unmasked frame (server → client)
# Returns (opcode, payload)
sub parse_frame {
    my ($data) = @_;
    my @bytes = unpack('C*', $data);

    my $opcode = $bytes[0] & 0x0F;
    my $masked = ($bytes[1] & 0x80) ? 1 : 0;
    my $len    = $bytes[1] & 0x7F;
    my $offset = 2;

    if ($len == 126) {
        $len = ($bytes[2] << 8) | $bytes[3];
        $offset = 4;
    } elsif ($len == 127) {
        # 64-bit length — use high 32 bits from bytes 2-5 (should be 0)
        $len = ($bytes[6] << 24) | ($bytes[7] << 16) | ($bytes[8] << 8) | $bytes[9];
        $offset = 10;
    }

    my @mask;
    if ($masked) {
        @mask = @bytes[$offset .. $offset + 3];
        $offset += 4;
    }

    my $payload = '';
    for my $i (0 .. $len - 1) {
        my $byte = $bytes[$offset + $i];
        $byte ^= $mask[$i % 4] if $masked;
        $payload .= chr($byte);
    }

    return ($opcode, $payload);
}

# Compute Sec-WebSocket-Accept from client key (RFC 6455)
sub compute_accept_key {
    my ($client_key) = @_;
    my $magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    return encode_base64(sha1($client_key . $magic), '');
}

# Generate a random base64-encoded 16-byte key for handshake
sub generate_key {
    my $raw = join('', map { chr(int(rand(256))) } 1..16);
    return encode_base64($raw, '');
}

# --- Connection methods ---

# Connect to a WebSocket URL (ws://host:port/path)
# Returns a Bmux::WebSocket connection object
sub connect {
    my ($class, $url) = @_;

    my ($host, $port, $path) = $url =~ m{^ws://([^:]+):(\d+)(/.*)$}
        or die "Invalid WebSocket URL: $url\n";

    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Cannot connect to $host:$port: $!\n";

    $sock->autoflush(1);
    binmode($sock);

    # HTTP upgrade handshake
    my $key = generate_key();
    my $req = join("\r\n",
        "GET $path HTTP/1.1",
        "Host: $host:$port",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Key: $key",
        "Sec-WebSocket-Version: 13",
        "", "",
    );

    print $sock $req;

    # Read response headers
    my $resp = '';
    while (my $line = <$sock>) {
        $resp .= $line;
        last if $line eq "\r\n";
    }

    die "WebSocket upgrade failed:\n$resp\n" unless $resp =~ /101/;

    return bless {
        sock => $sock,
        url  => $url,
    }, $class;
}

# Send a text frame
sub send_text {
    my ($self, $payload) = @_;
    my $frame = build_frame($payload);
    print { $self->{sock} } $frame;
}

# Receive one frame. Returns (opcode, payload).
# Reads from socket byte by byte to handle framing correctly.
sub recv_frame {
    my ($self) = @_;
    my $sock = $self->{sock};

    # Read first 2 bytes
    my $header;
    _read_exact($sock, \$header, 2) or die "WebSocket: connection closed\n";
    my @h = unpack('CC', $header);

    my $opcode = $h[0] & 0x0F;
    my $masked = ($h[1] & 0x80) ? 1 : 0;
    my $len    = $h[1] & 0x7F;

    if ($len == 126) {
        my $ext;
        _read_exact($sock, \$ext, 2) or die "WebSocket: short read\n";
        $len = unpack('n', $ext);
    } elsif ($len == 127) {
        my $ext;
        _read_exact($sock, \$ext, 8) or die "WebSocket: short read\n";
        my ($hi, $lo) = unpack('NN', $ext);
        $len = $lo;  # ignore high 32 bits
    }

    my @mask;
    if ($masked) {
        my $mask_bytes;
        _read_exact($sock, \$mask_bytes, 4) or die "WebSocket: short read\n";
        @mask = unpack('CCCC', $mask_bytes);
    }

    my $payload = '';
    if ($len > 0) {
        _read_exact($sock, \$payload, $len) or die "WebSocket: short read\n";
        if ($masked) {
            my @bytes = unpack('C*', $payload);
            for my $i (0 .. $#bytes) {
                $bytes[$i] ^= $mask[$i % 4];
            }
            $payload = pack('C*', @bytes);
        }
    }

    # Auto-respond to pings
    if ($opcode == OP_PING) {
        my $pong = build_pong_frame($payload);
        print $sock $pong;
    }

    return ($opcode, $payload);
}

# Receive a text message (skips pings/pongs)
sub recv_text {
    my ($self) = @_;
    while (1) {
        my ($opcode, $payload) = $self->recv_frame();
        return $payload if $opcode == OP_TEXT;
        return undef    if $opcode == OP_CLOSE;
        # skip pings, pongs, other control frames
    }
}

# Close the connection
sub close {
    my ($self) = @_;
    eval {
        my $frame = build_close_frame();
        print { $self->{sock} } $frame;
        $self->{sock}->close();
    };
}

# Build a masked pong frame
sub build_pong_frame {
    my ($payload) = @_;
    $payload //= '';
    my $len = length($payload);
    my @mask = map { int(rand(256)) } 1..4;

    my $frame = pack('CC', 0x8A, 0x80 | $len) . pack('C4', @mask);
    for my $i (0 .. $len - 1) {
        $frame .= chr(ord(substr($payload, $i, 1)) ^ $mask[$i % 4]);
    }
    return $frame;
}

sub _read_exact {
    my ($sock, $buf_ref, $len) = @_;
    $$buf_ref = '';
    while (length($$buf_ref) < $len) {
        my $remaining = $len - length($$buf_ref);
        my $n = read($sock, my $chunk, $remaining);
        return 0 unless defined $n && $n > 0;
        $$buf_ref .= $chunk;
    }
    return 1;
}

1;
