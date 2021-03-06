package Miril::Config::Format::Config::General;

# ABSTRACT: Config::General format support for Miril configuration files

use strict;
use warnings;

use Config::General;
use Ref::List qw(list);
use Miril::Topic;
use Miril::Type;
use Miril::List::Spec;
use File::Spec;
use Path::Class qw(file);

use Mouse;
extends 'Miril::Config';

around 'BUILDARGS' => sub
{
	my ($orig, $class, $filename) = @_;

	my %cfg = Config::General->new($filename)->getall;

	if ($cfg{topic})
	{
		my @topics = map { 
			Miril::Topic->new( id => $_, %{ $cfg{topic}{$_} }) 
		} keys %{ $cfg{topic} };
		$cfg{topics}  = \@topics;
		delete $cfg{topic};
	}

	if ($cfg{type})
	{
		my @types = map { 
			Miril::Type->new( id => $_, %{ $cfg{type}{$_} }) 
		} keys %{ $cfg{type} };
		$cfg{types} = \@types;
		delete $cfg{type};
	}

	if ($cfg{list})
	{
		my @lists = map { 
            Miril::List::Spec->new( id => $_, %{ $cfg{list}{$_} } )
        }  keys %{ $cfg{list} };
		$cfg{lists} = \@lists;
		delete $cfg{list};
	}

	### ADD BASE DIR INFO ###
	
	$cfg{site_dir} = file($filename)->dir;

	return $class->$orig(%cfg);
};

1;

