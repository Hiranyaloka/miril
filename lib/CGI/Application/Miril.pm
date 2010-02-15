package CGI::Application::Miril;

use strict;
use warnings;

use autodie;
use Try::Tiny;
use Exception::Class;

### ACCESSORS ###

use Object::Tiny qw(
	model
	filter
	cfg
	tmpl
	errors
	user_manager
	pager
	view
);

### SETUP ###

sub setup {
	my $self = shift;
	
	# setup runmodes

    $self->mode_param('action');
    $self->run_modes(
    	'list'         => 'posts_list',
        'edit'         => 'posts_edit',
        'create'       => 'posts_create',
        'delete'       => 'posts_delete',
        'view'         => 'posts_view',
        'update'       => 'posts_update',
		'publish'      => 'posts_publish',
		'files'        => 'files_list',
		'upload'       => 'files_upload',
		'unlink'       => 'files_delete',
		'search'       => 'search',
		'login'        => 'login',
		'logout'       => 'logout',
		'account'      => 'account',
	);

	$self->start_mode('list');
	$self->error_mode('error');

	# setup miril
	
	my $config_filename = $self->param('cfg_file');
	$config_filename = 'miril.config' unless $config_filename;
	my $miril = Miril->new($config_filename);
	
	require Miril::Theme::Flashyweb;
	$self->{tmpl} = Miril::Theme::Flashyweb->new;

	# load user manager
	my $user_manager_name = "Miril::UserManager::" . $self->cfg->user_manager;

	use Miril::UserManager::XMLTPP;
	$self->{user_manager} = Miril::UserManager::XMLTPP->new($self);

	#try {
	#	load $user_manager_name;
	#	$self->{user_manager} = $user_manager_name->new($self);
	#} catch {
	#	$self->process_error("Could not load user manager", $_, 'fatal');
	#};

	# configure authentication
	$self->authen->config( 
		DRIVER         => [ 'Generic', $self->user_manager->verification_callback ],
		LOGIN_RUNMODE  => 'login',
		LOGOUT_RUNMODE => 'logout',
		CREDENTIALS    => [ 'authen_username', 'authen_password' ],
		STORE          => [ 'Cookie', SECRET => $cfg->secret, EXPIRY => '+30d', NAME => 'miril_authen' ],
	);

	$self->authen->protected_runmodes(':all');	
	#$self->authen->protected_runmodes();
}

### RUN MODES ###

sub posts_list {
	my $self = shift;
	my $q = $self->query;

	my @items = $self->model->get_posts(
		author => ( $q->param('author') or undef ),
		title  => ( $q->param('title' ) or undef ),
		type   => ( $q->param('type'  ) or undef ),
		status => ( $q->param('status') or undef ),
		topic  => ( $q->param('topic' ) ? \($q->param('topic')) : undef ),
	);

	my @current_items = $self->paginate(@items);
	
	my $tmpl = $self->load_tmpl('list');
	$tmpl->param('items', \@current_items);
	return $tmpl->output;

}

sub search {
	my $self = shift;

	my $cfg = $self->cfg;

	my $tmpl = $self->load_tmpl('search');

	$tmpl->param('statuses', $self->prepare_statuses );
	$tmpl->param('types',    $self->prepare_types    );
	$tmpl->param('topics',   $self->prepare_topics   ) if $cfg->topics;
	$tmpl->param('authors',  $self->prepare_authors  ) if $cfg->authors;

	return $tmpl->output;
}

sub posts_create {
	my $self = shift;

	my $cfg = $self->cfg;

	my $empty_item;

	$empty_item->{statuses} = $self->prepare_statuses;
	$empty_item->{types}    = $self->prepare_types;
	$empty_item->{authors}  = $self->prepare_authors if $cfg->authors;
	$empty_item->{topics}   = $self->prepare_topics  if $cfg->topics;

	my $tmpl = $self->load_tmpl('edit');
	$tmpl->param('item', $empty_item);
	
	return $tmpl->output;
}

sub posts_edit {
	my $self = shift;

	my $cfg = $self->cfg;

	my $id = $self->query->param('id');
	# check if $item is defined
	my $item = $self->model->get_post($id);
	
	my %cur_topics;

	#FIXME
	if (@{ $item->{topics} }) {
		%cur_topics = map {$_->id => 1} $item->topics;
	}
	
	$item->{authors}  = $self->prepare_authors($item->author) if $cfg->authors;
	$item->{topics}   = $self->prepare_topics(%cur_topics)    if $cfg->topics;
	$item->{statuses} = $self->prepare_statuses($item->status);
	$item->{types}    = $self->prepare_types($item->type);
	
	my $tmpl = $self->load_tmpl('edit');
	$tmpl->param('item', $item);

	$self->add_to_latest($item->id, $item->title);

	return $tmpl->output;
}

