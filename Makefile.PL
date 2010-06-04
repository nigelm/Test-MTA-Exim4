# Automated tests always fail on Windows.  This magic should
# prevent windows smoketesters attempting to run the distro
# tests at all, and so stop it wasting everybodies time.
# Windows fail is down to IPC::Cmd
# However exim is not available on windows, so module does not
# apply anyhow...
exit 1 if ($^O eq 'MSWin32' && $ENV{AUTOMATED_TESTING} );

use inc::Module::Install;

name 'Test-MTA-Exim4';
all_from 'lib/Test/MTA/Exim4.pm';
author q{Nigel Metheringham <nigelm@cpan.org>};
license 'perl';

build_requires 'Test::More';
build_requires 'FindBin';

# basic requires set
requires 'Class::Accessor::Fast' => 0;
requires 'IPC::Cmd'              => 0;
requires 'Test::Builder'         => 0;

tests_recursive (qw|
    t
|);

resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'http://github.com/nigelm/Test-MTA-Exim4/';
resources 'MailingList' => 'http://lists.exim.org/mailman/listinfo/exim-dev';

auto_install;

WriteAll;

