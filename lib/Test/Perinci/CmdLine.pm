package Test::Perinci::CmdLine;

our $DATE = '2014-12-15'; # DATE
our $VERSION = '0.63'; # VERSION

use 5.010;
use strict;
use warnings;

use Capture::Tiny qw(capture);
use Test::More 0.98;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(test_run test_complete);

our $CLASS = "Perinci::CmdLine";

sub test_run {
    my %args = @_;

    my $name = "test_run: " . ($args{name} // join(" ", @{$args{argv} // []}));

    subtest $name => sub {
        no strict 'refs';
        no warnings 'redefine';

        local *{"$CLASS\::hook_after_get_meta"}          = $args{hook_after_get_meta}          if $args{hook_after_get_meta};
        local *{"$CLASS\::hook_before_run"}              = $args{hook_before_run}              if $args{hook_before_run};
        local *{"$CLASS\::hook_before_read_config_file"} = $args{hook_before_read_config_file} if $args{hook_before_read_config_file};
        local *{"$CLASS\::hook_after_parse_argv"}        = $args{hook_after_parse_argv}        if $args{hook_after_parse_argv};
        local *{"$CLASS\::hook_format_result"}           = $args{hook_format_result}           if $args{hook_format_result};
        local *{"$CLASS\::hook_format_row"}              = $args{hook_format_row}              if $args{hook_format_row};
        local *{"$CLASS\::hook_display_result"}          = $args{hook_display_result}          if $args{hook_display_result};
        local *{"$CLASS\::hook_after_run"}               = $args{hook_after_run}               if $args{hook_after_run};

        my %cmdargs = %{$args{args}};
        $cmdargs{exit} = 0;
        $cmdargs{read_config} //= 0;
        my $cmd = $CLASS->new(%cmdargs);

        local @ARGV = @{$args{argv} // []};
        my ($stdout, $stderr);
        my $res;
        eval {
            ($stdout, $stderr) = capture {
                $res = $cmd->run;
            };
        };
        my $eval_err = $@;
        my $exit_code = $res->[3]{'x.perinci.cmdline.base.exit_code'};

        if ($args{dies}) {
            ok($eval_err || ref($eval_err), "dies");
            return;
        } else {
            ok(!$eval_err, "doesn't die") or diag("dies: $eval_err");
        }

        if (defined $args{exit_code}) {
            is($exit_code, $args{exit_code}, "exit code");
        }

        if ($args{status}) {
            is($res->[0], $args{status}, "status")
                or diag explain $res;
        }

        if ($args{output_re}) {
            like($stdout // "", $args{output_re}, "output_re")
                or diag("output is <" . ($stdout // "") . ">");
        }

        if ($args{posttest}) {
            $args{posttest}->(\@ARGV, $stdout, $stderr, $res);
        }
    };
}

sub test_complete {
    my (%args) = @_;

    my $cmd = $CLASS->new(%{$args{args}}, exit=>0);

    local @ARGV = @{$args{argv} // []};

    # $args{comp_line0} contains comp_line with '^' indicating where comp_point
    # should be, the caret will be stripped. this is more convenient than
    # counting comp_point manually.
    my $comp_line  = $args{comp_line0};
    defined ($comp_line) or die "BUG: comp_line0 not defined";
    my $comp_point = index($comp_line, '^');
    $comp_point >= 0 or
        die "BUG: comp_line0 should contain ^ to indicate where comp_point is";
    $comp_line =~ s/\^//;

    local $ENV{COMP_LINE}  = $comp_line;
    local $ENV{COMP_POINT} = $comp_point;

    my ($stdout, $stderr);
    my $res;
    ($stdout, $stderr) = capture {
        $res = $cmd->run;
    };
    my $exit_code = $res->[3]{'x.perinci.cmdline.base.exit_code'};

    my $name = "test_complete: " . ($args{name} // $args{comp_line0});
    subtest $name => sub {
        is($exit_code, 0, "exit code = 0");
        is($stdout // "", join("", map {"$_\n"} @{$args{result}}), "result");
    };
}

1;
# ABSTRACT: Test library for Perinci::CmdLine{,::Lite}

__END__

=pod

=encoding UTF-8

=head1 NAME

Test::Perinci::CmdLine - Test library for Perinci::CmdLine{,::Lite}

=head1 VERSION

This document describes version 0.63 of Test::Perinci::CmdLine (from Perl distribution Perinci-CmdLine-Lite), released on 2014-12-15.

=head1 FUNCTIONS

=head2 test_run(%args)

=head2 test_complete(%args)

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Perinci-CmdLine-Lite>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-Perinci-CmdLine-Lite>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Perinci-CmdLine-Lite>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
