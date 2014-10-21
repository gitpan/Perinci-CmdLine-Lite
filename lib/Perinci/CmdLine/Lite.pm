package Perinci::CmdLine::Lite;

our $DATE = '2014-07-16'; # DATE
our $VERSION = '0.01'; # VERSION

use 5.010001;
# use strict; # already enabled by Mo
# use warnings; # already enabled by Mo

use Mo; extends 'Perinci::CmdLine::Base';

# when debugging, use this instead of the above because Mo doesn't give clear
# error message if base class has errors.
#use parent 'Perinci::CmdLine::Base';

# compared to pericmd, i want to avoid using internal attributes like
# $self->{_format}, $self->{_res}, etc.

sub BUILD {
    my ($self, $args) = @_;

    if (!$self->{actions}) {
        $self->{actions} = {
            call => {},
            version => {},
            subcommands => {},
            help => {},
        };
    }

    if (!$self->{common_opts}) {
        my $co = {
            version => {
                getopt  => 'version|v',
                summary => 'Show program version',
                handler => sub {
                    my ($r, $go, $val) = @_;
                    $r->{action} = 'version';
                    $r->{skip_parse_subcommand_argv} = 1;
                },
            },
            help => {
                getopt  => 'help|h|?',
                summary => 'Show help message',
                handler => sub {
                    my ($r, $go, $val) = @_;
                    $r->{action} = 'help';
                    $r->{skip_parse_subcommand_argv} = 1;
                },
            },
            format => {
                getopt  => 'format=s',
                summary => 'Set output format (text/text-simple/text-pretty/json/json-pretty)',
                handler => sub {
                    my ($r, $go, $val) = @_;
                    $r->{format} = $val;
                },
            },
            json => {
                getopt  => 'json',
                summary => 'Set output format to json',
                handler => sub {
                    my ($r, $go, $val) = @_;
                    $r->{format} = 'json';
                },
            },
        };
        if ($self->subcommands) {
            $co->{subcommands} = {
                getopt  => 'subcommands',
                summary => 'List available subcommands',
                handler => sub {
                    my ($r, $go, $val) = @_;
                    $r->{action} = 'subcommands';
                    $r->{skip_parse_subcommand_argv} = 1;
                },
            };
        }
        if ($self->default_subcommand) {
            $co->{cmd} = {
                getopt  => 'cmd=s',
                summary => 'Select subcommand',
                handler => sub {
                    my ($r, $go, $val) = @_;
                    $r->{subcommand_name} = $val;
                },
            };
        }
        $self->{common_opts} = $co;
    }

    $self->{formats} //= [qw/text text-simple text-pretty json/];
}

sub hook_before_run {}

sub hook_after_parse_argv {}

sub hook_after_select_subcommand {}

