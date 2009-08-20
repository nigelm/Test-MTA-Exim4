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

