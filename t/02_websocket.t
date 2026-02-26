#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebSocket;

# --- Frame building (client → server, must be masked) ---

# Small text frame (payload < 126 bytes)
{
    my $frame = Bmux::WebSocket::build_frame("hello");
    my @bytes = unpack('C*', $frame);

    # First byte: FIN=1, opcode=1 (text) → 0x81
    is($bytes[0], 0x81, 'small frame: FIN + text opcode');

    # Second byte: MASK=1, length=5 → 0x85
    is($bytes[1], 0x85, 'small frame: masked + length 5');

    # Bytes 2-5: masking key (4 bytes)
    # Bytes 6-10: masked payload (5 bytes)
    is(length($frame), 2 + 4 + 5, 'small frame: correct total length');

    # Unmask and verify payload
    my @mask = @bytes[2..5];
    my $payload = '';
    for my $i (0..4) {
        $payload .= chr($bytes[6 + $i] ^ $mask[$i % 4]);
    }
    is($payload, 'hello', 'small frame: unmasked payload matches');
}

# Medium text frame (126 <= payload < 65536)
{
    my $data = 'x' x 200;
    my $frame = Bmux::WebSocket::build_frame($data);
    my @bytes = unpack('C*', $frame);

    is($bytes[0], 0x81, 'medium frame: FIN + text opcode');
    is($bytes[1], 0xFE, 'medium frame: masked + length marker 126');

    # Bytes 2-3: 16-bit length in network byte order
    my $len = ($bytes[2] << 8) | $bytes[3];
    is($len, 200, 'medium frame: 16-bit length');

    # 2 header + 2 extended length + 4 mask + 200 payload
    is(length($frame), 2 + 2 + 4 + 200, 'medium frame: correct total length');
}

# Close frame
{
    my $frame = Bmux::WebSocket::build_close_frame();
    my @bytes = unpack('C*', $frame);

    # FIN=1, opcode=8 (close) → 0x88
    is($bytes[0], 0x88, 'close frame: FIN + close opcode');
    # MASK=1, length=0 → 0x80
    is($bytes[1], 0x80, 'close frame: masked + length 0');
    # 2 header + 4 mask key
    is(length($frame), 2 + 4, 'close frame: correct total length');
}

# --- Frame parsing (server → client, unmasked) ---

# Small unmasked text frame from server
{
    # Build a server frame manually: FIN+text, no mask, 5 bytes
    my $server_frame = pack('C*', 0x81, 5) . "hello";
    my ($opcode, $payload) = Bmux::WebSocket::parse_frame($server_frame);

    is($opcode, 1, 'parse small: text opcode');
    is($payload, 'hello', 'parse small: payload');
}

# Medium unmasked text frame from server
{
    my $data = 'y' x 300;
    # FIN+text, length=126, then 16-bit length
    my $server_frame = pack('CCn', 0x81, 126, 300) . $data;
    my ($opcode, $payload) = Bmux::WebSocket::parse_frame($server_frame);

    is($opcode, 1, 'parse medium: text opcode');
    is(length($payload), 300, 'parse medium: payload length');
    is($payload, $data, 'parse medium: payload content');
}

# Ping frame
{
    my $server_frame = pack('C*', 0x89, 0);  # FIN + ping, no payload
    my ($opcode, $payload) = Bmux::WebSocket::parse_frame($server_frame);

    is($opcode, 9, 'parse ping: opcode');
    is($payload, '', 'parse ping: empty payload');
}

# Pong frame
{
    my $server_frame = pack('C*', 0x8A, 4) . "pong";
    my ($opcode, $payload) = Bmux::WebSocket::parse_frame($server_frame);

    is($opcode, 10, 'parse pong: opcode');
    is($payload, 'pong', 'parse pong: payload');
}

# --- Handshake key computation ---
{
    # RFC 6455 example
    my $key = "dGhlIHNhbXBsZSBub25jZQ==";
    my $accept = Bmux::WebSocket::compute_accept_key($key);
    is($accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", 'accept key matches RFC 6455 example');
}

done_testing;