sub hook_format_result {
    my ($self, $r) = @_;

    my $res    = $r->{res};
    my $format = $r->{format} // 'text';
    my $meta   = $r->{meta};

    if ($format =~ /\Atext(-simple|-pretty)?\z/) {
        my $is_pretty = $format eq 'text-pretty' ? 1 :
            $format eq 'text-simple' ? 0 : (-t STDOUT);
        no warnings 'uninitialized';
        if ($res->[0] != 200) {
            return "ERROR $res->[0]: $res->[1]\n";
        } else {
            require Data::Check::Structure;
            my $data = $res->[2];
            my $max = 5;
            if (!ref($data)) {
                $data //= "";
                $data .= "\n" unless $data =~ /\n\z/;
                return $data;
            } elsif (Data::Check::Structure::is_aos($data, {max=>$max})) {
                if ($is_pretty) {
                    require Text::Table::Tiny;
                    $data = [map {[$_]} @$data];
                    return Text::Table::Tiny::table(rows=>$data) . "\n";
                } else {
                    return join("", map {"$_\n"} @$data);
                }
            } elsif (Data::Check::Structure::is_aoaos($data, {max=>$max})) {
                if ($is_pretty) {
                    require Text::Table::Tiny;
                    return Text::Table::Tiny::table(rows=>$data) . "\n";
                } else {
                    return join("", map {join("\t", @$_)."\n"} @$data);
                }
            } elsif (Data::Check::Structure::is_hos($data, {max=>$max})) {
                if ($is_pretty) {
                    require Text::Table::Tiny;
                    $data = [map {[$_, $data->{$_}]} sort keys %$data];
                    unshift @$data, ["key", "value"];
                    return Text::Table::Tiny::table(rows=>$data) . "\n";
                } else {
                    return join("", map {"$_\t$data->{$_}\n"} sort keys %$data);
                }
            } elsif (Data::Check::Structure::is_aohos($data, {max=>$max})) {
                # collect all mentioned fields
                my %fieldnames;
                for my $row (@$data) {
                    $fieldnames{$_}++ for keys %$row;
                }
                my @fieldnames = sort keys %fieldnames;
                my $newdata = [];
                for my $row (@$data) {
                    push @$newdata, [map {$row->{$_}} @fieldnames];
                }
                if ($is_pretty) {
                    unshift @$newdata, \@fieldnames;
                    require Text::Table::Tiny;
                    return Text::Table::Tiny::table(rows=>$newdata) . "\n";
                } else {
                    return join("", map {join("\t", @$_)."\n"} @$newdata);
                }
            } else {
                $format = 'json-pretty';
            }
        }
    }

    warn "Unknown format '$format', fallback to json-pretty"
        unless $format =~ /\Ajson(-pretty)?\z/;
    state $cleanser = do {
        require Data::Clean::JSON;
        Data::Clean::JSON->get_cleanser;
    };
    $cleanser->clean_in_place($res);
    state $json = do {
        require JSON;
        JSON->new->allow_nonref;
    };
    if ($format eq 'json') {
        return $json->encode($res);
    } else {
        return $json->pretty->encode($res);
    }
}

sub hook_display_result {
    my ($self, $r) = @_;
    print $r->{fres};
}

sub hook_after_run {}

sub __require_url {
    my ($url) = @_;

    $url =~ m!\A(?:pl:)?/(\w+(?:/\w+)*)/(\w*)\z!
        or die [500, "Unsupported/bad URL '$url'"];
    my ($mod, $func) = ($1, $2);
    require "$mod.pm";
    $mod =~ s!/!::!g;
    ($mod, $func);
}

sub get_meta {
    my ($self, $url) = @_;

    my ($mod, $func) = __require_url($url);

    my $meta;
    {
        no strict 'refs';
        if (length $func) {
            $meta = ${"$mod\::SPEC"}{$func}
                or die [500, "No metadata for '$url'"];
        } else {
            $meta = ${"$mod\::SPEC"}{':package'} // {v=>1.1};
        }
        $meta->{entity_v}    //= ${"$mod\::VERSION"};
        $meta->{entity_date} //= ${"$mod\::DATE"};
    }

    require Perinci::Sub::Normalize;
    $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);

    require Perinci::Object;
    if (Perinci::Object::risub($meta)->can_dry_run) {
        $self->common_opts->{dry_run} = {
            getopt  => 'dry-run',
            summary => "Run in simulation mode (also via DRY_RUN=1)",
            handler => sub {
                my ($r, $go, $val) = @_;
                $r->{dry_run} = 1;
                #$ENV{VERBOSE} = 1;
            },
        };
    }

    $meta;
}

sub run_subcommands {
    my ($self, $r) = @_;

    if (!$self->subcommands) {
        say "There are no subcommands.";
        return 0;
    }

    say "Available subcommands:";
    my $subcommands = $self->list_subcommands;
    [200, "OK",
     join("",
          (map { "  $_->{name} $_->{url}" } @$subcommands),
      )];
}

