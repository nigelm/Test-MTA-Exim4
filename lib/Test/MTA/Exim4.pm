package Test::MTA::Exim4;

use warnings;
use strict;
use base qw(Class::Accessor::Fast);
use IPC::Cmd qw[can_run run];
use Test::Builder;
use Data::Dumper;

__PACKAGE__->mk_accessors(qw[ debug]);
__PACKAGE__->mk_ro_accessors(qw[exim_path config_file test timeout]);

=head1 NAME

Test::MTA::Exim4 - Test Anything interface for testing Exim4 configurations

=head1 VERSION

Version 0.01

=cut

use vars qw[$VERSION];
our $VERSION = '0.01';

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Test::MTA::Exim4;

    my $foo = Test::MTA::Exim4->new();
    ...

=head1 METHODS

=head2 new

    my $exim = Test::MTA::Exim4->new( \%fields );

Create a new exim configuration testing object. You may pass
configuration information in as a hash reference - this is the only
point at which the locations of the exim binary and configuration file
may be set.

=cut

sub new {
    my ( $proto, $fields ) = @_;
    my ($class) = ref $proto || $proto;

    # copy fields into self (without checking) and bless
    my $self = defined($fields) ? { %{$fields} } : {};
    bless( $self, $class );

    # set some defaults if not already in place
    $self->{exim_path} ||=
         $ENV{DEFAULT_EXIM_PATH}
      || can_run('exim4')
      || can_run('exim')
      || '/usr/sbin/exim';
    $self->{config_file} ||= $ENV{DEFAULT_EXIM_CONFIG_FILE};
    $self->{test}        ||= Test::Builder->new;
    $self->{timeout}     ||= 5;

    # check that underlying IPC::Cmd has sufficient capabilities
    IPC::Cmd->can_capture_buffer
      || $self->_croak(
        'IPC::Cmd cannot capture buffers on this system - testing will fail');

    # check that exim is there and runnable
    can_run( $self->{exim_path} )
      || $self->_croak('No runnable exim binary found');

    # reset internal state
    $self->reset;

    return $self;
}

=head2 reset

Resets the internal state.  Not sure when this might be useful!

=cut

sub reset {
    my $self = shift;

    $self->{_state} = { config => {} };

    return $self;
}

=head2 config_ok 

Checks that C<exim> considers the configuration file as syntactically
valid. The config file must be specified when C<new> is called,
otherwise the default is used.

=cut

sub config_ok {
    my $self = shift;
    my $msg  = shift;

    $self->_run_exim_bv;

    # pad the msg if not specified
    $msg ||= sprintf(
        'config %s is valid',
        (
                 $self->{_state}{exim_config_file}
              || $self->{config_file}
              || '(unknown)'
        )
    );

    $self->test->ok( $self->{_state}{config}{ok}, $msg ) || $self->_diag;
}

=head2 has_capability 

    $exim->has_capability($type, $what, $optional_msg)
    $exim->has_capability('lookup', 'lsearch', 'Has lsearch capability')

Checks that C<exim> has the appropriate capability.  This is taken from 
the lists of capabilities listed by C<exim -bV>

The types of capability are:-

=over 4

=item support_for

=item lookup

=item authenticator

=item router

=item transport

=back

The items within a capability are processed to be lowercase
alphanumeric only - so C<iconv> rather than C<iconv()> as output by
exim. The subitems (for example C<maildir> is a subitem of
C<appendfile>) are treated as separately checkable items.

=cut

sub has_capability {
    my $self = shift;
    my $type = shift;
    my $what = shift;
    my $msg  = shift;

    $self->_run_exim_bv;
    $self->_croak('Invalid exim config') unless ( $self->{_state}{config}{ok} );
    $self->_croak('Capability requires a type')           unless ($type);
    $self->_croak('Capability requires a thing to check') unless ($what);

    # pad the msg if not specified
    $msg ||= sprintf( 'Checking %s/%s capability', $type, $what );

    $self->test->ok(
        (
                 $self->{_state}{config}{$type}
              && $self->{_state}{config}{$type}{$what}
        ),
        $msg
    );
}

