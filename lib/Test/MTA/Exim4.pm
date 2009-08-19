package Test::MTA::Exim4;

use warnings;
use strict;
use base qw(Class::Accessor::Fast);
use IPC::Cmd qw[can_run run];
use Test::Builder;

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

L<Test::MTA::Exim4> allows the testing of an C<exim> installation
and configuration using the perl TAP (Test Anything Protocol)
methodology.

This allows the writing of some simple test scripts which can check for
features of C<exim> and check that this configuration routes, accepts
or rejects mail as you would expect. As such it is an ideal system for
creating a test suite for your mail configuration allowing you to check
that there are no unexpected regressions when you make a change.

=head1 METHODS

=cut

# ------------------------------------------------------------------------

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

# ------------------------------------------------------------------------

=head2 reset

Resets the internal state.  Not sure when this might be useful!

=cut

sub reset {
    my $self = shift;

    $self->{_state} = { config => {} };

    return $self;
}

# ------------------------------------------------------------------------

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

# ------------------------------------------------------------------------

=head2 exim_version 

Returns the version of C<exim> seen when the configuration was checked.
This is intended for use within your own tests for appropriate
versions, for example:-

    # ensure we are running exim 4.69 or later
    ok(($exim->exim_version gt '4.69'), 'Exim version check');

=cut

sub exim_version {
    my $self = shift;
    my $msg  = shift;

    $self->_run_exim_bv;

    return $self->{_state}{exim_version};
}

# ------------------------------------------------------------------------

=head2 exim_build 

Returns the build number of C<exim> seen when the configuration was
checked. This is intended for use within your own tests for appropriate
versions/builds.

=cut

sub exim_build {
    my $self = shift;
    my $msg  = shift;

    $self->_run_exim_bv;

    return $self->{_state}{exim_build};
}

# ------------------------------------------------------------------------

=head2 has_capability 

    $exim->has_capability($type, $what, $optional_msg)
    $exim->has_capability('lookup', 'lsearch', 'Has lsearch capability')

Checks that C<exim> has the appropriate capability.  This is taken from 
the lists of capabilities listed by C<exim -bV>

The types of capability are:-

=over 4

=item * support_for

=item * lookup

=item * authenticator

=item * router

=item * transport

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
    $msg ||= sprintf( 'Checking for %s/%s capability', $type, $what );

    $self->test->ok(
        (
                 $self->{_state}{config}{$type}
              && $self->{_state}{config}{$type}{$what}
        ),
        $msg
      )
      || $self->_diag;
}

# ------------------------------------------------------------------------

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
    $msg ||= sprintf( 'Checking for lack of %s/%s capability', $type, $what );

    $self->test->ok(
        (
            $self->{_state}{config}{$type}
              && !$self->{_state}{config}{$type}{$what}
        ),
        $msg
      )
      || $self->_diag;
}

# ------------------------------------------------------------------------

=head2 routes_ok 

    $exim->routes_ok($address, $optional_msg);
    $exim->routes_ok('address@example.com', 'Checking routing');

Checks that C<exim> with this configuration can route to the address
given. Accepts any working address which may route to any number of
final targets as long as there are no undeliverable addresses in the
set.

=cut

sub routes_ok {
    my $self = shift;
    my $addr = shift;
    my $msg  = shift;

    $self->_croak('Requires an address') unless ($addr);

    # run the check
    my $res = $self->_run_exim_bt($addr);

    # pad the msg if not specified
    $msg ||= sprintf( 'Can route to %s', $addr );

    # OK if there are no undeliverables and there are deliverables
    $self->test->ok( ( $res->{deliverable} && !$res->{undeliverable} ), $msg )
      || $self->_diag;
}

# ------------------------------------------------------------------------

