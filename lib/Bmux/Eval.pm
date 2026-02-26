package Bmux::Eval;
use strict;
use warnings;
use JSON::PP;

# Build Runtime.evaluate command
sub cmd_evaluate {
    my ($cdp, $expression) = @_;
    return $cdp->build_command('Runtime.evaluate', {
        expression    => $expression,
        returnByValue => JSON::PP::true,
    });
}

# Format a Runtime.evaluate result for display
sub format_result {
    my ($result) = @_;

    # Check for exception
    if (my $ex = $result->{exceptionDetails}) {
        my $desc = $ex->{exception}{description}
                // $ex->{text}
                // 'Unknown error';
        return "Error: $desc";
    }

    my $r = $result->{result} // return 'undefined';

    # Null
    if (($r->{subtype} // '') eq 'null') {
        return 'null';
    }

    # Has a value
    if (exists $r->{value}) {
        if (ref $r->{value}) {
            return encode_json($r->{value});
        }
        return defined $r->{value} ? "$r->{value}" : 'null';
    }

    # No value — return type description
    return $r->{description} // $r->{type} // 'undefined';
}

1;
