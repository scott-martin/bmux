package Bmux::Args;
use strict;
use warnings;

# Verbs that take a sub-action as second arg
my %COMPOUND_VERBS = map { $_ => 1 } qw(session tab);

# Verbs that take a value after the object (selector + value)
my %VALUE_VERBS = map { $_ => 1 } qw(fill type style select);

# Known flags
my %SHORT_FLAGS = map { $_ => 1 } qw(p s);
my %LONG_FLAGS  = map { $_ => 1 } qw(session follow matched);

sub parse {
    my (@argv) = @_;

    my %result;
    my @positional;

    # Extract flags first
    my %opts;
    my @rest;
    for my $arg (@argv) {
        if ($arg =~ /^--(\w+)$/) {
            $opts{$1} = 1;
        } elsif ($arg =~ /^-(\w)$/) {
            # Short flag — could be boolean or take a value
            $opts{$1} = 1;
            push @rest, $arg if !$SHORT_FLAGS{$1}; # unknown flag, keep as positional
            next;
        } else {
            push @rest, $arg;
        }
    }

    # Handle -s specially: next positional is its value if compound verb
    # Re-scan for -s with value
    %opts = ();
    @rest = ();
    my $i = 0;
    while ($i < @argv) {
        my $arg = $argv[$i];
        if ($arg =~ /^--(\w+)$/) {
            $opts{$1} = 1;
        } elsif ($arg eq '-p') {
            $opts{p} = 1;
        } elsif ($arg eq '-s' && $i + 1 < @argv) {
            $opts{s} = $argv[$i + 1];
            $i += 2;
            next;
        } elsif ($arg =~ /^-/) {
            # unknown flag, skip
        } else {
            push @rest, $arg;
        }
        $i++;
    }

    # First positional is always the verb
    $result{verb} = shift @rest // return \%result;

    # Compound verbs: second positional is the action
    if ($COMPOUND_VERBS{$result{verb}}) {
        $result{action} = shift @rest;
        _parse_remaining(\%result, \@rest, $result{verb}, $result{action});
    } else {
        _parse_remaining(\%result, \@rest, $result{verb}, undef);
    }

    # Value verbs: last positional is the value (if enough args)
    if ($VALUE_VERBS{$result{verb}} && defined $result{object} && @rest) {
        # Already consumed — handled in _parse_remaining
    }

    $result{opts} = \%opts if %opts;
    return \%result;
}

# Verbs where a bare word (no colon) is always a target, never an object
my %BARE_TARGET_VERBS = map { $_ => 1 } qw(attach cookies);

# Compound verb actions where a bare word is a target
my %BARE_TARGET_ACTIONS = ('tab.new' => 1, 'tab.list' => 1);

sub _parse_remaining {
    my ($result, $rest, $verb, $action) = @_;

    return unless @$rest;

    my $verb_key = defined $action ? "$verb.$action" : ($verb // '');
    my $bare_is_target = $BARE_TARGET_VERBS{$verb // ''}
                      || $BARE_TARGET_ACTIONS{$verb_key};

    # session:tab pattern is unambiguously a target
    if ($rest->[0] =~ /^[a-zA-Z]\w*:\d+$/) {
        $result->{target} = _parse_target(shift @$rest);
    }
    # bare word — target if: verb says so, OR there are more args after
    elsif (_is_target($rest->[0]) && ($bare_is_target || @$rest > 1)) {
        $result->{target} = _parse_target(shift @$rest);
    }

    # Next positional is object
    if (@$rest) {
        $result->{object} = shift @$rest;
    }

    # Next positional is value (for fill, type, style, select)
    if (@$rest) {
        $result->{value} = shift @$rest;
    }
}

# Verbs where a bare word after the verb/action is a target (session name)
my %TARGET_VERBS = map { $_ => 1 } qw(attach tab goto back forward reload
    capture screenshot click fill type check select wait eval
    cookies network console scripts source style storage);

sub _is_target {
    my ($str, $verb) = @_;

    # URLs are not targets
    return 0 if $str =~ m{^https?://};

    # Flags are not targets
    return 0 if $str =~ /^-/;

    # session:tab pattern is always a target
    return 1 if $str =~ /^[a-zA-Z]\w*:\d+$/;

    # bare word is only a target for specific verbs, and only if it
    # looks like a session name (no CSS/JS chars)
    return 0 if $str =~ /[.#\[\]>~+*=]/;

    # For compound verbs (session, tab), bare word after action is a target
    # For other verbs, bare word is ambiguous — only treat as target
    # if followed by more positional args (meaning there's still an object)
    # This is handled by the caller via context
    return 1;
}


sub _parse_target {
    my ($str) = @_;
    my %target;

    if ($str =~ /^([a-zA-Z]\w*):(\d+)$/) {
        $target{session} = $1;
        $target{tab} = int($2);
    } else {
        $target{session} = $str;
    }

    return \%target;
}

1;