=head2 has_not_capability 

Precisely the opposite of L<has_capability> with an opposite test - so
fails if this does exist.

=cut

sub has_not_capability {
    my $self = shift;
    my $type = shift;
    my $what = shift;
    my $msg  = shift;

    $self->_run_exim_bv;
    $self->_croak('Invalid exim config') unless ( $self->{_state}{config}{ok} );
    $self->_croak('Capability requires a type')           unless ($type);
    $self->_croak('Capability requires a thing to check') unless ($what);

    # pad the msg if not specified
    $msg ||= sprintf( 'Checking %s/%s capability', $type, $what );

    $self->test->ok(
        (
            $self->{_state}{config}{$type}
              && !$self->{_state}{config}{$type}{$what}
        ),
        $msg
    );
}

=head1 INTERNAL METHODS

These methods are not intended to be run by end users, but are exposed.

=head2 _run_exim_command

=cut

sub _run_exim_command {
    my $self = shift;
    my @args = @_;

    # we always put the config file as the first argument if we have one
    unshift @args, ( '-C' . $self->{config_file} )
      if ( $self->{config_file} );

    # run command
    my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) = run(
        command => [ $self->{exim_path}, @args ],
        verbose => $self->{debug},

        ## TODO timeout appears to have a nasty interaction which
        ##      causes the tests to fail, plus hang after the run
        #timeout => $self->{timeout}
    );

    $self->{_state}{last_error}  = $error_code;
    $self->{_state}{last_output} = $full_buf;

    return ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf );
}

=head2 _run_exim_bv

=cut

sub _run_exim_bv {
    my $self = shift;

    # we only want to run this once per session
    return if ( $self->{_state}{checked}++ );

    # run command
    my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) =
      $self->_run_exim_command('-bV');

    # parse things out if command worked
    if ($success) {
        $self->{_state}{config}{ok} = 1;
        foreach ( @{$stdout_buf} ) {
            chomp;
            if (/^Exim\s+version\s+([0-9\.]+)\s+#(\d+)/) {
                $self->{_state}{exim_version} = $1;
                $self->{_state}{exim_build}   = $2;
            }
            elsif (
                m{ ^
                    (   support \s+ for | # pick one of these
                        lookups         | # in $1
                        authenticators  |
                        routers         |
                        transports
                    )
                    : \s*               # followed by a colon
                    (.*)                # and the rest of the line in $2
                    $
                 }ix
              )
            {
                my $type = lc($1);
                $type =~ tr/a-z/_/cs;
                $type =~ s/s$//;        # strip trailing s
                my $res = lc($2);
                $res =~ tr|a-z0-9_ /||cd;
                my $table = { map { $_ => 1 } ( split( /[\s\/]/, $res ) ) };
                $self->{_state}{config}{$type} = $table;
            }
            elsif (/Configuration file is (.*)/) {
                $self->{_state}{exim_config_file} = $1;
            }
        }

        # we do sanity checks here - currently croak on these, which might
        # be too drastic!
        $self->_croak('No exim version number found')
          unless ( $self->{_state}{exim_version} );
    }
    else {
        $self->{_state}{config}{ok} = 0;
    }
}

=head2 _diag

=cut

sub _diag {
    my $self = shift;

    $self->test->diag(
        sprintf(
            "Error: %s\nOutput: %s\n",
            $self->{_state}{last_error},
            join(
                ' ',
                @{
                    ( ref( $self->{_state}{last_output} ) eq 'ARRAY' )
                    ? $self->{_state}{last_output}
                    : [ $self->{_state}{last_output} ]
                  }
            )
        )
    );
}

=head1 AUTHOR

Nigel Metheringham, C<< <nigelm at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-test-mta-exim4 at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-MTA-Exim4>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Test::MTA::Exim4


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-MTA-Exim4>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Test-MTA-Exim4>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Test-MTA-Exim4>

=item * Search CPAN

L<http://search.cpan.org/dist/Test-MTA-Exim4/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Nigel Metheringham.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Test::MTA::Exim4
