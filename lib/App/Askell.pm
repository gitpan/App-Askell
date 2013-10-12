#
# This file is part of App-Askell
#
# This software is copyright (c) 2013 by Loïc TROCHET.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
package App::Askell;
# ABSTRACT: Execute commands defined by the user when files are created, modified or deleted

use Moose;
with qw(MooseX::Getopt::Strict);
use YAML qw(LoadFile);
use Path::Tiny;
use AnyEvent::Filesys::Notify;
use AnyEvent;

our $VERSION = '0.132850'; # VERSION

has file
=> (
    metaclass   => 'Getopt'
,   is          => 'ro'
,   isa         => 'Str'
,   cmd_aliases => 'f'
);

has 'version'
=> (
    metaclass   => 'Getopt'
,   is          => 'ro'
,   isa         => 'Bool'
,   default     => 0
,   cmd_aliases => 'v'
);

has 'silent'
=> (
    metaclass   => 'Getopt'
,   is          => 'ro'
,   isa         => 'Bool'
,   default     => 0
,   cmd_aliases => 's'
);

sub _load_file
{
    my $self = shift;
    my $data = {};
    my $config = LoadFile($self->file);
    
    while (my ($dir, $dir_data) = each %$config)
    {
        my $path = path($dir);

        die "'$dir' is not an absolute path.\n"
            unless $path->is_absolute;

        die "'$dir' is not a real directory.\n"
            unless $path->is_dir;
        
        $data->{$dir} = {};
        
        while (my ($files_mask, $files_data) = each %$dir_data)
        {
            my $cmd = $data->{$dir}->{$files_mask} = {c => undef, m => undef, d => undef};
            
            if (ref($files_data))
            {
                die "The data associated with '$files_mask' must be a hash.\n"
                    if ref($files_data) ne 'HASH';

                while (my ($events, $cmd_string) = each %$files_data)
                {
                    die "One of the commands associated with '$files_mask' is not a string.\n"
                        if ref $cmd_string;

                    for (split(',', $events))
                    {
                        die "'$_' is an invalid event ('c'reated, 'm'odified or 'd'eleted).\n"
                            if $_ ne 'c' and $_ ne 'm' and $_ ne 'd';

                        $cmd->{$_} = $cmd_string;
                    }
                }
            }
            else
            {
                $cmd->{c} = $files_data;
                $cmd->{m} = $files_data;
                $cmd->{d} = $files_data;
            }
        }
    }
    
    return $data;
}

sub _execute
{
    my ($self, $cmd, $file_name, $vars, $event) = @_;

    $cmd =~ s/\@p/$vars->{p}/g;
    $cmd =~ s/\@d/$vars->{d}/g;
    $cmd =~ s/\@f/$vars->{f}/g;
    $cmd =~ s/\@b/$vars->{b}/g;
    $cmd =~ s/\@e/$vars->{e}/g;

    print "---> $file_name($event) ==> $cmd\n"
        unless $self->silent;

    system($cmd) == 0
        or print STDERR "ERROR: system($cmd) failed - $?\n";
}

sub _callback
{
    my ($self, $data, @events) = @_;

    for my $event (@events)
    {
        my $path = path($event->path);

        my $dir_name  = $path->dirname;
        my $file_name = $path->basename;

        if (exists $data->{$dir_name})
        {
            while (my ($files_mask, $cmd) = each %{$data->{$dir_name}})
            {
                if ($file_name =~ m/^$files_mask$/)
                {
                    my $vars = {};

                    $vars->{p} = $event->path;
                    $vars->{d} = $dir_name;
                    $vars->{f} = $file_name;

                    if ($file_name =~ m/^(\S+)\.(\S+)$/)
                    {
                        $vars->{b} = $1;
                        $vars->{e} = $2;
                    }
                    else
                    {
                        $vars->{b} = '';
                        $vars->{e} = '';
                    }

                    $self->_execute($cmd->{c}, $file_name, $vars,  'created') if $event->is_created  and $cmd->{c};
                    $self->_execute($cmd->{m}, $file_name, $vars, 'modified') if $event->is_modified and $cmd->{m};
                    $self->_execute($cmd->{d}, $file_name, $vars,  'deleted') if $event->is_deleted  and $cmd->{d};
                }
            }
        }
    }

    return 0;
}


sub run
{
    my $self = shift;
    
    if ($self->version)
    {
        print "askell v$VERSION\n";
        exit 0;
    }

    unless (defined $self->file)
    {
        exit 0;
    }

    my $data = $self->_load_file;

    my @watchers;

    push @watchers, AnyEvent::Filesys::Notify->new
    (
        dirs     => [ keys %$data ]
    ,   interval => 1.0
    ,   filter   => sub { 1 }
    ,   cb       => sub { $self->_callback($data, @_) }
    );
    
    print "==>> Press 'Ctrl + C' or enter 'exit', 'quit' or 'bye' to stop the application...\n"
        unless $self->silent;

    my $exit = AnyEvent->condvar;
    push @watchers, AnyEvent->signal(signal => "INT", cb => sub { $exit->send; print "\n" });
    push @watchers, AnyEvent->io
    (
        fh   => \*STDIN
    ,   poll => 'r'
    ,   cb   => sub
        {
            # Read a line
            chomp(my $input = <STDIN>);
            # Quit program if 'exit', 'quit' or 'bye'
            $exit->send if $input eq 'exit' or $input eq 'quit' or $input eq 'bye';
        }
    );
    $exit->recv;
}

1;

__END__

=pod

=head1 NAME

App::Askell - Execute commands defined by the user when files are created, modified or deleted

=head1 VERSION

version 0.132850

=head1 SYNOPSIS

    foo.yml
    =======
    '/project/foo/src/less/':
        'app.less':
            'c,m': lessc --compress @p > @d@b.css

    askell --file foo.yml

    baz.yml
    =======
    '/project/baz/':
        '\w+.mpg':
            'c': mv @p /files/mpg/
        '\w+.mp3':
            'c': mv @p /files/mp3/
        '\w+.xml':
            'd': rm /files/xml/@f

    askell --file /project/baz.yml --silent

=head1 DESCRIPTION

This application allows you to execute commands when some files are created, modified or deleted in directories.

The configuration is done via a YAML file where you can specify multiple directories, and several types of files
per directory in the form of regular expressions.

=head2 Events

The following events can be used:

B<'c'> --> 'c'reated

B<'m'> --> 'm'odified

B<'d'> --> 'd'eleted

They can also be combined:

B<'c,m'> --> 'c'reated or 'm'odifed

=head2 Variables

The following variables can also be used, they will be replaced by their values at runtime:

B<@p> --> full path name (directory and filename)

B<@d> --> only directory

B<@f> --> only filename

B<@b> --> file basename  if filename like '*.*' else empty string

B<@e> --> file extension if filename like '*.*' else empty string

See L<askell> for the syntax of the command line.

=for Pod::Coverage::TrustPod run

=encoding utf8

=head1 AUTHOR

Loïc TROCHET <losyme@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Loïc TROCHET.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