=head2 routes_as_ok 

    $exim->routes_as_ok($address, $target, $optional_msg);
    $exim->routes_as_ok('address@example.com',
        {transport => 'local_smtp}, 'Checking routing');

Checks that C<exim> with this configuration routes to the address
given with the appropriate target results.

The target is an arrayref of hashes (or as a special case a single
hash), which matches against the addresses section of the result from
L<_run_exim_bt>. Each address matches if all the elements given in the
target hash match (so an empty hash will match anything).

See L<_run_exim_bt> for hash elements.

=cut

sub routes_as_ok {
    my $self   = shift;
    my $addr   = shift;
    my $target = shift;
    my $msg    = shift;

    $self->_croak('Requires an address')           unless ($addr);
    $self->_croak('Requires a target description') unless ($target);

    # if target is a hash, wrap it in an array
    $target = [$target] if ( ref($target) eq 'HASH' );
    $self->_croak('target should be an arrayref')
      unless ( ref($target) eq 'ARRAY' );

    # run the check
    my $res = $self->_run_exim_bt($addr);

    # pad the msg if not specified
    $msg ||= sprintf( 'Can route to %s', $addr );

    # check we get the right number of things back
    my $count_ok =
      ( scalar( keys %{ $res->{addresses} } ) == scalar( @{$target} ) );
    my $count         = scalar( @{$target} );
    my $addr_count_ok = 0;
    my $addresses     = { %{ $res->{addresses} } };    #copy address info

    # only do these tests if the count matches the rules
    if ($count_ok) {
        foreach my $targetspec ( @{$target} ) {
            $self->_croak('target spec should be hashref')
              unless ( ref($targetspec) eq 'HASH' );
            foreach my $addr ( keys %{$addresses} ) {
                my $thisone = 1;
                foreach my $key ( keys %{$targetspec} ) {
                    unless ( exists( $addresses->{$addr}{$key} )
                        && ( $addresses->{$addr}{$key} eq $targetspec->{$key} )
                      )
                    {
                        $thisone = 0;
                        last;
                    }
                }
                if ($thisone) {
                    $addr_count_ok++;
                    last;
                }
            }
        }
    }

    # return test status
    $self->test->ok( ( $count_ok && ( $addr_count_ok == $count ) ), $msg )
      || $self->_diag;
}

# ------------------------------------------------------------------------

=head2 discards_ok 

    $exim->discards_ok($address, $optional_msg);
    $exim->discards_ok('discards@example.com', 'Checking discarding');

Checks that C<exim> with this configuration will discard the given
address.

=cut

sub discards_ok {
    my $self = shift;
    my $addr = shift;
    my $msg  = shift;

    $self->_croak('Requires an address') unless ($addr);

    # run the check
    my $res = $self->_run_exim_bt($addr);

    # pad the msg if not specified
    $msg ||= sprintf( 'Discard for %s', $addr );

    # OK if there is a total of one address and it was discarded
    $self->test->ok(
        (
                 ( $res->{total} == 1 )
              && ( values %{ $res->{addresses} } )[0]->{discarded}
        ),
        $msg
    ) || $self->_diag;
}

# ------------------------------------------------------------------------

=head2 undeliverable_ok 

    $exim->undeliverable_ok($address, $optional_msg);
    $exim->undeliverable_ok('discards@example.com', 'Checking discarding');

Checks that C<exim> with this configuration will consider the given
address to be undeliverable.

=cut

sub undeliverable_ok {
    my $self = shift;
    my $addr = shift;
    my $msg  = shift;

    $self->_croak('Requires an address') unless ($addr);

    # run the check
    my $res = $self->_run_exim_bt($addr);

    # pad the msg if not specified
    $msg ||= sprintf( 'Undeliverable to %s', $addr );

    # OK if there are no deliverables and there are undeliverables
    $self->test->ok( ( $res->{undeliverable} && !$res->{deliverable} ), $msg )
      || $self->_diag;
}

# ------------------------------------------------------------------------

=head1 INTERNAL METHODS

These methods are not intended to be run by end users, but are exposed.

=cut

# ------------------------------------------------------------------------

=head2 _run_exim_command

Runs an exim instance with the appropriate config file and 

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

    # as documented in IPC::Cmd, the buffer returns are an arrayref
    # unexpectedly, that array has a single element with a slurped string
    # so we reprocess into a one line per element form
    $full_buf   = [ map { ( split( /\r?\n/, $_ ) ) } @{ $full_buf   || [] } ];
    $stdout_buf = [ map { ( split( /\r?\n/, $_ ) ) } @{ $stdout_buf || [] } ];
    $stderr_buf = [ map { ( split( /\r?\n/, $_ ) ) } @{ $stderr_buf || [] } ];

    $self->{_state}{last_error}  = $error_code;
    $self->{_state}{last_output} = $full_buf;

    return ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf );
}

# ------------------------------------------------------------------------

=head2 _run_exim_bv

Runs C<exim -bV> with the appropriate configuration file, to check that
the configuration file is valid. The output of the command is parsed
and stashed and used to provide the functions to check versions numbers
and capabilities.

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
                my $res  = lc($2);
                $type =~ tr/a-z/_/cs;
                $type =~ s/s$//;             # strip trailing s
                $res  =~ tr|a-z0-9_ /||cd;
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

# ------------------------------------------------------------------------

=head2 _run_exim_bt

Runs C<exim -bt> (address test mode) with the appropriate configuration
file, to check how the single address passed routes. The output of the
command is parsed and passed back in the results.

