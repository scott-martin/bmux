package Bmux::WebDriver::Eval;
use strict;
use warnings;
use JSON::PP qw(encode_json);

sub execute_request {
    my ($session_id, $script, $args) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/execute/sync",
        body   => {
            script => $script,
            args   => $args // [],
        },
    };
}

sub execute_async_request {
    my ($session_id, $script, $args) = @_;
    return {
        method => 'POST',
        path   => "/session/$session_id/execute/async",
        body   => {
            script => $script,
            args   => $args // [],
        },
    };
}

sub wrap_script {
    my ($script) = @_;
    # If script already starts with return (with optional whitespace), leave it
    return $script if $script =~ /^\s*return\b/;
    # Otherwise wrap it
    return "return $script";
}

sub format_result {
    my ($value) = @_;
    
    return 'null' unless defined $value;
    
    # Handle JSON::PP booleans
    if (JSON::PP::is_bool($value)) {
        return $value ? 'true' : 'false';
    }
    
    # Handle refs (objects, arrays)
    if (ref $value) {
        return encode_json($value);
    }
    
    # Scalars (strings, numbers)
    return "$value";
}

# High-level runner

sub run_eval {
    my ($client, $script) = @_;
    my $session_id = $client->session_id;
    
    my $result = $client->post(
        "/session/$session_id/execute/sync",
        {
            script => wrap_script($script),
            args   => [],
        }
    );
    
    return format_result($result);
}

1;
