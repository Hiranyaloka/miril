package Miril::App::Cmd::Command::sync;

use strict;
use warnings;

use Miril::App::Cmd -command;

sub execute 
{
	my ($self, $opt, $args) = @_;
    
    my $command = $self->miril->config->sync;
    
    if ($command)
    {
        exec $command;
    }
    else
    {
        print "Sync command not specified in your configuration file\n";
    }
}

1;