sub run_version {
    my ($self, $r) = @_;

    my $meta = $r->{meta};

    [200, "OK",
     join("",
          $self->get_program_and_subcommand_name($r),
          " version ", ($meta->{entity_v} // "?"),
          ($meta->{entity_date} ? " ($meta->{entity_date})" : ''),
          "\n",
          "  ", __PACKAGE__,
          " version ", ($Perinci::CmdLine::Lite::VERSION // "?"),
          ($Perinci::CmdLine::Lite::DATE ? " ($Perinci::CmdLine::Lite::DATE)":''),
      )];
}

sub run_help {
    my ($self) = @_;

    [200, "OK", "Help message"];
}

sub run_call {
    my ($self, $r) = @_;

    my $scd = $r->{subcommand_data};
    my ($mod, $func) = __require_url($scd->{url});

    no strict 'refs';
    &{"$mod\::$func"}(%{ $r->{args} });
}

1;
# ABSTRACT: A lightweight Rinci/Riap-based command-line application framework

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::CmdLine::Lite - A lightweight Rinci/Riap-based command-line application framework

=head1 VERSION

This document describes version 0.01 of Perinci::CmdLine::Lite (from Perl distribution Perinci-CmdLine-Lite), released on 2014-07-16.

=head1 SYNOPSIS

See L<Perinci::CmdLine::Manual::Examples>.

=head1 DESCRIPTION

B<NOTE: This module is still experimental. Early release, completion not yet
implemented.>

Perinci::CmdLine::Lite (hereby P::C::Lite) is a lightweight (low startup
overhead, minimal dependencies) alternative to L<Perinci::CmdLine> (hereby
P::C). It offers a subset of functionality and a compatible API. Unless you use
the unsupported features of P::C, P::C::Lite is a drop-in replacement for P::C
(also see L<Perinci::CmdLine::Any> for automatic fallback).

The main difference is that, to keep dependencies minimal and startup overhead
small, P::C::Lite does not access code and metadata through the L<Riap> client
library L<Perinci::Access> layer, but instead accesses Perl modules/packages
directly.

Below is summary of the differences between P::C::Lite and P::C:

=over

=item * No remote URL support

Only code in Perl packages on the filesystem is available.

=item * No automatic validation from schema

As code wrapping and schema code generation by L<Data::Sah> currently adds some
startup overhead.

=item * P::C::Lite starts much faster

The target is under 0.05s, while P::C can start between 0.2-0.5s.

=item * P::C::Lite does not support color themes

=item * P::C::Lite does not support undo

=item * P::C::Lite does not currently support logging

Something more lightweight than L<Log::Any::App> will be considered. If you want
to view logging and your function uses L<Log::Any>, you can do something like
this:

 % DEBUG=1 PERL5OPT=-MLog::Any::App app.pl

=item * P::C::Lite does not support progress indicator

=item * P::C::Lite does not support I18N

=item * P::C::Lite does not yet support these Rinci function metadata properties

 x.perinci.cmdline.default_format

=item * P::C::Lite does not yet support these Rinci function argument specification properties

 cmdline_src

=item * P::C::Lite does not yet support these Rinci result metadata properties/attributes

 is_stream
 cmdline.display_result
 cmdline.page_result
 cmdline.pager

=item * P::C::Lite uses simpler formatting

Instead of L<Perinci::Result::Format> (especially the 'text' formats which use
L<Data::Format::Pretty::Console> and L<Text::ANSITable>), to keep dependencies
minimal and formatting quick, P::C::Lite uses the following simple rules that
work for a significant portion of common data structures:

1) if result is undef, print nothing.

2) if result is scalar, print it (with newline automatically added).

3) if result is an array of scalars (check at most 5 first rows), print it one
line for each element.

4) if result is a hash of scalars (check at most 5 keys), print a two column
table, first column is key and second column is value. Keys will be sorted.

5) if result is an array of hashes of scalars (check at most 5 elements), print
as table.

6) if result is an array of arrays of scalars (check at most 5 elements), print
as table.

7) otherwise print as JSON (after cleaning it with L<Data::Clean::JSON>).

YAML and the other formats are not supported.

Table is printed using the more lightweight and much faster
L<Text::Table::Tiny>.

=item * P::C::Lite does not yet support these environment variables

 PERINCI_CMDLINE_COLOR_THEME
 PERINCI_CMDLINE_SERVER
 PROGRESS
 PAGER
 COLOR
 UTF8

 DEBUG, VERBOSE, QUIET, TRACE, and so on

=item * In passing command-line object to functions, P::C::Lite object is passed

Some functions might expect a L<Perinci::CmdLine> instance.

=back

=for Pod::Coverage ^(hook_.+|)$

=head1 ENVIRONMENT

=over

=item * PERINCI_CMDLINE_PROGRAM_NAME => STR

Can be used to set CLI program name.

=back

=head1 SEE ALSO

L<Perinci::CmdLine>, L<Perinci::CmdLine::Manual>

L<Perinci::CmdLine::Any>

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

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
