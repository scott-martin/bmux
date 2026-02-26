#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Capture;

# --- Get page source request ---

{
    my $req = Bmux::WebDriver::Capture::get_source_request('sess123');
    
    is($req->{method}, 'GET', 'get source is GET');
    is($req->{path}, '/session/sess123/source', 'get source path');
}

# --- Execute script request (for outerHTML) ---

{
    my $req = Bmux::WebDriver::Capture::execute_request('sess123', 'return document.body.outerHTML', []);
    
    is($req->{method}, 'POST', 'execute is POST');
    is($req->{path}, '/session/sess123/execute/sync', 'execute path');
    is($req->{body}{script}, 'return document.body.outerHTML', 'execute script');
    is_deeply($req->{body}{args}, [], 'execute args empty');
}

{
    my $req = Bmux::WebDriver::Capture::execute_request('sess123', 'return arguments[0].outerHTML', ['elem-ref']);
    
    is_deeply($req->{body}{args}, ['elem-ref'], 'execute with args');
}

# --- Element outerHTML script ---

{
    my $script = Bmux::WebDriver::Capture::outer_html_script();
    
    like($script, qr/outerHTML/, 'outer_html_script references outerHTML');
    like($script, qr/arguments\[0\]/, 'outer_html_script uses arguments[0]');
}

# --- Strip HTML ---

{
    my $html = '<div><p>Hello <b>world</b></p></div>';
    my $text = Bmux::WebDriver::Capture::strip_html($html);
    
    is($text, 'Hello world', 'strip_html removes tags');
}

{
    my $html = '<div>  Multiple   spaces  </div>';
    my $text = Bmux::WebDriver::Capture::strip_html($html);
    
    is($text, 'Multiple spaces', 'strip_html collapses whitespace');
}

{
    my $html = "<div>Line1\n\nLine2</div>";
    my $text = Bmux::WebDriver::Capture::strip_html($html);
    
    like($text, qr/Line1.*Line2/, 'strip_html handles newlines');
}

{
    my $html = '<script>var x = 1;</script><p>Content</p><style>.x{}</style>';
    my $text = Bmux::WebDriver::Capture::strip_html($html);
    
    is($text, 'Content', 'strip_html removes script and style');
}

# --- High-level runners with mock ---

{
    package MockClient;
    my $ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';
    
    sub new { 
        my ($class, %responses) = @_;
        bless { calls => [], responses => \%responses }, $class;
    }
    sub session_id { 'mock-session' }
    sub get {
        my ($self, $path) = @_;
        push @{$self->{calls}}, { method => 'GET', path => $path };
        return $self->{responses}{get} // '<html>page source</html>';
    }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        if ($path =~ /\/element$/) {
            return { $ELEMENT_KEY => 'found-elem' };
        }
        if ($path =~ /\/execute/) {
            return $self->{responses}{execute} // '<div>element html</div>';
        }
        return undef;
    }
    sub calls { shift->{calls} }
    
    package main;
}

# run_capture: no selector = full page source
{
    my $client = MockClient->new(get => '<html><body>Full page</body></html>');
    my $result = Bmux::WebDriver::Capture::run_capture($client, undef, 0);
    
    is($result, '<html><body>Full page</body></html>', 'run_capture returns page source');
    is($client->calls->[0]{method}, 'GET', 'run_capture uses GET');
    like($client->calls->[0]{path}, qr/\/source$/, 'run_capture gets source');
}

# run_capture: with selector = element outerHTML via script
{
    my $client = MockClient->new(execute => '<div class="target">Content</div>');
    my $result = Bmux::WebDriver::Capture::run_capture($client, 'div.target', 0);
    
    is($result, '<div class="target">Content</div>', 'run_capture with selector returns element HTML');
    
    my @calls = @{$client->calls};
    # Should find element, then execute script
    like($calls[0]{path}, qr/\/element$/, 'first call finds element');
    like($calls[1]{path}, qr/\/execute/, 'second call executes script');
}

# run_capture: plain text mode
{
    my $client = MockClient->new(get => '<html><body><p>Plain text content</p></body></html>');
    my $result = Bmux::WebDriver::Capture::run_capture($client, undef, 1);
    
    is($result, 'Plain text content', 'run_capture with plain flag strips HTML');
}

# run_capture: selector + plain
{
    my $client = MockClient->new(execute => '<div><b>Bold</b> and normal</div>');
    my $result = Bmux::WebDriver::Capture::run_capture($client, 'div', 1);
    
    is($result, 'Bold and normal', 'run_capture selector + plain strips HTML');
}

done_testing;
