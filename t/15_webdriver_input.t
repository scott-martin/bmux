#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Input;

# --- Click request ---

{
    my $req = Bmux::WebDriver::Input::click_request('sess123', 'elem-456');
    
    is($req->{method}, 'POST', 'click is POST');
    is($req->{path}, '/session/sess123/element/elem-456/click', 'click path');
    is_deeply($req->{body}, {}, 'click has empty body');
}

# --- Clear request ---

{
    my $req = Bmux::WebDriver::Input::clear_request('sess123', 'elem-456');
    
    is($req->{method}, 'POST', 'clear is POST');
    is($req->{path}, '/session/sess123/element/elem-456/clear', 'clear path');
    is_deeply($req->{body}, {}, 'clear has empty body');
}

# --- Send keys request ---

{
    my $req = Bmux::WebDriver::Input::send_keys_request('sess123', 'elem-456', 'hello world');
    
    is($req->{method}, 'POST', 'send keys is POST');
    is($req->{path}, '/session/sess123/element/elem-456/value', 'send keys path');
    is($req->{body}{text}, 'hello world', 'send keys text');
}

{
    my $req = Bmux::WebDriver::Input::send_keys_request('sess123', 'elem-456', 'special chars: @#$');
    
    is($req->{body}{text}, 'special chars: @#$', 'send keys preserves special chars');
}

# --- High-level runners with mock ---

{
    package MockClient;
    my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';
    
    sub new { 
        my ($class) = @_;
        bless { calls => [] }, $class;
    }
    sub session_id { 'mock-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        # Return element ID when finding elements
        if ($path =~ /\/element$/) {
            return { $ELEMENT_KEY => 'found-elem-id' };
        }
        return undef;
    }
    sub calls { shift->{calls} }
    sub clear_calls { shift->{calls} = [] }
    
    package main;
}

# run_click: find element, then click
{
    my $client = MockClient->new();
    Bmux::WebDriver::Input::run_click($client, 'button.submit');
    
    my @calls = @{$client->calls};
    is(scalar @calls, 2, 'run_click makes two calls');
    
    # First call: find element
    like($calls[0]{path}, qr/\/element$/, 'first call finds element');
    is($calls[0]{body}{value}, 'button.submit', 'find with selector');
    
    # Second call: click
    like($calls[1]{path}, qr/\/element\/found-elem-id\/click$/, 'second call clicks element');
}

# run_fill: find element, clear, send keys
{
    my $client = MockClient->new();
    Bmux::WebDriver::Input::run_fill($client, 'input.name', 'John Doe');
    
    my @calls = @{$client->calls};
    is(scalar @calls, 3, 'run_fill makes three calls');
    
    like($calls[0]{path}, qr/\/element$/, 'first call finds element');
    like($calls[1]{path}, qr/\/clear$/, 'second call clears');
    like($calls[2]{path}, qr/\/value$/, 'third call sends keys');
    is($calls[2]{body}{text}, 'John Doe', 'sends correct text');
}

# run_type: same as fill (WebDriver doesn't distinguish keystroke-by-keystroke)
{
    my $client = MockClient->new();
    Bmux::WebDriver::Input::run_type($client, 'input.search', 'query');
    
    my @calls = @{$client->calls};
    is(scalar @calls, 3, 'run_type makes three calls');
    is($calls[2]{body}{text}, 'query', 'run_type sends text');
}

# run_wait: poll until found
{
    package MockClientWithRetry;
    my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';
    
    sub new { 
        my ($class, $fail_count) = @_;
        bless { calls => [], fail_count => $fail_count // 0 }, $class;
    }
    sub session_id { 'mock-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        if ($path =~ /\/element$/) {
            if ($self->{fail_count} > 0) {
                $self->{fail_count}--;
                die "WebDriver error: no such element - not found\n";
            }
            return { $ELEMENT_KEY => 'finally-found' };
        }
        return undef;
    }
    sub calls { shift->{calls} }
    
    package main;
    
    # Element found immediately
    my $client1 = MockClientWithRetry->new(0);
    my $found = Bmux::WebDriver::Input::run_wait($client1, 'div.loaded', 5, 0);
    ok($found, 'run_wait returns true when found');
    is(scalar @{$client1->calls}, 1, 'run_wait with immediate find: one call');
    
    # Element found after 2 retries
    my $client2 = MockClientWithRetry->new(2);
    $found = Bmux::WebDriver::Input::run_wait($client2, 'div.loaded', 5, 0);
    ok($found, 'run_wait returns true after retries');
    is(scalar @{$client2->calls}, 3, 'run_wait retried 3 times');
}

# run_wait: timeout
{
    package MockClientNeverFound;
    sub new { bless { calls => [] }, shift }
    sub session_id { 'mock-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { path => $path };
        die "WebDriver error: no such element - not found\n";
    }
    sub calls { shift->{calls} }
    
    package main;
    
    my $client = MockClientNeverFound->new();
    my $found = Bmux::WebDriver::Input::run_wait($client, 'div.missing', 2, 0);
    ok(!$found, 'run_wait returns false on timeout');
}

done_testing;