sub posts_update {
	my $self = shift;
	my $q = $self->query;

	my $item = {
		'id'     => $q->param('id'),
		'author' => ( $q->param('author') or undef ),
		'status' => ( $q->param('status') or undef ),
		'text'   => ( $q->param('text')   or undef ),
		'title'  => ( $q->param('title')  or undef ),
		'type'   => ( $q->param('type')   or undef ),
		'old_id' => ( $q->param('old_id') or undef ),
	};

	# SHOULD NOT BE HERE
	$item->{topics} = [$q->param('topic')] if $q->param('topic');

	$self->model->save($item);

	return $self->redirect("?action=view&id=" . $item->{id});
}

sub posts_delete {
	my $self = shift;

	my $id = $self->query->param('old_id');
	$self->model->delete($id);

	return $self->redirect("?action=list");
}

sub posts_view {
	my $self = shift;
	
	my $q = $self->query;
	my $id = $q->param('old_id') ? $q->param('old_id') : $q->param('id');

	my $item = $self->model->get_post($id);
	if ($item) {
		$item->{text} = $self->filter->to_xhtml($item->text);

		my $tmpl = $self->load_tmpl('view');
		$tmpl->param('item', $item);
		return $tmpl->output;
	} else {
		return $self->redirect("?action=list");	
	}
}

sub login {
	my $self = shift;
	
	my $tmpl = $self->load_tmpl('login');
	return $tmpl->output;
}

sub logout {
	my $self = shift;

	$self->authen->logout();
	
	return $self->redirect("?action=login");
}

sub account {
	my $self = shift;
	my $q = $self->query;

	if (   $q->param('name')
		or $q->param('email')
		or $q->param('new_password') 
	) {
	
		my $username        = $q->param('username');
		my $name            = $q->param('name');
		my $email           = $q->param('email');
		my $new_password    = $q->param('new_password');
		my $retype_password = $q->param('retype_password');
		my $password        = $q->param('password');

		my $user = $self->user_manager->get_user($username);
		my $encrypted = $self->user_manager->encrypt($password);

		if ( $name and $email and ($encrypted eq $user->{password}) ) {
			$user->{name} = $name;
			$user->{email} = $email;
			if ( $new_password and ($new_password eq $retype_password) ) {
				$user->{password} = $self->user_manager->encrypt($new_password);
			}
			$self->user_manager->set_user($user);

			return $self->redirect("?"); 
		}

		return $self->redirect("?action=account");

	} else {
	
		my $username = $self->authen->username;
		my $user = $self->user_manager->get_user($username);

		my $tmpl = $self->load_tmpl('account');
		$tmpl->param('user', $user);
		return $tmpl->output;
	} 
}

sub files_list {
	my $self = shift;

	my $cfg = $self->cfg;

	my $files_path = $cfg->files_path;
	my $files_http_dir = $cfg->files_http_dir;
	my @files;
	
	opendir(my $dir, $files_path) or $self->process_error("Cannot open files directory", $!, 'fatal');
	@files = grep { -f catfile($files_path, $_) } readdir($dir);
	closedir $dir;

	my @current_files = $self->paginate(@files);

	my @files_with_data = map +{ 
		name     => $_, 
		href     => "$files_http_dir/$_", 
		size     => format_bytes( -s catfile($files_path, $_) ), 
		modified => strftime( "%d/%m/%Y %H:%M", localtime( $self->get_last_modified_time(catfile($files_path, $_)) ) ), 
	}, @current_files;

	my $tmpl = $self->load_tmpl('files');
	$tmpl->param('files', \@files_with_data);
	return $tmpl->output;
}

sub files_upload {
	my $self = shift;
	my $q = $self->query;
	my $cfg = $self->cfg;

	if ( $q->param('file') or $q->upload('file') ) {
	
		my @filenames = $q->param('file');
		my @fhs = $q->upload('file');

		for ( my $i = 0; $i < @fhs; $i++) {

			my $filename = $filenames[$i];
			my $fh = $fhs[$i];

			if ($filename and $fh) {
				my $new_filename = catfile($cfg->files_path, $filename);
				my $new_fh = IO::File->new($new_filename, "w") 
					or $self->process_error("Could not upload file", $!);
				copy($fh, $new_fh) 
					or $self->process_error("Could not upload file", $!);
				$new_fh->close;
			}
		}

		return $self->redirect("?action=files");

	} else {
		
		my $tmpl = $self->load_tmpl('upload');
		return $tmpl->output;

	}
}

sub files_delete {
	my $self = shift;	
	my $cfg = $self->cfg;
	my $q = $self->query;

	my @filenames = $q->param('file');

	try {
		for (@filenames) {
			unlink( catfile($cfg->files_path, $_) )
				or $self->process_error("Could not delete file", $!);
		}
	};

	return $self->redirect("?action=files");
}

sub posts_publish {
	my $self = shift;

	my $cfg = $self->cfg;
	
	my $do = $self->query->param("do");
	my $rebuild = $self->query->param("rebuild");

	if ($do) {
		$self->publish($rebuild);
		return $self->redirect("?action=list");
	} else {
		my $tmpl = $self->load_tmpl('publish');
		return $tmpl->output;
	}
}


1;
