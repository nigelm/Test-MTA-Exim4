package inc::MyDistMakeMaker;
use Moose;

extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';

override _build_MakeFile_PL_template => sub {
    my ($self) = @_;

    my $template .= <<'TEMPLATE';
# Automated tests always fail on Windows.  This magic should
# prevent windows smoketesters attempting to run the distro
# tests at all, and so stop it wasting everybodies time.
# Windows fail is down to IPC::Cmd
# However exim is not available on windows, so module does not
# apply anyhow...
exit 1 if ($^O eq 'MSWin32' && $ENV{AUTOMATED_TESTING} );

TEMPLATE

    $template .= super();

    return $template;
};

__PACKAGE__->meta->make_immutable;
