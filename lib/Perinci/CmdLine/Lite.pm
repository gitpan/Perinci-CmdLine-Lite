package Perinci::CmdLine::Lite;

our $DATE = '2014-11-09'; # DATE
our $VERSION = '0.46'; # VERSION

use 5.010001;
# use strict; # already enabled by Mo
# use warnings; # already enabled by Mo

use Mo qw(build default);
#use Moo;
extends 'Perinci::CmdLine::Base';

# when debugging, use this instead of the above because Mo doesn't give clear
# error message if base class has errors.
#use parent 'Perinci::CmdLine::Base';

has default_prompt_template => (
    is=>'rw',
    default => 'Enter %s: ',
);
has log => (
    is=>'rw',
    default => sub {
        if (defined $ENV{LOG}) {
            return $ENV{LOG};
        } elsif ($ENV{LOG_LEVEL} && $ENV{LOG_LEVEL} =~ /^(off|none)$/) {
            return 0;
        } elsif ($ENV{LOG_LEVEL} || $ENV{TRACE} || $ENV{DEBUG} ||
                     $ENV{VERBOSE} || $ENV{QUIET}) {
            return 0;
        }
        0;
    },
);
has log_level => (
    is=>'rw',
    default => sub {
        if ($ENV{LOG_LEVEL}) {
            return $ENV{LOG_LEVEL};
        } elsif ($ENV{TRACE}) {
            return 'trace';
        } elsif ($ENV{DEBUG}) {
            return 'debug';
        } elsif ($ENV{VERBOSE}) {
            return 'info';
        } elsif ($ENV{QUIET}) {
            return 'error';
        }
        'warning';
    },
);

my $formats = [qw/text text-simple text-pretty json json-pretty/];

sub BUILD {
    my ($self, $args) = @_;

    if (!$self->{riap_client}) {
        require Perinci::Access::Lite;
        my %rcargs = (
            riap_version => $self->{riap_version} // 1.1,
            %{ $self->{riap_client_args} // {} },
        );
        $self->{riap_client} = Perinci::Access::Lite->new(%rcargs);
    }

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
                    my ($go, $val, $r) = @_;
                    $r->{action} = 'version';
                    $r->{skip_parse_subcommand_argv} = 1;
                },
            },
            help => {
                getopt  => 'help|h|?',
                summary => 'Show help message',
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{action} = 'help';
                    $r->{skip_parse_subcommand_argv} = 1;
                },
            },
            format => {
                getopt  => 'format=s',
                summary => 'Set output format',
                schema => ['str*' => in => $formats],
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{format} = $val;
                },
            },
            json => {
                getopt  => 'json',
                summary => 'Set output format to json',
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{format} = 'json';
                },
            },
        };
        if ($self->subcommands) {
            $co->{subcommands} = {
                getopt  => 'subcommands',
                summary => 'List available subcommands',
                handler => sub {
                    my ($go, $val, $r) = @_;
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
                    my ($go, $val, $r) = @_;
                    $r->{subcommand_name} = $val;
                    $r->{subcommand_name_from} = '--cmd';
                },
                completion => sub {
                    require Complete::Util;
                    my %args = @_;
                    Complete::Util::complete_array_elem(
                        array => [keys %{ $self->list_subcommands }],
                        word => $args{word});
                },
            };
        }
        if ($self->read_config) {
            $co->{config_path} = {
                getopt  => 'config-path=s@',
                summary => 'Set path to configuration file',
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{config_paths} //= [];
                    push @{ $r->{config_paths} }, $val;
                },
            };
            $co->{no_config} = {
                getopt  => 'noconfig|no-config',
                summary => 'Do not use any configuration file',
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{read_config} = 0;
                },
            };
            $co->{config_profile} = {
                getopt  => 'config-profile=s',
                summary => 'Set configuration profile to use',
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{config_profile} = $val;
                },
            };
        }
        if ($self->log) {
            $co->{log_level} = {
                getopt  => 'log-level=s',
                summary => 'Set log level',
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{log_level} = $val;
                },
            };
            $co->{trace} = {
                getopt  => 'trace',
                summary => "Set log level to 'trace'",
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{log_level} = 'trace';
                },
            };
            $co->{debug} = {
                getopt  => 'debug',
                summary => "Set log level to 'debug'",
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{log_level} = 'debug';
                },
            };
            $co->{verbose} = {
                getopt  => 'verbose',
                summary => "Set log level to 'info'",
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{log_level} = 'info';
                },
            };
            $co->{quiet} = {
                getopt  => 'quiet',
                summary => "Set log level to 'error'",
                handler => sub {
                    my ($go, $val, $r) = @_;
                    $r->{log_level} = 'error';
                },
            };
        }
        $self->{common_opts} = $co;
    }

    $self->{formats} //= $formats;

    $self->{per_arg_json} //= 1;
}

