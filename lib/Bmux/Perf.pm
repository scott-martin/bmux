package Bmux::Perf;
use strict;
use warnings;
use JSON::PP;
use File::Path qw(make_path);

my %BYTE_METRICS = map { $_ => 1 } qw(
    JSHeapUsedSize JSHeapTotalSize
);

sub is_byte_metric { $BYTE_METRICS{$_[0]} // 0 }

sub format_bytes {
    my ($n) = @_;
    return '0 B' unless $n;
    my @units = ('B', 'KB', 'MB', 'GB');
    my $i = 0;
    my $val = $n;
    while ($val >= 1024 && $i < $#units) {
        $val /= 1024;
        $i++;
    }
    return $i == 0 ? "$n B" : sprintf("%.1f %s", $val, $units[$i]);
}

sub extract_metric {
    my ($metrics, $name) = @_;
    for my $m (@$metrics) {
        return $m->{value} if $m->{name} eq $name;
    }
    return undef;
}

sub format_snapshot {
    my ($metrics) = @_;
    my $out = '';
    for my $m (@$metrics) {
        my $val = is_byte_metric($m->{name})
            ? format_bytes($m->{value})
            : $m->{value};
        $out .= sprintf("%-30s %s\n", $m->{name}, $val);
    }
    return $out;
}

sub diff_metrics {
    my ($before, $after) = @_;
    my %before_map = map { $_->{name} => $_->{value} } @$before;
    my %after_map  = map { $_->{name} => $_->{value} } @$after;

    my @names;
    my %seen;
    for my $m (@$before, @$after) {
        push @names, $m->{name} unless $seen{$m->{name}}++;
    }

    return [ map {
        my $b = $before_map{$_} // 0;
        my $a = $after_map{$_}  // 0;
        { name => $_, before => $b, after => $a, delta => $a - $b };
    } @names ];
}

sub format_diff {
    my ($diff) = @_;
    my $out = sprintf("%-30s %15s %15s %15s\n", 'Metric', 'Before', 'After', 'Delta');
    $out .= '-' x 77 . "\n";
    for my $d (@$diff) {
        my $is_bytes = is_byte_metric($d->{name});
        my $before = $is_bytes ? format_bytes($d->{before}) : $d->{before};
        my $after  = $is_bytes ? format_bytes($d->{after})  : $d->{after};
        my $delta;
        if ($is_bytes) {
            my $sign = $d->{delta} > 0 ? '+' : '';
            $delta = $sign . format_bytes(abs($d->{delta}));
            $delta = '-' . format_bytes(abs($d->{delta})) if $d->{delta} < 0;
        } else {
            $delta = $d->{delta} > 0 ? "+$d->{delta}" : "$d->{delta}";
        }
        $out .= sprintf("%-30s %15s %15s %15s\n", $d->{name}, $before, $after, $delta);
    }
    return $out;
}

# --- Baseline storage ---

sub _perf_dir {
    my ($base_dir) = @_;
    $base_dir //= $ENV{PWD};
    return "$base_dir/perf";
}

sub save_baseline {
    my ($name, $metrics, $base_dir) = @_;
    my $dir = _perf_dir($base_dir);
    make_path($dir) unless -d $dir;
    my $file = "$dir/$name.json";
    open my $fh, '>', $file or die "Cannot write $file: $!\n";
    print $fh encode_json($metrics);
    close $fh;
}

sub load_baseline {
    my ($name, $base_dir) = @_;
    my $file = _perf_dir($base_dir) . "/$name.json";
    return undef unless -f $file;
    open my $fh, '<', $file or die "Cannot read $file: $!\n";
    local $/;
    my $json = <$fh>;
    close $fh;
    return decode_json($json);
}

sub list_baselines {
    my ($base_dir) = @_;
    my $dir = _perf_dir($base_dir);
    return () unless -d $dir;
    opendir my $dh, $dir or die "Cannot read $dir: $!\n";
    my @names = map { s/\.json$//r } grep { /\.json$/ } readdir $dh;
    closedir $dh;
    return sort @names;
}

sub delete_baseline {
    my ($name, $base_dir) = @_;
    my $file = _perf_dir($base_dir) . "/$name.json";
    unlink $file or die "Cannot delete $file: $!\n";
}

1;