The results structure is hash that looks like:-
    {
        all_ok        => # no invocation errors
        deliverable   => # number of deliverable addresses
        undeliverable => # number of undeliverable addresses
        total         => # total number of addresses
        addresses     => {}
    }

The C<addresses> part of the structure has one key for each resultant
address, the value of which is another hash, which may contain the
following items:-

=over 4

=item * ok

True if the address routed OK, False otherwise.

=item * discarded

True if the address was discarded by the router, false or missing if
not.

=item * data

Scalar of lines picked out of exim output related to this address and
not otherwise recognised.

=item * router

The router name used to handle this address.

=item * transport

The transport name used to handle this address.

=item * address

The final destination addresss.

=item * original

The original address that was used within this transformation. This is
actually an arrayref each containing an address as several
transformations may take place.

=item * target

For a local transport, the delivery target.

=back

=cut

sub _run_exim_bt {
    my $self    = shift;
    my $address = shift;
    my $sender  = shift;

    # check for sanity... make sure we have a valid binary + config
    $self->_run_exim_bv unless ( $self->{_state}{config}{ok} );
    $self->_croak('No exim version number found')
      unless ( $self->{_state}{config}{ok} );

    my @options = ('-bt');
    push( @options, '-f', $sender ) if ( defined($sender) );
    push( @options, '--', $address );

    # run command - use a -- divider to prevent funkiness in the address
    my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) =
      $self->_run_exim_command(@options);

    # as exim uses the exit value to signify how well things worked, and
    # IPC::Cmd obscures this somewhat, we are just going to ignore it!
    # and parse the output to see what happened...
    my @lines  = @{$stdout_buf};
    my $result = {
        all_ok        => $success,
        deliverable   => 0,
        undeliverable => 0,
        total         => 0,
        addresses     => {}
    };
    while ( scalar(@lines) ) {
        my $line = shift @lines;
        next if ( $line =~ /^\s*$/ );

        # this line should be one of:-
        #   <addr> is undeliverable
        #   <addr> is discarded
        #   <addr> -> <target> + more info on next lines
        #   <addr> + more info on next lines
        if ( $line =~ /^(.*) is undeliverable(.*)$/ ) {
            $result->{undeliverable}++;
            $result->{total}++;
            $result->{addresses}{$1} = { ok => 0, reason => $2, address => $1 };
            next;
        }
        $result->{deliverable}++;
        $result->{total}++;
        my $res = { ok => 1, discarded => 0, data => [] };
        if ( $line =~ /^(.*) -\> (.*)$/ ) {
            $res->{address}          = $1;
            $res->{target}           = $2;
            $result->{addresses}{$1} = $res;
        }
        elsif ( $line =~ /^(.*) is discarded$/ ) {
            $res->{address}          = $1;
            $res->{discarded}        = 1;
            $result->{addresses}{$1} = $res;
        }
        else {
            $res->{address} = $line;
            $result->{addresses}{$line} = $res;
        }

        # mop up subsequent lines
        while ( scalar(@lines) && ( $lines[0] =~ /^\s/ ) ) {
            $line = shift @lines;
            if ( $line =~ /^\s+\<-- (.*)/ ) {
                $res->{original} ||= [];
                push( @{ $res->{original} }, $1 );
            }
            elsif ( $line =~ /^\s+transport = (.*)/ ) {
                $res->{transport} = $1;
            }
            elsif ( $line =~ /^\s+router = (.*), transport = (.*)/ ) {
                $res->{router}    = $1;
                $res->{transport} = $2;
            }
            else {
                push( @{ $res->{data} }, $line );
            }
        }
    }

    return $result;
}

# ------------------------------------------------------------------------

=head2 _diag

Spits out some L<Test::Builder> diagnostics for the last run command.
Used internally by some tests on failure. The output data is the last
error seen by L<IPC::Cmd> and the complete output of the command.

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

# ------------------------------------------------------------------------

=head1 AUTHOR

Nigel Metheringham, C<< <nigelm at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-test-mta-exim4 at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-MTA-Exim4>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Test::MTA::Exim4

=head2 Warning

=over 4

At this point the module is *not* released to CPAN - still in early
development and subject to change in a big way (including renaming, or
even just dropping it). However when/if it is released, further
information will be found at these locations

=back

You can also look for information at:

=over 4

=item * github - source control system (latest development version will always be here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-MTA-Exim4>

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

The module draws very strongly on the L<Test::Exim4::Routing> module by
Max Maischein. It is structured differently, and is currently very
experimental (meaning the API may change in a big way), so these
changes were made as a new module in a name space that is intended for
use by similar modules for other MTAs.


=head1 COPYRIGHT & LICENSE

Copyright 2009 Nigel Metheringham.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Test::MTA::Exim4