sub hook_before_run {}

sub hook_after_parse_argv {
    my ($self, $r) = @_;

    # since unlike Perinci::CmdLine, we don't wrap the function (where the
    # wrapper assigns default values for arguments), we must do it here
    # ourselves.
    my $ass  = $r->{meta}{args} // {};
    my $args = $r->{args};
    for (keys %$ass) {
        next if exists $args->{$_};
        my $as = $ass->{$_};
        if (exists $as->{default}) {
            $args->{$_} = $as->{default};
        } elsif ($as->{schema} && exists $as->{schema}[1]{default}) {
            $args->{$_} = $as->{schema}[1]{default};
        }
    }

    # set up log adapter
    if ($self->log) {
        require Log::Any::Adapter;
        Log::Any::Adapter->set(
            'ScreenColoredLevel',
            min_level => $r->{log_level} // $self->log_level,
            formatter => sub { $self->program_name . ": $_[1]" },
        );
    }
}

sub hook_format_result {
    my ($self, $r) = @_;

    my $res    = $r->{res};
    my $format = $r->{format} // 'text';
    my $meta   = $r->{meta};

    if ($format =~ /\Atext(-simple|-pretty)?\z/) {
        my $is_pretty = $format eq 'text-pretty' ? 1 :
            $format eq 'text-simple' ? 0 : (-t STDOUT);
        no warnings 'uninitialized';
        if ($res->[0] !~ /^2/) {
            my $fres = "ERROR $res->[0]: $res->[1]";
            if (my $prev = $res->[3]{prev}) {
                $fres .= " ($prev->[0]: $prev->[1])";
            }
            return "$fres\n";
        } elsif ($res->[3] && $res->[3]{"x.hint.result_binary"}) {
            return $res->[2];
        } else {
            require Data::Check::Structure;
            my $data = $res->[2];
            my $max = 5;
            if (!ref($data)) {
                $data //= "";
                $data .= "\n" unless !length($data) || $data =~ /\n\z/;
                return $data;
            } elsif (ref($data) eq 'ARRAY' && !@$data) {
                return "";
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
        return $json->encode($res) . "\n";
    } else {
        return $json->pretty->encode($res);
    }
}

sub hook_format_row {
    my ($self, $r, $row) = @_;

    if (ref($row) eq 'ARRAY') {
        return join("\t", @$row) . "\n";
    } else {
        return ($row // "") . "\n";
    }
}

sub hook_display_result {
    my ($self, $r) = @_;
    $self->display_result($r);
}

sub hook_after_run {}

sub hook_after_get_meta {
    my ($self, $r) = @_;

    require Perinci::Object;
    if (Perinci::Object::risub($r->{meta})->can_dry_run) {
        $self->common_opts->{dry_run} = {
            getopt  => 'dry-run',
            summary => "Run in simulation mode (also via DRY_RUN=1)",
            handler => sub {
                my ($go, $val, $r) = @_;
                $r->{dry_run} = 1;
                #$ENV{VERBOSE} = 1;
            },
        };
    }
}

sub run_subcommands {
    my ($self, $r) = @_;

    if (!$self->subcommands) {
        say "There are no subcommands.";
        return 0;
    }

    say "Available subcommands:";
    my $scs = $self->list_subcommands;
    my $longest = 6;
    for (keys %$scs) { my $l = length; $longest = $l if $l > $longest }
    [200, "OK",
     join("",
          (map { sprintf("  %-${longest}s  %s\n",$_,$scs->{$_}{summary}//"") }
               sort keys %$scs),
      )];
}

sub run_version {
    my ($self, $r) = @_;

    my $meta = $r->{meta} = $self->get_meta($r, $self->url);

    [200, "OK",
     join("",
          $self->get_program_and_subcommand_name($r),
          " version ", ($meta->{entity_v} // "?"),
          ($meta->{entity_date} ? " ($meta->{entity_date})" : ''),
          "\n",
          "  ", __PACKAGE__,
          " version ", ($Perinci::CmdLine::Lite::VERSION // "?"),
          ($Perinci::CmdLine::Lite::DATE ?
               " ($Perinci::CmdLine::Lite::DATE)":''),
      )];
}

sub run_help {
    my ($self, $r) = @_;

    my @help;
    my $scn    = $r->{subcommand_name};
    my $scd    = $r->{subcommand_data};
    my $meta   = $self->get_meta($r, $scd->{url} // $self->{url});
    my $args_p = $meta->{args} // {};

    # summary
    my $cmdname = $self->get_program_and_subcommand_name($r);
    push @help, $cmdname;
    {
        my $sum = ($scd ? $scd->{summary} : undef) //
            $meta->{summary};
        last unless $sum;
        push @help, " - ", $sum, "\n";
    }

    # usage
    push @help, "\n";
    push @help, "Usage:\n";
    {
        # we have subcommands but user has not specified any to choose
        my $has_sc_no_sc = $self->subcommands && !length($r->{subcommand_name});

        push @help, "  $cmdname --help (or -h, -?)\n";
        push @help, "  $cmdname --version (or -v)\n";
        push @help, "  $cmdname --subcommands\n" if $has_sc_no_sc;

        unless ($has_sc_no_sc) {
            my @args;
            my %args = %{ $args_p };
            my $max_pos = -1;
            for (values %args) {
                $max_pos = $_->{pos}
                    if defined($_->{pos}) && $_->{pos} > $max_pos;
            }
            my $pos = 0;
            while ($pos <= $max_pos) {
                my ($arg, $as);
                for (keys %args) {
                    $as = $args{$_};
                    if (defined($as->{pos}) && $as->{pos}==$pos) {
                        $arg=$_;
                        last;
                    }
                }
                next unless defined($arg);
                if ($as->{req}) {
                    push @args, "<$arg>" . ($as->{greedy} ? " ...":"");
                } else {
                    push @args, "[$arg]" . ($as->{greedy} ? " ...":"");
                }
                delete $args{$arg};
                $pos++;
            }
            unshift @args, "[options]" if keys %args;
            push @help, "  $cmdname ".join(" ", @args)."\n";
        }
    }

    # description
    {
        my $desc = ($scd ? $scd->{description} : undef) //
            $meta->{description};
        last unless $desc;
        push @help, "\n";
        $desc =~ s/\A\n+//;
        $desc =~ s/\n+\z//;
        push @help, $desc, "\n";
    }

    # options
    {
        require Perinci::Sub::GetArgs::Argv;
        my $co = $self->common_opts;
        my $co_by_ospec = { map {$co->{$_}{getopt} => $_ } keys %$co };
        my $res = Perinci::Sub::GetArgs::Argv::gen_getopt_long_spec_from_meta(
            meta         => $meta,
            common_opts  => $co,
            per_arg_json => $self->{per_arg_json},
            per_arg_yaml => $self->{per_arg_yaml},
        );
        my $sms = $res->[3]{'func.specmeta'};

        # first, all common options first
        my @opts;
        for my $k (sort(grep {!defined($sms->{$_}{arg})} keys %$sms)) {
            my $p = $sms->{$k}{parsed};
            # XXX currently ad-hoc, skip irrelevant common opt
            next if $scn && $k eq 'subcommands';
            my $i = 0;
            my $opt = '';
            for (@{ $p->{opts} }) {
                $i++;
                $opt .= ", " if $i > 1;
                $opt .= (length($_) > 1 ? '--':'-').$_;
                $opt .= "=$p->{type}" if $p->{type} && $i==1;
            }
            push @opts, [$opt, $co->{$co_by_ospec->{$k}}{summary}];
        }
        my $longest = 6;
        for (@opts) { my $l = length($_->[0]); $longest = $l if $l > $longest }
        push @help, "\nCommon options:\n" if @opts;
        for (@opts) {
            push @help, sprintf("  %-${longest}s  %s\n",
                                $_->[0], $_->[1] // "");
        }

        # now the rest
        @opts = ();
        for my $k (sort(grep {defined($sms->{$_}{arg})} keys %$sms)) {
            my $sm = $sms->{$k};
            # skip non-code aliases
            next if $sm->{is_alias} && !$sm->{is_code};
            my $p = $sm->{parsed};
            my $i = 0;
            my $opt = '';
            for (@{ $p->{opts} }) {
                $i++;
                $opt .= ", " if $i > 1;
                $opt .= (length($_) > 1 ? '--':'-').$_;
                $opt .= "=$p->{type}" if $p->{type} && $i==1;
            }
            # add non-code aliases
            for my $al (@{ $sm->{noncode_aliases} // [] }) {
                $al =~ s/=.+//; $al = (length($al) > 1 ? "--":"-").$al;
                $opt .= ", $al";
            }
            my $arg = $sm->{arg};
            my $as = $args_p->{$arg};
            my $alspec = $sm->{alias} ?
                $as->{cmdline_aliases}{$sm->{alias}} : {};
            my $sum = join(
                "",
                (defined($as->{pos}) ? "(or via arg #$as->{pos}".
                     ($as->{greedy} ? "+":"").") " : ""),
                ($sm->{alias_for} ? $alspec->{summary} //
                     "Alias for $sm->{alias_for}" : $as->{summary} // ''),
                ($as->{cmdline_src} ? " ($as->{cmdline_src})" : ""),
            );
            my $sch = ($sm->{is_alias} ?
                           $as->{cmdline_aliases}{$sm->{alias}}{schema} :
                               undef) // $as->{schema};
            if ($sch && $sch->[1]{in}) {
                $sum .= " (".join("|", @{ $sch->[1]{in} }).")";
            }
            push @opts, [$opt, $sum];
        }
        for (@opts) { my $l = length($_->[0]); $longest = $l if $l > $longest }
        push @help, "\nOptions:\n" if @opts;
        for (@opts) {
            push @help, sprintf("  %-${longest}s  %s\n",
                                $_->[0], $_->[1] // "");
        }
        push @help, "\n" if @opts;
    }

    [200, "OK", join("", @help), {"cmdline.skip_format"=>1}];
}

sub run_call {
    my ($self, $r) = @_;

    my %extra;
    if ($r->{send_argv}) {
        $extra{argv} = $r->{orig_argv};
    } else {
        $extra{args} = $r->{args};
    }

    $extra{stream_arg} = 1 if $r->{stream_arg};

    $self->riap_client->request(
        call => $r->{subcommand_data}{url}, \%extra);
}

1;
# ABSTRACT: A lightweight Rinci/Riap-based command-line application framework

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::CmdLine::Lite - A lightweight Rinci/Riap-based command-line application framework

=head1 VERSION

This document describes version 0.46 of Perinci::CmdLine::Lite (from Perl distribution Perinci-CmdLine-Lite), released on 2014-11-09.

=head1 SYNOPSIS

See L<Perinci::CmdLine::Manual::Examples>.

=head1 DESCRIPTION

Perinci::CmdLine::Lite (hereby P::C::Lite) is a lightweight (low startup
overhead, minimal dependencies) alternative to L<Perinci::CmdLine> (hereby
P::C). It offers a subset of functionality and a compatible API. Unless you use
the unsupported features of P::C, P::C::Lite is a drop-in replacement for P::C
(also see L<Perinci::CmdLine::Any> for automatic fallback).

P::C::Lite stays lightweight by avoiding the use of libraries that have large
dependencies or add too much to startup overhead. This includes
L<Perinci::Access> for metadata access, L<Data::Sah> for validator generation,
L<Text::ANSITable> for formatting results, and L<Log::Any::App> (which uses
L<Log::Log4perl>) for logging.

P::C::Lite attributes default to condition of low startup overhead. For example,
C<log> is by default off instead of on like in P::C.

I first developed P::C::Lite mainly for CLI applications that utilize shell tab
completion as their main feature, e.g. L<App::PMUtils>, L<App::ProgUtils>,
L<App::GitUtils>.

Below is summary of the differences between P::C::Lite and P::C:

=over

=item * P::C::Lite starts much faster

The target is under 0.04-0.05s to make shell tab completion convenient. On the
other hand, P::C can start between 0.20-0.50s.

=item * P::C::Lite uses simpler formatting

Instead of L<Perinci::Result::Format> (especially for 'text*' formats which use
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

=item * No support for some protocols

Instead of L<Perinci::Access>, this module uses the more lightweight alternative
L<Perinci::Access::Lite> which does not support some URL schemes (http/https and
local are supported though).

=item * No automatic validation from schema in P::C::Lite

Since code wrapping and schema code generation done by L<Perinci::Sub::Wrapper>
and L<Data::Sah> (which are called automatically by Perinci::Access, but not by
Perinci::Access::Lite) adds too much startup overhead.

=item * P::C::Lite does not support color themes

=item * P::C::Lite does not support undo

=item * P::C::Lite currently has simpler logging

Only logging to screen is supported, using
L<Log::Any::Adapter::ScreenColoredLevel>.

=item * P::C::Lite does not support progress indicator

=item * P::C::Lite does not support I18N

=item * P::C::Lite does not yet support these environment variables

 PERINCI_CMDLINE_COLOR_THEME
 PERINCI_CMDLINE_SERVER
 PROGRESS
 COLOR
 UTF8

=item * In passing command-line object to functions, P::C::Lite object is passed

Some functions might expect a L<Perinci::CmdLine> instance.

=back

=for Pod::Coverage ^(BUILD|get_meta|hook_.+|run_.+)$

=head1 ATTRIBUTES

All the attributes of L<Perinci::CmdLine::Base>, plus:

=head2 log => bool (default: 0, or from env)

Whether to enable logging. This currently means setting up L<Log::Any::Adapter>
to display logging (set in C<hook_after_parse_argv>, so tab completion skips
this step). To produce log, you use L<Log::Any> in your code.

The default is off. If you set LOG=1 or LOG_LEVEL or TRACE/DEBUG/VERBOSE/QUIET,
then the default will be on. It defaults to off if you set LOG=0 or
LOG_LEVEL=off.

=head2 log_level => str (default: warning, or from env)

Set default log level. The default can also be set via
LOG_LEVEL/TRACE/DEBUG/VERBOSE/QUIET.

=head1 METHODS

All the methods of L<Perinci::CmdLine::Base>, plus:

=head1 ENVIRONMENT

All the environment variables that L<Perinci::CmdLine::Base> supports, plus:

=head2 DEBUG

Set log level to 'debug'.

=head2 VERBOSE

Set log level to 'info'.

=head2 QUIET

Set log level to 'error'.

=head2 TRACE

Set log level to 'trace'.

=head2 LOG_LEVEL

Set log level.

=head1 RESULT METADATA

All those supported by L<Perinci::CmdLine::Base>, plus:

=head2 x.hint.result_binary => bool

If set to true, then when formatting to C<text> formats, this class won't print
any newline to keep the data being printed unmodified.

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

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
