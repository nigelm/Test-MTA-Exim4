use inc::Module::Install;

name     'Test-MTA-Exim4';
all_from 'lib/Test/MTA/Exim4.pm';
author   q{Nigel Metheringham <nigelm@cpan.org>};
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

