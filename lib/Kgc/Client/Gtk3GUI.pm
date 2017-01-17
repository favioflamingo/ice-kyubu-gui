package Kgc::Client::Gtk3GUI;

#use 5.020002;
use strict;
use warnings;
use CBitcoin;
use Gtk3 '-init';
use Glib qw{ TRUE FALSE };
use Glib::EV;
use EV;
use IO::Socket::UNIX;
use JSON::XS;
use Image::PNG::QRCode 'qrpng';
use MIME::Base64;
use Gtk3::SimpleList;
use Number::Format;
use Kgc::Types::Utilities;
use utf8;

use Log::Log4perl;
Log::Log4perl->init("/etc/kgc/kgc-logging.conf");
my $logger = Log::Log4perl->get_logger();

sub module_directory {
	use File::ShareDir ':ALL';
	return  module_dir('Kgc::Client::Gtk3GUI');
	#my $path = $ENV{'PATH'};
	#my $x = `readlink -f . && ls -la && echo $path`;
	#warn $x;
	#return '.';
}

require Exporter;
*import = \&Exporter::import;
require DynaLoader;

$Kgc::Client::Gtk3GUI::VERSION = '0.1';

DynaLoader::bootstrap Kgc::Client::Gtk3GUI $Kgc::Client::Gtk3GUI::VERSION;

@Kgc::Client::Gtk3GUI::EXPORT = ();
@Kgc::Client::Gtk3GUI::EXPORT_OK = ();


=item dl_load_flags

Don't worry about this.

=cut


sub dl_load_flags {0} # Prevent DynaLoader from complaining and croaking



=pod

---+ Kgc::Client::Gtk3GUI

# https://developer.gnome.org/gtk3/stable/

http://search.cpan.org/~mlehmann/Glib-EV-2.02/EV.pm

Mix EV with gtk

The best way to start looking at the business logic part of the code is to first go to the main_menu set of callbacks.  All functionality flows from those callbacks.

---++ Start Up Procedure

On start up, the following events occur in roughly the following order, as can be seen in _new_ and _loop_ :
   1. _Client_ sends _api/login_ request to _Kgc_ 
      a. If the user uses a smartphone with all of the settings cached, then we are finished
      a. If the user just types in the PIN, then dialog_restore is executed
   1. _Kgc_ responds with a cookie, stores the PIN for the smartchip, and alerts _Client_ as to whether or not there was a root key to begin with



---+ Subroutines

=cut

our $default_unit = 'mBTC';

=pod

---++ new

Check out the "connect" subroutine to see how the login process gets kicked off.

Make sure to check the language settings by looking up $ENV{'LANGUAGE'}

	LANGUAGE = (unset),
	LC_ALL = (unset),
	LC_PAPER = "ja_JP.utf8",
	LC_MONETARY = "ja_JP.utf8",
	LC_NUMERIC = "ja_JP.utf8",
	LC_MEASUREMENT = "ja_JP.utf8",
	LC_TIME = "ja_JP.utf8",
	LANG = "en_GB.UTF-8"


=cut

sub new {
	my ($package,$basedir,$homedir) = @_;
	
	my $xmlfilename = $basedir."/ice-kyubu.glade",
	my $customcss = $basedir."/custom.css";
	
	
	die "no glade xml file exists here" unless -f $xmlfilename;
	

	# get a new builder object
	my $this = {
		'builder' => Gtk3::Builder->new(),
		'surface' => 'no water',
		'objects' => {},
		'nonce' => 1,
		'send requests' => [],
		'signature count' => 0,
		'basedir' => $basedir, # contains static files
		'homedir' => $homedir # contains home folder
	};
	bless($this,$package);
	
	$this->locked();
	
	$this->{'Number::Format'}->{'mBTC'} = Number::Format->new(
		-thousands_sep   => ',',
		-decimal_point   => '.',
		-int_curr_symbol => 'mBTC',
		-decimal_digits => 3 
	);
	$this->{'Number::Format'}->{'mBTC'}->{'_divisor'} = 100_000;
	$this->{'Number::Format'}->{'BTC'} = Number::Format->new(
		-thousands_sep   => ',',
		-decimal_point   => '.',
		-int_curr_symbol => 'BTC',
		-decimal_digits => 3
	);
	$this->{'Number::Format'}->{'BTC'}->{'_divisor'} = 100_000;
	
	# load the Gtk File from GLADE
	$this->builder->add_from_file( $xmlfilename ) || die "Error loading GLADE file";
   	
   	# interface-css-provider-path
	if(-f $customcss){
		#$this->{'custom_css'} = Gtk3::CssProvider->new();
		#$this->{'custom_css'} = $this->{'custom_css'}->load_from_path($customcss);
	}
	else{
		die "no custom css file path provided ($customcss)";
	}
   	
   	#$this->builder->signal_autoconnect_from_package($this);

	# Do this line, so that when there is a callback (ie button press), we get the object back
	# .. as the first argument
	$this->builder->connect_signals(undef, $this );
		
	$logger->debug("before show main menu");
	$this->show_main_menu();
	$logger->debug("after show main menu");
	return $this;
}

=pod

---+++ locked

Check if multiple programs are running.  Exit if true.

And when an interrupt has been received, remove the lock file.

=cut

sub locked {
	my $this = shift;
	my $lock_fp = $this->home_directory().'/icekyub.pid';
	if(-f $lock_fp){
		$logger->error("Program is already running! FP=$lock_fp");
		
		#exit 1;
	}
	else{
		open(my $fh,'>',$lock_fp) || die "cannot open lock file";
		print $fh $$;
		close($fh);
	}	
	$SIG{'INT'} = sub{
		my $t1 = $this;
		$t1->finish();
		#exit 0;
	};
}

=pod

---++ finish()

Remove the lock file, kill all the children, and exit.

=cut

sub finish{
	my $this = shift;
	my $lock_fp = $this->home_directory.'/icekyub.pid';
	if(-f $lock_fp){
		unlink($lock_fp);
	}
	
	if(defined $this->{'child pids'} && ref($this->{'child pids'}) eq 'ARRAY'){
		foreach my $pid (@{$this->{'child pids'}}){
			$logger->info("Killing pid=$pid");
			kill('INT',$pid);
			waitpid($pid,0);
		}
	}
	exit(0);
}

=pod

---+ Getters/Setters

=cut

=pod

---++ builder

=cut

sub builder {
	my $this = shift;
	return $this->{'builder'};
}

=pod

---++ home_directory

Give back $HOME/.kyub (untainted).

=cut

sub home_directory {
	return shift->{'homedir'};
}

=pod

---++ object($id)

=cut

sub object{
	my $this = shift;
	my $id = shift;
	
	if(defined $id && length($id) > 0){
		if(defined $this->{'objects'}->{$id}){
			return $this->{'objects'}->{$id};
		}
		elsif(defined $this->special_object($id)){
			# this object will be defined in the special object subroutine			
			return $this->{'objects'}->{$id};
		}
		else{
			my $x = $this->builder->get_object($id);
			$this->{'objects'}->{$id} = $x if defined $x;
			return $x;
		}
	}
	else{
		die "no id specified";
	}
}

=pod

---++ special_object

Look up objects not defined in the glade file.

=cut

sub special_object {
	my $this = shift;
	my $id = shift;
	
	if($id eq 'accountdetail_simplelist'){
		$this->{'objects'}->{'accountdetail_simplelist'} = Gtk3::SimpleList->new_from_treeview(
			$this->object('accountdetail_treestore')
			,'hello' => 'text'
			,'number' => 'double'
		);
		return $this->{'objects'}->{'accountdetail_simplelist'};
	}
	elsif($id eq 'simplelist_bank'){
		$this->{'objects'}->{'simplelist_bank'} = Gtk3::SimpleList->new_from_treeview(
			$this->object('settings_bank_dialog_treeview')
			,'name' => 'text'
		);
		@{$this->{'objects'}->{'simplelist_bank'}->{data}} = @{$this->{'swift codes'}->{'Japan'}};
		require Data::Dumper;
		my $xo = Data::Dumper::Dumper($this->{'swift codes'}->{'Japan'});
		$logger->debug("XO=$xo");
		#@{$this->{'objects'}->{'simplelist_bank'}->{data}} = (['日本語','beta','charlie']);
		return $this->{'objects'}->{'simplelist_bank'};		
	}
	elsif($id eq 'txoutputs_simplelist'){
		$this->{'objects'}->{'txoutputs_simplelist'} = Gtk3::SimpleList->new_from_treeview(
			$this->object('txoutputs_dialog_treeview_outputs')
			,'ADDR' => 'text'
			,'BTC' => 'double'
		);
		# @{$this->{'objects'}->{'txoutputs_simplelist'}->{data}} = (['addr1',3.0],['addr2',1.4]);
		return 	$this->{'objects'}->{'txoutputs_simplelist'};
	}
	else{
		return undef;
	}
	
}

=pod

---+++ accountdetail_simplelist

my $treestore = $this->object('accountdetail_treestore');
my $child = $tree_store->append(undef);
$tree_store->set($child, 0, '/', 1, '/');

=cut

sub special_object_accountdetail_simplelist {
	my ($this) = @_;
	$this->{'objects'}->{'accountdetail_simplelist'} = Gtk3::SimpleList->new_from_treeview(
		$this->object('accountdetail_treestore'),
		'hello' => 'text'
		,'number' => 'double'
	);
    return $this->{'objects'}->{'accountdetail_simplelist'};
}


=pod

---+ subs

=cut

=pod

---++ show_main_menu

=cut

sub show_main_menu {
	my $this = shift;
	
	# create the main window
	my $window = $this->object( "main_menu" ) ||  die "Error while creating Main Window";
	
	#if(defined $this->{'custom_css'}){
		#$logger->debug("changing css for all widgests");
		#my $newcontext = Gtk3::StyleContext->new();
		#$window->get_style_context()->add_provider_for_screen($this->{'custom_css'},1);
	#}
	#else{
	#	die "failed to load css";
	#}
	
	
	$window->show_all();
	$window->fullscreen();
	
	# when the windiw is closed, kill the program
	$window->signal_connect(destroy=> sub{
		Gtk3->main_quit;	
	});
}

=pod

---+ Utilities

=cut

=pod

---++ display_account($account)

Display an account.

=cut

sub display_account {
	my ($this,$account) = @_;
	unless(defined $account){
		$logger->debug("no account specified, using default account");
		$account = $this->{'settings'}->{'default_account'};
	}
	my $slist = $this->object('accountdetail_simplelist');
	
	@{$slist->{data}} = (
		[ 'alpha', 1.1 ],
		[ 'beta', 2.2 ]
	);
	
	# format buttons?	
	
	my $window = $this->object('accountdetail_view_window');
	$window->set_transient_for($this->object('main_menu'));
	$window->show();
	$window->fullscreen();

}

sub display_account_formatpanel {
	my ($this,$account) = @_;

	my $button1 = Gtk3::Button->new("Do Something?");
	$button1->signal_connect (clicked => sub{
		my $t1 = $this;
		$logger->debug("first button");		
	});

	my $button2 = Gtk3::Button->new("Do Something else?");
	$button2->signal_connect (clicked => sub{
		my $t1 = $this;
		$logger->debug("second button pressed");		
	});

	my $vbox = Gtk3::Box->new("vertical", 2);
	$vbox->pack_start($button1, TRUE, TRUE, 0);
	$vbox->pack_start($button2, TRUE, TRUE, 0);

	$vbox->set_homogeneous (TRUE);
	
	return $vbox;
}

sub accountdetail_view_window_button_toparent_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	$logger->debug("hiding accountdetail_view_window");
	$this->object('accountdetail_view_window')->hide();
}



=pod

---++ dialog($parent,$id,$title,$resposne_callback)->$response

Use a dialog box to retreive some info.  The info get stored in $this->{'dialog data'}->{$id}

example_dialog_label_top needs to exist.  That is the title.

The $parent is not text, but the actual gtk object.

=cut

sub dialog {
	my $this = shift;
	my $parent = shift;
	die "no parent specified" unless defined $parent;
	my $id = shift;
	die "no dialog box specified" unless defined $id;
	my $title = shift;
	#$title = '' unless defined $title;
	
	my $response_callback = shift;
	$response_callback = sub {
		return $_[0]->hide;
	} unless defined $response_callback;
	if(defined $response_callback && ref($response_callback) ne 'CODE'){
		die "response callback is not a subroutine";
	}
	
	my $dialog = $this->object($id);
	$dialog->set_transient_for($parent);
	
	# set the title
	my $label = $this->object($id."_label_top");
	$label->set_label($title) if defined $label && defined $title;
	
	
	$dialog->signal_connect (
		response => $response_callback
	);
	$this->input_dialog_change_keys($id,undef);
	
	$dialog->show();
	$dialog->fullscreen();
	my $resp = $dialog->run();
	my $x = $this->{'dialog data'}->{$id};
	delete $this->{'dialog data'}->{$id};
	# eq 'ok'
	if($resp){
		return $x;
	}
	elsif($resp eq 'cancel'){
		return undef;
	}
	else{
		$logger->debug("hi, no response code recognized");
	}
}

=pod

---+++ dialog_preconnect

=cut

sub dialog_preconnect {
	my ($this) = @_;
	
	$this->dialog($this->object('main_menu'),"preconnection_dialog","Welcome");
	
}

=pod

---+++ dialog_login($failed_previous_request)

Log in over the unix domain socket to the kgc.

=cut

sub dialog_login {
	my $this = shift;
		
	unless(defined $this->{'login attempt count'}){
		$this->{'login attempt count'} = 0;
	}
	
	
	# TODO: spend some time parsing the password
	# if there is data, put it in $this->{'data_to_load'};
	my $parsed_data = $this->settings_parse(
		$this->dialog($this->object( "main_menu" ),"text_input2_dialog","Login!")
	);
	# my $password = $parsed_data->{'password'};
	
	# with the password, set up progress bar
	$this->progress_message({
		'message' => 'Activating kyüb smartchip'
		,'progress' => 10,
		,'current task' => 'processing password'
		,'parent' => $this->object("main_menu") 
	});

	$this->send_request(
		{
			'method' => 'api/login',
			'params' => [{
				'password' => $this->password
			}]
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			#my $p1 = $password;
			if($response->{'result'} eq 'success'){
				$t1->{'login attempt count'} = 0;
				$t1->{'cookie'} = $response->{'cookie'};
				#$t1->{'password'} = $t1->password;
				$t1->progress_message_update({
					'current task' => 'checking internal data'
					,'progress' => 50
				});
				# send a view_home request, should return with error, 'no accounts'
				$t1->view_home();
				
				$t1->listener_add('update signature account',sub {
					my $t2 = $t1;
					# $socket,$index,$response
					my $socket2 = shift;
					# we do not need the index since we are not deleting this listener
					my $index = shift;
					# send the response over
					$t2->handle_signature_count(shift);
				});
				# api/echo sends gpg --card-status
				$t1->send_request(
					{
						'method' => 'api/echo',
						'params' => [1]
					},sub{}
				);	
				
			}
			elsif($t1->{'login attempt count'} < 5){
				$logger->debug("cannot log in");
				$t1->{'login attempt count'} += 1;
				#$t1->progress_message_update({
				#	'current task' => 'error: bad password'
				#	,'progress' => 10
				#	,'response' => 'cancel'
				#});
				#progress_dialog
				$t1->object('progress_dialog')->hide();
				$t1->dialog_login();
				$t1->object('progress_dialog')->show();
			}
			else{
				$logger->error("failed to log in after too many attempts");
				$this->dialog_shutdown();
				die "failed to log in after too many attempts";
			}
		}
	);
}

=pod

---+++ dialog_restore

Initiates the restore procedure.  Print the qr code.

=cut

sub dialog_restore {
	my $this = shift;
	$logger->debug("need to do restore");

	my $answer = $this->dialog_restore_choice('main_menu');
	
	
	# choice is either $answer eq 'fresh' || answer eq 'old'
	$logger->debug("after window:$answer");
	# we were probably trying to log in, so, check if we have a cookie
	if($this->{'cookie'}){
		$logger->debug("log in was successful, but need to do restore");
		$this->progress_message_update({
			'current task' => 'must do root initialization'
			,'progress' => 55
		});
	}
	else{
		die "weird problem, no login, but have to do restore";
	}

	# check if we have data to add
	# pick by $this->{'restore option'}
	if($answer eq 'old'){
		$logger->debug("need to load up some data");
		$this->dialog_restore_old();
	}
	elsif($answer eq 'fresh'){
		$logger->debug("need to create everything from scratch");

		#my $answer = $this->dialog();
		$this->dialog_restore_fresh();
		$logger->debug("prepare to backup");
		$this->dialog_save_qrcode($this->settings_backup());
		$this->dialog_shutdown();
	}
	else{
		$logger->error("reboot the machine!");
	}
}

=pod

---+++ dialog_restore_choice($parent,$timeout)

Give the user a choice between entering a root key or printing a new one.

=cut

sub dialog_restore_choice {
	my $this = shift;
	my ($parent,$timeout) = @_;
	
	# make sure we are logged in
	return undef unless defined $this->{'cookie'};
	
	$parent = 'main_menu' unless defined $parent;
	
	#$message = 'An error has occurred.';
	
	my $id = 'restorechoice_dialog';
	
	
	#$logger->debug("setting main_menu as transient");
	my $ref = $this->object('main_menu');
	#$logger->debug("with ref=$ref");
	my $dialog = $this->object($id);
	$dialog->set_transient_for($this->object($parent));
	#$logger->debug("after transient");
	# set a time out on the window
	if(defined $timeout && 0 < $timeout){
		my $w = EV::timer( 15, 0, sub{
			my $t1 = $this;
			my $d1 = $dialog;
			$logger->debug("timeout called");
			delete $t1->{'watchers'}->{$d1};
			$d1->response(4);
		});
		$this->{'watchers'}->{$dialog} = $w;		
	}
	
	
	$dialog->signal_connect (
		response => sub {
			return $_[0]->hide;
		}
	);
	#$this->input_dialog_change_keys($id,undef);
	
	$this->object('restorechoice_dialog_box_menu')->show();
	$this->object('restorechoice_dialog_box_fresh')->hide();
	$this->object('restorechoice_dialog_box_old')->hide();
	
	$dialog->show();
	$dialog->fullscreen();
	my $resp = $dialog->run();
	my $x = $this->{'dialog data'}->{$id};
	delete $this->{'dialog data'}->{$id};
	# eq 'ok'
	if($resp){
		return $x;
	}
	elsif($resp eq 'cancel'){
		return undef;
	}
	else{
		$logger->error("hi, no response code recognized");
	}
}
# making a restore choice
sub restorechoice_dialog_button_fresh_clicked_cb {
	my $this = shift;
	$this->{'dialog data'}->{'restorechoice_dialog'} = 'fresh';
	$logger->debug("fresh");
	$this->object('restorechoice_dialog')->response(4);
}

sub restorechoice_dialog_button_old_clicked_cb {
	my $this = shift;
	$this->{'dialog data'}->{'restorechoice_dialog'} = 'old';
	$logger->debug("old");
	$this->object('restorechoice_dialog')->response(4);
}

# getting details
sub restorechoice_dialog_button_helpfresh_clicked_cb {
	my ($this) = @_;
	$this->object('restorechoice_dialog_box_menu')->hide();
	$this->object('restorechoice_dialog_box_fresh')->show();
	$this->object('restorechoice_dialog_box_old')->hide();
}

sub restorechoice_dialog_button_helpold_clicked_cb {
	my ($this) = @_;
	$this->object('restorechoice_dialog_box_menu')->hide();
	$this->object('restorechoice_dialog_box_fresh')->hide();
	$this->object('restorechoice_dialog_box_old')->show();
}
# when the user finishes looking at the explanation, cycle back to the 2 choices
sub restorechoice_dialog_button_explanationok_clicked_cb {
	my ($this) = @_;
	$this->object('restorechoice_dialog_box_menu')->show();
	$this->object('restorechoice_dialog_box_fresh')->hide();
	$this->object('restorechoice_dialog_box_old')->hide();	
}

=pod

---+++ settings_backup

Take all the settings stored in the gui (locally) and export it via QR code.

version, index, 'number of friends', 'password'

=cut

sub settings_backup {
	my $this = shift;
	
	my $text = '';
	$this->{'data_to_load'}->{'version'} = 1; # always...
	$this->{'data_to_load'}->{'index'} = 2 unless 
		defined $this->{'data_to_load'}->{'index'};
	$this->{'data_to_load'}->{'number of friends'} = 0 unless
		defined $this->{'data_to_load'}->{'number of friends'};
	
	###### read password #########
	die "bad password length" unless length($this->password()) == 6;
	$text .= $this->password();
	my $out = '';
	
	###### read version #########
	die "bad version length with length=".lc(sprintf("%x", $this->{'data_to_load'}->{'version'})) unless
		 $this->{'data_to_load'}->{'version'} < 16;
	$text .= lc(sprintf("%x", $this->{'data_to_load'}->{'version'}));
	
	###### read index #########
	$out = MIME::Base64::encode_base64(pack('S',$this->{'data_to_load'}->{'index'}),'');
	die "bad index length with index=[".length($out)."]"
		unless length($out) == 4;
	$text .= $out;
	
	###### read numOffriends #########
	$out = lc(sprintf("%x", $this->{'data_to_load'}->{'number of friends'}));
	die "bad number of friends length" 
		unless $this->{'data_to_load'}->{'number of friends'} < 16;
	$text .= $out;
	
	return $text;
}


=pod

---++ settings_parse

=cut

sub settings_parse {
	my $this = shift;
	my $output_from_login = shift;
	#$this->{'data_to_load'} = {};
	my $ref = {};
	unless(defined $output_from_login && length($output_from_login) > 0 ){
		$this->{'password'} = 1;
		return {};
	}
	# check the length of the output
	# ..as this might be the initial log in
	if(length($output_from_login) == 6){
		$this->{'password'} = $output_from_login;
		return undef;
	}
	
	
	# does length check
	my $quit_sub = sub{
		my ($error) = @_;
		$this->{'password'} = 1;
		$logger->error($error);
		return {};
	};
	
	
	
	open(my $fhin, '<',\$output_from_login) || die "cannot read";
	# password is always 6 digits
	my ($n, $buf);
	
	###### read password #########
	$n = read($fhin,$buf,6);
	return $quit_sub->("did not read full password") unless $n == 6;
	# untaint because we are sending it to the smartchip
	if($buf =~ m/^([0-9a-zA-Z]+)$/){
		$this->{'password'} = $1;
	}
	else{
		return $quit_sub->("badly formatted password");
	}
	
	###### read version #########
	$n = read($fhin,$buf,1);
	return $quit_sub->("not enough bytes") unless $n == 1;
	if($buf =~ m/^([0-9a-f]+)$/){
		$ref->{'version'} = hex($1);
	}
	else{
		return $quit_sub->("badly formatted version");
	}
	###### read index #########
	$n = read($fhin,$buf,4);
	return $quit_sub->("not enough bytes") unless $n == 1;
	if($buf =~ m/^([0-9a-zA-Z\/\+\=]+)$/){
		$ref->{'index'} = $1;
		$ref->{'index'} = unpack('S',MIME::Base64::decode_base64($ref->{'index'}));
	}
	else{
		return $quit_sub->("badly formatted index with i=$buf");
	}
	
	###### read numOffriends #########
	# integer->hex: sprintf("%x", 15)
	# hex->integer: hex('f')
	$n = read($fhin,$buf,1);
	if($buf =~ m/^([0-9a-f])$/){
		$ref->{'number of friends'} = hex($1);
	}
	else{
		return $quit_sub->("badly formatted index with i=$buf");
	}	

	
	require Data::Dumper;
	my $xo = Data::Dumper::Dumper($ref);
	$logger->debug("$xo");
	$this->{'data_to_load'} = $ref;
}


=pod

---+++ dialog_save_qrcode

=cut

sub dialog_save_qrcode {
	my $this = shift;
	my $text = shift;
	
	$logger->debug("part 1: text=$text");
	my $png_file_path = $this->create_qr_code_png($text);
	$this->object("saverqr_dialog");
	if(-f $png_file_path){
		$this->object("saveqr_dialog_image_qr")->set_from_file($png_file_path);
	}
	
	# we don't need the response after this
	my $main_menu = $this->object( "main_menu" );
	$this->dialog($main_menu,"saveqr_dialog","Save Configuration");
	
	$logger->debug("part 2, printing dialog");
	
	$this->dialog($main_menu,"printroot_dialog","Print QR Code");
	
	
}

sub saveqr_dialog_button_ok_clicked_cb {
	shift->object("saveqr_dialog")->response(4);
}

sub printroot_dialog_button_ok_clicked_cb {
	shift->object("printroot_dialog")->response(4);
}

=pod

---+++ dialog_restore_old

Creates a new root cbhd key and a fresh tree.

=cut

sub dialog_restore_old {
	my $this = shift;
	#my $rootkey =  $this->dialog($this->object('main_menu'),"text_input2_dialog","Put in restore text");
	my $tries = 0;
	my $seed;
	$this->object('progress_dialog')->hide();
	# Testing only!
	my $seed_fake = 'xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi';

	while($tries < 5){
		$seed = $this->dialog(
			$this->object( "main_menu" ),"text_input2_dialog","Root Password"
		);
		$seed = $seed_fake;
		if(defined $seed && 0 < length($seed) && $seed =~ m/^(xprv.*)/){
			$seed = $1;
			last;
		}
		else{
			$logger->error("failed to scan xprv");
			$tries += 1;
		}
	}
	unless($tries < 5){
		$this->dialog_shutdown();
	}

	$this->object('progress_dialog')->show();
	$logger->debug("part 1");
	
	$this->send_request(
		{
			'method' => 'api/restore',
			'params' => [
				'root', # the name of the root account
				{
					'seed' => $seed,
					'root_pin' => $this->{'password'}
				}
			]
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			
			$t1->progress_message_update({
				'current task' => 'creating cbhd tree'
				,'progress' => 75
			});
			if($response->{'result'} eq 'success'){
				$logger->debug("response to api/restore - part 0");
				$t1->dialog_restore_fresh_version_1('root');
			}
			else{
				# failed, die
				die "failed to create new root key";
			}
		}	
	);
}



=pod

---+++ dialog_restore_fresh

Creates a new root cbhd key and a fresh tree.

=cut

sub dialog_restore_fresh {
	my $this = shift;
	#my $rootkey =  $this->dialog($this->object('main_menu'),"text_input2_dialog","Put in restore text");
	
	$logger->debug("part 1");
	
	$this->send_request(
		{
			'method' => 'api/restore',
			'params' => [
				'root',
				{
					'root_pin' => $this->{'password'}
				}
			]
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			
			$t1->progress_message_update({
				'current task' => 'creating cbhd tree'
				,'progress' => 75
			});
			if($response->{'result'} eq 'success'){
				$logger->debug("response to api/restore - part 0");
				$t1->dialog_restore_fresh_version_1('root');
			}
			else{
				# failed, die
				die "failed to create new root key";
			}
		}	
	);
}

sub dialog_restore_fresh_version_1 {
	my $this = shift;
	my $root = shift;
	
	$logger->debug("Go for version 1");
	
	$this->{'account mapping'} = {} unless defined $this->{'account mapping'};
	
	# create root->(h,2)
	$this->send_request(
		{
			'method' => 'api/createAccountExpert',
			'params' => [{
				'name' => 'v1',
				'comment' => 'servers as version 1 tree',
				'parentaccount' => $root,
				'type' => 'hard',
				'index' => 2
			}]
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			$logger->debug("response to dialog_restore_fresh_version_1 - part 1");
			if($response->{'result'} eq 'success'){
				# find the parent
				my $parent = 'v1';
				$logger->debug("response to dialog_restore_fresh_version_1 - part 2");
				#my $parent = $response->{'address'};
				
				# Savings Account: root->(h,2)->(h,2)
				# Broadcast Account, Channel 1: root->(h,2)->(s,2)
				# Child Kyub Account: root->(h,2)->(h,3)
				$t1->send_request(
					{
						'method' => 'api/createAccountExpert',
						'params' => [
							{
								'name' => 'savings',
								'comment' => 'for holding bitcoins',
								'parentaccount' => $parent,
								'type' => 'hard',
								'index' => 2,							
							},
							{
								'name' => 'broadcast',
								'comment' => 'channel 1',
								'parentaccount' => $parent,
								'type' => 'soft',
								'index' => 2						
							},
							{
								'name' => 'childkyub',
								'comment' => 'for child kyub',
								'parentaccount' => $parent,
								'type' => 'hard',
								'index' => 3			
							},
						]
					},
					sub{
						my $t2 = $this;
						my $response = shift;
						$logger->debug("response to dialog_restore_fresh_version_1 - part 3");
						if($response->{'result'} eq 'success'){
							# address -> {name, comment}
							foreach my $address (keys %{$response->{'cbhd'}}){
								$t2->{'account mapping'}->{$address}
									 = $response->{'cbhd'}->{$address};
							}
							$logger->debug("response to dialog_restore_fresh_version_1 - part 4");
							$t2->progress_message_update({
								'current task' => 'done'
								,'progress' => 100
								,'response' => 'ok'
							});
						}
						else{
							die "bad results:".$response->{'error'};
						}
						$logger->debug("response to dialog_restore_fresh_version_1 - part 6");
					}
				);
			}
			else{
				die "bad response, no way to create version 1 tree";
			}
			$logger->debug("response to dialog_restore_fresh_version_1 - part 7");
		}
	);
	
}

=pod

---++ dialog_shutdown

Put up a splash screen instructing the user to shutdown the device.

=cut

sub dialog_shutdown {
	my ($this) = @_;
	
	my $dialog = $this->object('shutdown_dialog');
	$dialog->set_transient_for($this->object('main_menu'));
	$dialog->show();
	$dialog->fullscreen();
	$dialog->run();
}


=pod

---+ Error Handling

This is for when there is an error that occurs during a dialog.

=cut

=pod

---++ dialog_error($message,$parent,$timeout)

Is this a duplicate of message_info?

=cut

sub dialog_error {
	my $this = shift;
	my ($message,$parent,$timeout) = @_;
	
	# make sure we are logged in
	return undef unless defined $this->{'cookie'};
	
	$parent = 'main_menu' unless defined $parent;
	
	#$message = 'An error has occurred.';
	
	my $id = 'error_dialog';

		
	my $dialog = $this->object($id);
	$dialog->set_transient_for($this->object($parent));
	
	# set a time out on the window
	if(defined $timeout && 0 < $timeout){
		my $w = EV::timer( 15, 0, sub{
			my $t1 = $this;
			my $d1 = $dialog;
			$logger->debug("timeout called");
			delete $t1->{'watchers'}->{$d1};
			$d1->response(4);
		});
		$this->{'watchers'}->{$dialog} = $w;		
	}

	
	# set the title
	my $label = $this->object('error_dialog_label_message');
	$label->set_markup('<big>'.$message.'</big>') if defined $label;
	
	
	$dialog->signal_connect (
		response => sub {
			return $_[0]->hide;
		}
	);
	#$this->input_dialog_change_keys($id,undef);
	
	$dialog->show();
	$dialog->fullscreen();
	my $resp = $dialog->run();
	my $x = $this->{'dialog data'}->{$id};
	delete $this->{'dialog data'}->{$id};
	# eq 'ok'
	if($resp){
		return $x;
	}
	elsif($resp eq 'cancel'){
		return undef;
	}
	else{
		$logger->error("hi, no response code recognized");
	}
}


sub error_dialog_button_ok_clicked_cb {
	shift->object("error_dialog")->response(4);
}


=pod

---+ Define Buttons

Ordered by window.


=cut

=pod

---++ main_menu

=cut


=pod

---+++ main_menu_button_buy_btc_sell_jpy_clicked_cb

From the main menu, the user wants to buy bitcoin.	

Process=buybtc

=cut


sub main_menu_button_buy_btc_sell_jpy_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	#my $resp = $this->dialog($win,"printbuy2_dialog","");
	
	$this->process_set('buybtc');
	
	$this->progress_message({
		'message' => 'Preparing buy request'
		,'progress' => 34,
		,'current task' => 'Creating deposit address'
		,'parent' => $this->object("main_menu") 
	});
	
	
	$this->send_request(
		{
			'method' => 'api/printbuy',
			# see dialog_restore_fresh_version_1 on what the tree looks like
			'params' => [$this->current_index(),[2, 'savings','broadcast']]
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			#my $p1 = $password;
			
			unless($t1->process_check('buybtc')){
				$t1->progress_message_update({
					'current task' => 'Error!'
					,'progress' => 0
					,'response' => 'ok'
				});
				# set process to null
				$t1->process_set();
				return undef;	
			}
			
			
			
			$t1->progress_message_update({
				'current task' => 'Signing buy request'
				,'progress' => 66
			});
			if($response->{'result'} eq 'success'){
#	{
#		'result' => 'success'
#		,'url' => $job->{'msg'}->{'url'}
#		,'link1' => substr($link,0,$halfpoint)
#		,'link2' => substr($link,$halfpoint)
#	}
				# see the smartcard-mq script for the method name
				# see listener_add on the args for the callback
				$t1->listener_add($response->{'listener'},sub{
					my $t2 = $t1;
					my $socket = shift;
					my $index = shift;
					my $r2 = shift;
					$logger->debug($response->{'listener'});
					$t2->progress_message_update({
						'current task' => 'Printing buy request'
						,'progress' => 100
						,'response' => 'ok'
					});
					$t2->dialog_buybtc(
						$r2->{'url'},
						$r2->{'link1'},
						$r2->{'link2'}
					);
					$t2->listener_remove($response->{'listener'},$index);
					# get the signature count from the smart card
					$t2->send_request(
						{
							'method' => 'api/echo',
							'params' => [1]
						},sub{}
					);
					# not in any process, set to null
					$t2->process_set();
				});	

					
			}
			else{
				$t1->dialog_error('Failed to get a response',$t1->process_parent());
			}
		}
	);
}

sub printbuy2_dialog_button_ok_clicked_cb{
	my $this = shift;
	
	$this->object("printbuy2_dialog")->hide();
}

sub printbuy2_dialog_button_help_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	$this->dialog_help("printbuy2_dialog");
}



sub dialog_buybtc {
	my ($this,$url,$link1,$link2) = @_;

	
	$logger->debug("part 1: text=$url");
	
	my @p = (
		$this->create_qr_code_png($url.$link1.$link2,4),
		$this->create_qr_code_png($url.$link2,2)
	);
	$this->object("printbuy2_dialog"); #initialize it so we can access images	
	$this->object("printbuy2_dialog_image_qr")->set_from_file($p[0]);
	#$this->object("printbuy2_dialog_image_right")->set_from_file($p[1]);
	
	my $main_menu = $this->object( "main_menu" );
	$this->dialog($main_menu,"printbuy2_dialog","Save Configuration",sub{
		# need to delete png files
		my @q = ($p[0],$p[1]);
		unlink($q[0]);
		unlink($q[1]);
		
		return $_[0]->hide;
	});
	
}

=pod

---+++ main_menu_button_sell_btc_buy_jpy

From [[http://gtk.10911.n7.nabble.com/Directory-file-browser-as-TreeView-td66216.html]].

=cut


sub main_menu_button_sell_btc_buy_jpy {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	#my $resp = $this->dialog($win,"printbuy2_dialog","");
	
	# TODO: put waiting window here
	$this->progress_message({
		'message' => 'Preparing sell request'
		,'progress' => 34,
		,'current task' => 'Creating deposit address'
		,'parent' => $this->object("main_menu") 
	});
	
	
	$this->send_request(
		{
			'method' => 'api/printsell',
			# see dialog_restore_fresh_version_1 on what the tree looks like
			'params' => [1, 'e-flamingo']
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			#my $p1 = $password;
			$t1->progress_message_update({
				'current task' => 'Signing buy request'
				,'progress' => 66
				,'response' => 'ok'
			});
			if($response->{'result'} eq 'success'){
#	{
#		'result' => 'success'
#		,'url' => $job->{'msg'}->{'url'}
#		,'link1' => substr($link,0,$halfpoint)
#		,'link2' => substr($link,$halfpoint)
#	}
				# see the smartcard-mq script for the method name
				# see listener_add on the args for the callback
				$t1->listener_add($response->{'listener'},sub{
					my $t2 = $t1;
					my $socket = shift;
					my $index = shift;
					my $r2 = shift;
					$logger->debug($response->{'listener'});
					$t2->progress_message_update({
						'current task' => 'Printing buy request'
						,'progress' => 100
						,'response' => 'ok'
					});
					$t2->dialog_buybtc(
						$r2->{'url'},
						$r2->{'link1'},
						$r2->{'link2'}
					);
					$t2->listener_remove($response->{'listener'},$index);
				});	

					
			}
			else{
				die "failed to get a response";
			}
		}
	);
}

sub printsell2_dialog_button_ok_clicked_cb{
	my $this = shift;
	$this->object("printbuy2_dialog")->hide();
}


sub dialog_sellbtc {
	my ($this,$url,$link1,$link2) = @_;

	
	$logger->debug("part 1: text=$url");
	
	my @p = (
		$this->create_qr_code_png($url.$link1.$link2,4),
		$this->create_qr_code_png($url.$link2,2)
	);
	$this->object("printbuy2_dialog"); #initialize it so we can access images	
	$this->object("printbuy2_dialog_image_left")->set_from_file($p[0]);
	#$this->object("printbuy2_dialog_image_right")->set_from_file($p[1]);
	
	my $main_menu = $this->object( "main_menu" );
	$this->dialog($main_menu,"printbuy2_dialog","Save Configuration",sub{
		# need to delete png files
		my @q = ($p[0],$p[1]);
		unlink($q[0]);
		unlink($q[1]);
		
		return $_[0]->hide;
	});
	
}

=pod

---++ dialog_help($dialog)

Bring up a qrcode so that someone can get help on what is going on.

=cut

sub dialog_help{
	my $this = shift;
	my $dialog = shift;
	$logger->debug("Dialog=$dialog");
	
}

=pod

---+++ main_menu_button_cmdcast_clicked_cb

Do a command broadcast (cmdcast).  The broadcast takes place via bitcoin transaction.

=cut


sub main_menu_button_cmdcast_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	#$btn->set_label("don't press");
	
	#my $newwindow = $this->builder->get_object("buy_btc");
	my $x = $this->dialog($this->object( "main_menu" ),"cmdselect_dialog","Select command");
	#$newwindow->show_all();
}


=pod

---+++ main_menu_button_tx_clicked_cb

Initiate a transaction.  Send btc to another address.

Process='dotx'

=cut


sub main_menu_button_tx_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	#my $resp = $this->dialog($win,"printbuy2_dialog","");
	
	#$this->{'utxo set'}->{'3Ed1mJi6PypbAHZmNPjQuL4ZRrDHg3VgK8'}->{'fadhfds'} = {
	#	'satoshi' => 50000,
	#	'tx_index' => 0
	#};
=pod	
	$this->utxo_add([
		undef,
		[
			{
              'satoshi' => 50000,
              'tx_hash' => '60163bdd79e0b67b33eb07dd941af5dfd9ca79b85866c9d69993d95488e71f2d',
              'tx_index' => 0,
              'address' => '3Ed1mJi6PypbAHZmNPjQuL4ZRrDHg3VgK8'			
			}
		]
	]);
=cut
	
#	$logger->debug("Balance:".$this->{'utxo set balance'});
	
	# create funding
	
#	$this->txoutputs_dialog();
	
	
#	return undef;
	
	
	$this->progress_message({
		'message' => 'Preparing UTXO request'
		,'progress' => 34,
		,'current task' => 'Calculating addresses'
		,'parent' => $this->object("main_menu") 
	});
	
	
	$this->process_set('dialog_tx','main_menu');
	
	
	# start the transaction process, first, by getting the utxo from the Bitcoin Network
	# and in txoutputs_dialog, the balances get fetched via the utxo_* subroutines.
	$this->utxo_send_request(\&txoutputs_dialog,[2, 'savings','broadcast']);
	
}


=pod

---+ tx dialogs

These dialogs are for btc transactions.

=cut

=pod

---+++ utxo_fee

Set the fee per kB in satoshi

The average recently has been 1000 (0.01mBTC) per kilobyte,

This is set in utxo_collect_response.

=cut

sub utxo_fee {
	my ($this,$fee) = @_;
	if(defined $fee && $fee =~ m/^(\d+)$/){
		$this->{'suggested fee'} = $1;
	}
	elsif(defined $fee){
		$logger->error("badly formatted fee");
	}
	return $this->{'suggested fee'};
}

=pod

---+++ utxo_add

[
          undef,
          [
            {
              'satoshi' => 50000,
              'tx_hash' => 'fadhfds&
              'tx_index' => 0,
              'address' => '3Ed1mJi6PypbAHZmNPjQuL4ZRrDHg3VgK8'
            },
            {
              'satoshi' => 50000,
              'tx_hash' => 'f5nnskdfak',
              'tx_index' => 0,
              'address' => '3Ed1mJi6PypbAHZmNPjQuL4ZRrDHg3VgK8'
            },
            {
              'satoshi' => 50000,
              'tx_hash' => 'fafrf',
              'tx_index' => 0,
              'address' => '3Ed1mJi6PypbAHZmNPjQuL4ZRrDHg3VgK8'
            },
            {
              'satoshi' => 50000,
              'tx_hash' => 'fadhfds&
              'tx_index' => 0,
              'address' => '3Ed1mJi6PypbAHZmNPjQuL4ZRrDHg3VgK8'
            }
          ]
        ]
# ('satoshi','tx_hash','tx_index','address')
=cut

sub utxo_add{
	my ($this,$utxo_new) = @_;
	
	unless(defined $utxo_new && ref($utxo_new) eq 'ARRAY'){
		$logger->error("bad format for utxo set");
		return undef;
	}
	
	$logger->debug(sub{
		"Setting utxo:".Data::Dumper::Dumper($utxo_new);
	});
	
	my @cols = ('satoshi','tx_hash','tx_index','address');
	
	my $p2pkh_array = $utxo_new->[0];
	my $p2sh_array = $utxo_new->[1];
	
	my $map = ['p2pkh', 'p2sh'];
	for(my $i=0;$i< scalar(@{$utxo_new});$i++){
		my $parray = $utxo_new->[$i];
		$logger->debug("sifting thru new ".$map->[$i]." entries");
		if(defined $parray && ref($parray) eq 'ARRAY'){
			foreach my $item (@{$parray}){
				my $complete_bool = 1;
				foreach my $c1 (@cols){
					$complete_bool = 0 unless defined $item->{$c1};
				}
				#$logger->debug("1");
				return undef unless $complete_bool;
				#$logger->debug(sub{
				#	"2 - ".Data::Dumper::Dumper($item)
				#});
				if(
					defined $this->{'utxo set'}->{$item->{'address'}}
					&& defined $this->{'utxo set'}->{$item->{'address'}}->{$item->{'tx_hash'}}
					&& defined $this->{'utxo set'}->{$item->{'address'}
						}->{$item->{'tx_hash'}}->{$item->{'tx_index'}}
				){
					$logger->error("overwriting tx input!");
					return undef;
				}
				$this->{'utxo set'}->{$item->{'address'}}->{$item->{'tx_hash'}
					}->{$item->{'tx_index'}} = {
						'script type' => $map->[$i],
						'satoshi' => $item->{'satoshi'}
				};
				#delete $this->{'utxo set'}->{$item->{'address'}
				#	}->{$item->{'tx_hash'}}->{'tx_hash'};				
				#delete $this->{'utxo set'}->{$item->{'address'}
				#	}->{$item->{'tx_hash'}}->{'address'};
			}
		}
		elsif(defined $parray){
			$logger->error($map->[$i]." array is in the wrong format");
			return undef;
		}		
	}

	
	# calculate the balances
	
	
	my $balance = 0;
	foreach my $k_address (keys %{$this->{'utxo set'}}){
		$logger->debug("have txhash=$k_address");
		foreach my $k_txhash (keys %{$this->{'utxo set'}->{$k_address}}){
			$logger->debug("have txhash=$k_txhash");
			foreach my $k_txindex (keys %{$this->{'utxo set'}->{$k_address}->{$k_txhash}}){
				$balance += $this->{'utxo set'}->{$k_address}->{$k_txhash
					}->{$k_txindex}->{'satoshi'};
			}
			
			
		}
	}
	$this->{'utxo set balance'} = $balance;
}

=pod

---+++ utxo_balance($satoshi)



=cut

sub utxo_balance {
	my ($this,$x) = @_;
	
	unless(defined $this->{'utxo set balance'}){
		$this->{'utxo set balance'} = 0;
	}
		
	if(defined $x && $x =~ m/^\-(\d+)$/){
		# adding an output
		$this->{'utxo set balance'} += -1 * $1;
	}
	elsif(defined $x && $x =~ m/^(\d+)$/){
		$this->{'utxo set balance'} += $1;
	}
	
	return $this->{'utxo set balance'};
}



=pod

---+++ utxo_send_request($callback,@list_of_accounts)

For single, p2pkh accounts, just put 'savings'.  For multisig, put [2, 'savings','broadcast'].

The @args for $callback is ($this).

=cut

sub utxo_send_request {
	my $this = shift;
	my $callback = shift;
	
	unless(defined $callback && ref($callback) eq 'CODE'){
		$logger->error("no callback given");
		return undef;
	}
	
	my @accounts = @_;
	unshift(@accounts,$this->current_index());
	
	$this->send_request(
		{
			'method' => 'api/utxorequest',
			# see dialog_restore_fresh_version_1 on what the tree looks like
			'params' =>\@accounts
		},
		sub{
			my $t1 = $this;
			# my $response = shift;
			$t1->utxo_collect_response(shift);
			my $c1 = $callback;
			my $account_ref = \@accounts;
			$c1->($t1,$account_ref);
		}
	);
}

=pod

---+++ utxo_collect_response($response)

This subroutine will take a response from utxo_send_request and let the user download the utxo set via qr codes.

=cut

sub utxo_collect_response {
	my ($t1,$response) = @_;
	
	return undef unless $t1->process_check('dialog_tx');

	# TODO: parse this from a utxo request
	$t1->utxo_fee(5000);

	if($response->{'result'} eq 'success'){
		$t1->progress_message_update({
			'current task' => 'Creating transaction message'
			,'progress' => 100
			,'response' => 'ok'
		});
		# "checksum":"QRXq2x55dkI=","utxo request"
		my $utxoreq = $response->{'utxo request'};
		if(
			defined $utxoreq && ref($utxoreq) eq 'ARRAY'
			&& 0 < scalar(@{$utxoreq})
		){
			# loop through each set of 5-10 hashes (addresses), get the utxo for this set
			my @utxoresp;
			my $answers = [];
			$t1->{'dialog_utxorequest'}->{'m'} = scalar(@{$utxoreq->[0]}) + scalar(@{$utxoreq->[1]});
			$logger->info(sub{
				"Total outbound qr codes:".$t1->{'dialog_utxorequest'}->{'m'}
			});
			$t1->{'dialog_utxorequest'} = {'stop' => 0};
			$t1->{'dialog_utxorequest'}->{'n'} = 0;
			$t1->{'dialog_utxorequest'}->{'type'} = 0;
			{
				# isolate the scope for convenience reasons
				# ..Joel wanted to use $p here and in the for loop below
				my $p = 0;
				foreach my $item (@{$utxoreq->[0]}){
					$logger->info("Have p2pkh item=$item");
					my $fullnelson;
					while(
						!(defined $fullnelson) && length($fullnelson) == 0
						&& !($t1->{'dialog_utxorequest'}->{'stop'})
					){
						$fullnelson = $t1->dialog_utxorequest(
							'https://e-flamingo.net/utxo/p2pkh/'.
							Kgc::Types::Utilities::gpgsig_base64_to_urlsafe($item)
						);
						
						$logger->error("Fullnelson is blank") unless defined $fullnelson;
					}
					$fullnelson->{'p'} = $p;
					push(@{$answers->[0]},$fullnelson);
					$t1->{'dialog_utxorequest'}->{'n'} += 1;
					$p += 1;
					last if $t1->{'dialog_utxorequest'}->{'stop'};
				}			
			}


			unless($t1->{'dialog_utxorequest'}->{'stop'}){
				$t1->{'dialog_utxorequest'}->{'n'} = 0;
				$t1->{'dialog_utxorequest'}->{'type'} = 1;
				my $p = 0;
				foreach my $item (@{$utxoreq->[1]}){
					$logger->info("Have p2sh item=$item");
					my $fullnelson;
					while(
						!(defined $fullnelson) && length($fullnelson) == 0
						&& !($t1->{'dialog_utxorequest'}->{'stop'})
					){
						$fullnelson = $t1->dialog_utxorequest(
							'https://e-flamingo.net/utxo/p2sh/'.
							Kgc::Types::Utilities::gpgsig_base64_to_urlsafe($item)
						);
						
						$logger->error("Fullnelson is blank") unless defined $fullnelson;
					}
					$fullnelson->{'p'} = $p;
					push(@{$answers->[1]},$fullnelson);
					
					$logger->debug("after first p2sh p=$p");
					$t1->{'dialog_utxorequest'}->{'n'} += 1;
					$p += 1;
					last if $t1->{'dialog_utxorequest'}->{'stop'};
				}						
			}
			$t1->utxo_add($answers);
			
		}
		else{
			$t1->dialog_error('Failed to get a response',$t1->process_parent());
		}
		
	}
	else{
		#die "failed to get a response";
		$t1->dialog_error('Failed to get a response',$t1->process_parent());
	}
}



=pod

---+++ dialog_utxorequest($url)

Send a utxorequest to either E-Flamingo or a Hot-Kyub.

Need n for which set of addresses we are on, out of m sets.

=cut

sub dialog_utxorequest {
	my ($this,$url) = @_;
	
	
	$logger->debug("part 1: text=$url");
	
	
	my $req = '';
	
	my $qrpng = $this->create_qr_code_png($url,4);
	$this->{'dialog_utxorequest'}->{'qr code file path'} = $qrpng;
	$this->object("utxorequest_dialog"); #initialize it so we can access images	
	$this->object("utxorequest_dialog_image_qr")->set_from_file($qrpng);
	
	
	$this->object('utxorequest_dialog_textview');
	my ($n,$m) = ($this->{'dialog_utxorequest'}->{'n'},$this->{'dialog_utxorequest'}->{'m'});
	my $newtext = "Scanned $n/$m qr codes";
	$this->object("utxorequest_dialog_textbuffer")->set_text($newtext,length($newtext));
	
	return $this->dialog($this->object("main_menu"),"utxorequest_dialog",undef,sub{
		# need to delete png files
		my $qrpng_in = $qrpng;
		unlink($qrpng_in);
		$logger->debug("leaving utxorequest_dialog");
		return $_[0]->hide;
	});
}

=pod

---+++ utxorequest_dialog_button_ok_clicked_cb

No meaing.... Give status check?

=cut


sub utxorequest_dialog_button_ok_clicked_cb{
	my ($this,$btn,$win) = @_;
	
	# move on to the next one?
	#my @utxoresponses = ($this->dialog_utxoreceive(0,0));
	#$this->object("utxorequest_dialog")->response(4);
	$logger->info("clicked ok");
}

=pod

---+++ utxorequest_dialog_button_scan_clicked_cb

Scan the QR code on the website.

=cut

sub utxorequest_dialog_button_scan_clicked_cb{
	my ($this,$btn,$win) = @_;
	my ($u1,$urlcode);
	$urlcode = '';
	$u1 = \$urlcode;
	$this->{'dialog_utxorequest'}->{'current response'} = [] unless 
		defined $this->{'dialog_utxorequest'}->{'current response'};
	# callback: send request to kgc to take a picture, get back the response
	$this->scan_qr(sub{
		my ($t1,$qrcode) = @_;
		my $u2 = $u1;
		return $t1->utxorequest_dialog_button_scan_clicked_cb_zbarcallback(
			$qrcode,$u2
		);
	});
	
}

=pod

---+++ utxorequest_dialog_button_scan_clicked_cb_zbarcallback

=cut

sub utxorequest_dialog_button_scan_clicked_cb_zbarcallback {
	my ($this,$qrcode,$u2) = @_;
	$logger->debug("hello, got qrcode=$qrcode");
	
	eval{
		use bytes;
		die "no qrcode" unless defined $qrcode && 0 < length($qrcode);
		$qrcode = Kgc::Types::Utilities::gpgsig_urlsafe_to_base64($qrcode);
		$qrcode = MIME::Base64::decode_base64($qrcode);
		# do i already have a copy
		my $index = unpack('C',substr($qrcode,0,1));
		if($this->{'dialog_utxorequest'}->{'current response'}->[$index]){
			$logger->error("we already have a copy");
		}
		else{
			# we have no copy
			if($index == 0){
				# figure out how many qr codes we have to scan
				$this->{'dialog_utxorequest'}->{'qr m'} = unpack('C',substr($qrcode,1,1));
				$this->{'dialog_utxorequest'}->{'current response'}->[$index] = substr($qrcode,2);
				$logger->debug(
					"Got n=".unpack('C',substr($qrcode,0,1))." and m=".
						unpack('C',substr($qrcode,1,1))
				);
			}
			else{
				$this->{'dialog_utxorequest'}->{'current response'}->[$index] = substr($qrcode,1);
			}
		}
		
		if(
			defined $this->{'dialog_utxorequest'}->{'qr m'}
			&& scalar(@{$this->{'dialog_utxorequest'}->{'current response'}}) == 
				$this->{'dialog_utxorequest'}->{'qr m'}
		){
			# we are done!
			$logger->debug("we are done because n + 1 = m");
			$this->{'dialog_utxorequest'}->{'done'} = 1;
		}
		elsif(
			defined $this->{'dialog_utxorequest'}->{'qr m'}
			&& $this->{'dialog_utxorequest'}->{'qr m'} < $index
		){
			$logger->error("index is out of bounds");
		}
		$this->utxorequest_dialog_button_scan_clicked_cb_wrapup();
	};
	my $error = $@;
	if($error){
		$logger->error("got error scanning qr code:$error");
	}
}


=pod

---+++ utxorequest_dialog_button_scan_clicked_cb_wrapup

Once a qr cod has been scanned, see what data we got.



=cut

sub utxorequest_dialog_button_scan_clicked_cb_wrapup {
	my ($this) = @_;
	
	$logger->debug("checking qr code");
	
	my ($n,$m,$big_n,$big_m) = (
		scalar(@{$this->{'dialog_utxorequest'}->{'current response'}}),
		$this->{'dialog_utxorequest'}->{'qr m'},
		$this->{'dialog_utxorequest'}->{'n'},
		$this->{'dialog_utxorequest'}->{'m'}
	);
	# TODO: update balance during this process
	my $newtext = "Scanned $n/$m qr codes for set $big_n/$big_m";
	my $textbuffer = $this->object("utxorequest_dialog_textbuffer")->
		set_text($newtext,length($newtext));
	
	# set what gets returned from dialog_utxorequest
	
	if($this->{'dialog_utxorequest'}->{'done'}){
		$logger->debug("finished scanning 1 set");
		# returns {'answer' => .., 'tx_hash' => f4h38gh, 'tx_index' => 3, 'satoshi' => 5000}
		my $fullnelson = join('',@{$this->{'dialog_utxorequest'}->{'current response'}});
		$fullnelson = $this->utxo_singleset_deserialize($fullnelson);
		$this->{'dialog_utxorequest'}->{'current response'} = [];
		
		if(defined $fullnelson){
			$logger->debug(sub{
				"Full Nelson:".Data::Dumper::Dumper($fullnelson)
			});
			$this->{'dialog data'}->{'utxorequest_dialog'} = $fullnelson;
			$this->{'dialog_utxorequest'}->{'done'} = 0;
			$this->object("utxorequest_dialog")->response(4);
			my $qrfp = $this->{'dialog_utxorequest'}->{'qr code file path'};
			unlink($qrfp) if -f $qrfp;
		}
		else{
			$logger->error("could not parse utxo response");
			$this->{'dialog data'}->{'utxorequest_dialog'} = undef;
			$this->{'dialog_utxorequest'}->{'done'} = 0;
		}
	}
}


=pod

---+++ utxorequest_dialog_button_scan_clicked_cb

=cut

sub utxorequest_dialog_button_cancel_clicked_cb {
	my ($this,$btn,$win) = @_;
	$logger->info("Cancelling current process");
	$this->{'dialog_utxorequest'}->{'stop'} = 1;
	$this->process_set(undef);
	$this->object("utxorequest_dialog")->response(42);
}

=pod

---+++ utxo_singleset_deserialize($fulldata)->\@answer

parse/validate utxo single set (corresponding to 5-10 scripts)

So, perhaps there are between 5 to 10 20 byte hashes.  For each hash, there will be some tx inputs.


# [checksum,4B] [0 for p2pkh/ 1 for p2sh,1B]
# ..[script, 20B][tx_hash,32B][tx_index,2B][satoshi,8B] with total=47B

Get {
	'answer' => .., 'tx_hash' => f4h38gh, 'tx_index' => 3, 'satoshi' => 5000
}

=cut

sub utxo_singleset_deserialize {
	my ($this,$fullnelson) = @_;
	
	use bytes;
	open(my $fh,'<',\$fullnelson);
	binmode($fh);
	my ($n,$buf);
	my $answer = {}; # map scripts to \@txinputs
	eval{
		# checksum
		$n = read($fh,$buf,4);
		die "could not read checksum" unless $n == 4;
		my $checksum = $buf;
		my $checksumdata;
		# p2pkh or p2sh
		$n = read($fh,$buf,1);
		die "could not read script type" unless $n == 1;
		$checksumdata .= $buf;
		my $script_type = unpack('C',$buf);

		# script hash (160bit/20B)
		$n = read($fh,$buf,20);
		die "could not read script hash" unless $n == 20;
		$checksumdata .= $buf;
		my $scripthash = $buf;
		if($script_type == 0){
			$logger->debug("handling p2pkh script");
			$answer->{'address'} = 'OP_DUP OP_HASH160 0x'.
				unpack('H*',$scripthash).' OP_EQUALVERIFY OP_CHECKSIG';
			$answer->{'address'} = CBitcoin::Script::script_to_address($answer->{'address'});
		}
		elsif($script_type == 1){
			$logger->debug("handling p2sh script");
			$answer->{'address'} = 'OP_HASH160 0x'.unpack('H*',$scripthash).' OP_EQUAL';
			$answer->{'address'} = CBitcoin::Script::script_to_address($answer->{'address'});
		}
		else{
			die "bad script type";
		}
		# tx_hash
		$n = read($fh,$buf,32);
		die "could not read index" unless $n == 32;
		$checksumdata .= $buf;
		$answer->{'tx_hash'} = $buf;
		# tx_index
		$n = read($fh,$buf,2);
		die "could not read index" unless $n == 2;
		$checksumdata .= $buf;
		$answer->{'tx_index'} = unpack('S',$buf);
		
		$n = read($fh,$buf,8);
		die "could not read satoshi" unless $n == 8;
		$checksumdata .= $buf;
		$answer->{'satoshi'} = unpack('q',$buf);
		
		
		if($checksum eq substr(Digest::SHA::sha256($checksumdata),0,4)){
			$logger->debug("checksum matches");
		}
		else{
			die "checksum does not match";
		}
	
	} || do {
		my $error = $@;
		$logger->error("could not parse:$error");
		return undef;
	};
	close($fh);
	return $answer;
}

=pod

---++ txoutputs_dialog($funding_sources)

Once we get the utxo request, it is time from the user to pick the destination.

We have a gtkbox object, which is a derivative of gtkcontainer.  [[https://developer.gnome.org/gtk3/unstable/GtkContainer.html][gtk container documentation]] has a list of available functions.

Make sure to supply the funding sources needed to pay for the transaction.

The txoutputs_dialog does not return until txconfirm_dialog finishes.

=cut

sub txoutputs_dialog {
	my ($this) = @_;
	
	#$this->{'dialog data'}->{'funding sources'} = $this->utxo_current_funding();
	
	# load the dialog into memory, in case it hasn't already been
	$this->object('txoutputs_dialog');
	$this->object('txoutputs_dialog_label_balance')->set_text(
		$this->format_satoshi($this->utxo_balance(),$default_unit)
	);
	
	my $output = $this->dialog($this->object('main_menu'),'txoutputs_dialog',"Save Configuration",sub{
		my $t1 = $this;
		delete $t1->{'dialog data'}->{'txoutputs_dialog'};
		return $_[0]->hide;
	});
	
	
}

=pod

---+++ txoutputs_dialog_button_add_clicked_cb

Add a destination.

=cut

sub txoutputs_dialog_button_add_clicked_cb {
	my ($this,$btn,$win) = @_;
	

	my ($address,$satoshi);
	# get an address
	$address = $this->dialog(
		$this->object( "txoutputs_dialog" ),
		"text_input2_dialog","Address"
	);
	# $address = CBitcoin::Script::address_to_script($address) if defined $address;
	unless(
		defined $address
		&& 0 < length($address) 
	){
		$logger->error("address is in a bad format");
		return undef;
	}
	
	if(defined $this->{'dialog data'}->{'txoutputs_dialog'}->{$address}){
		$logger->error("address already being used");
		return undef;
	}


	# get an amount
	$satoshi = $this->dialog(
		$this->object( "txoutputs_dialog" ),
		"text_input2_dialog","Amount for $address"
	);
	$logger->debug("Satoshi:[$satoshi]");
	unless(
		defined $satoshi && $satoshi =~ m/^\d+(?:\.\d+)?$/ 
		&& 0 < $this->utxo_balance() - $satoshi
	){
		$logger->error("satoshi is in a bad format");
		return undef;
	}	
	#$satoshi = int($satoshi_divisor * $satoshi);

	$this->utxo_balance(-1 * $satoshi);
	#$this->{'utxo set balance'} = $this->{'utxo set balance'} - $satoshi; 
	# update balance
	$this->object('txoutputs_dialog_label_balance')->set_text(
		$this->format_satoshi($this->utxo_balance(),$default_unit)
	);
	
	# [$address/$satoshi, $button] -> $hbox
	my $box = $this->object('txoutputs_dialog_box_outputs');
	
	my $hbox = Gtk3::Box->new("horizontal", 2);
	$hbox->set_homogeneous(FALSE);
	
	
	# vertical
	my $vbox = Gtk3::Box->new("vertical", 2);
	$vbox->set_homogeneous(TRUE);
		
	# address label
	my $label = Gtk3::Label->new('');
	$label->set_markup('<big>'.$address.'</big>');
	$label->set_line_wrap(TRUE);
	$vbox->pack_start($label, FALSE, FALSE, 0);
	$label->show();

	# amount label
	$label = Gtk3::Label->new('');
	$label->set_markup(
		'<big>'.$this->format_satoshi($satoshi,$default_unit).' '.
		$default_unit.'</big>'
	);
	$label->set_justify('right');
	$vbox->pack_start($label, FALSE, FALSE, 0);
	$label->show();
	
	$hbox->pack_start($vbox, TRUE, TRUE, 0);
	$vbox->show();

	# add button to remove
	#my $mainiconstuff = Gtk3::IconSize::get_default();
	
	my $remove_button = Gtk3::Button->new_from_icon_name(
		'gtk-remove',
		16 #Gtk3::IconSize::from_name('GTK_ICON_SIZE_BUTTON')
	);
	$remove_button->set_always_show_image(TRUE);
	
	$remove_button->signal_connect (clicked => sub{
		my $bin = $hbox;
		$bin->destroy();
		
		my $t1 = $this;
		my $satoshi_ref = \$satoshi;
		#$t1->{'utxo set balance'} += $$satoshi_ref;
		$t1->utxo_balance($$satoshi_ref);
		$t1->object('txoutputs_dialog_label_balance')->set_text(
			$t1->format_satoshi($this->utxo_balance(),$default_unit)
		);
		my $a1 = \$address;
		delete $t1->{'dialog data'}->{'txoutputs_dialog'}->{$$a1};
		
	}, "remove");
	$hbox->pack_start($remove_button, FALSE, FALSE, 0);
	$remove_button->show();
	$box->pack_start($hbox, FALSE, FALSE, 0);
	$hbox->show();
	
	unless(defined $this->{'dialog data'}->{'txoutputs_dialog'}->{$address}){
		$this->{'dialog data'}->{'txoutputs_dialog'}->{$address} = 0;
	}
	
	$this->{'dialog data'}->{'txoutputs_dialog'}->{$address} += $satoshi;
}




=pod

---+++ txoutputs_dialog_button_ok_clicked_cb

Sign the transaction and display the qr codes necessary to send it back.

=cut

sub txoutputs_dialog_button_ok_clicked_cb {
	my ($this,$btn,$win) = @_;
	
	#my $txconfirm_dialog = $this->object('txconfirm_dialog');
	
	$this->txconfirm_dialog();
}

=pod

---+++ txoutputs_dialog_button_cancel_clicked_cb

Give up and go back to the main_menu.

=cut

sub txoutputs_dialog_button_cancel_clicked_cb {
	my ($this,$btn,$win) = @_;
	
	my $dialog = $this->object('txoutputs_dialog');
	$dialog->response(42);
}

=pod

---++ txconfirm_dialog($inputs,$outputs)

Allow the user to double check their transaction before putting out the qr codes.

All the data collected via txoutputs_dialog and utxorequest_dialog are still available.

Access the utxo tree via $this->{'utxo set'}.

=cut

sub txconfirm_dialog {
	my ($this,$inputs,$outputs) = @_;
	
	# run a delete sub here to clear out the screen
	if(defined $this->{'dialog data'}->{'callbacks txconfirm_dialog'}){
		foreach my $sub (@{$this->{'dialog data'}->{'callbacks txconfirm_dialog'}}){
			$sub->();
		}
	}
	$this->{'dialog data'}->{'callbacks txconfirm_dialog'} = [];
	
	$this->object('txconfirm_dialog');
	
	my $tx_hash = {};
	
	my $box;
	#........Inputs ....................
	$box = $this->object('txconfirm_dialog_box_inputs');
	# ['addr1','tx_hash1','tx_index1', 40000]
	my @inputs;
	foreach my $address (keys %{$this->{'utxo set'}}){
		# $this->{'utxo set'}->{$item->{'address'}}->{$item->{'tx_hash'}}
		my $satoshi = 0;
		foreach my $tx_hash (keys %{$this->{'utxo set'}->{$address}}){
		foreach my $tx_index (keys %{$this->{'utxo set'}->{$address}->{$tx_hash}}){
			$satoshi += $this->{'utxo set'}->{$address}->{$tx_hash}->{$tx_index}->{'satoshi'};
			push(@inputs,[$address,$tx_hash,$tx_index,$satoshi]);
		}}
		$logger->debug("add input:[$address,$satoshi]");
		
		#my ($address,$satoshi);
		#my $hbox = Gtk3::Box->new("horizontal", 3);
		#$hbox->set_homogeneous(TRUE);
		my $label = Gtk3::Label->new('');
		# address label
		my @x;
		if($address =~ m/^([0-9a-zA-Z]{6}).*([0-9a-zA-Z]{4})$/){
			@x = ($1,$2);
		}
		$label->set_markup('<big>'.$x[0].'..'.$x[1].'</big>');
		$box->pack_start($label, FALSE, FALSE, 0);
		$label->show();
		push(@{$this->{'dialog data'}->{'callbacks txconfirm_dialog'}},sub{
			my $h1 = $label;
			$h1->destroy();
		});
		# amount label
		$label = Gtk3::Label->new('');
		$label->set_markup(
			'<big>'.$this->format_satoshi($satoshi,$default_unit).' '.
			$default_unit.'</big>'
		);
		$label->set_justify('right');
		$box->pack_start($label, FALSE, FALSE, 0);
		$label->show();
		# add delete sub here in order to clear everything on the screen when reloading
		push(@{$this->{'dialog data'}->{'callbacks txconfirm_dialog'}},sub{
			my $h1 = $label;
			$h1->destroy();
		});
	}
	$tx_hash->{'inputs'} = \@inputs;
	
	# ..........Outputs.............
	# txconfirm_dialog_box_outputs
	# $this->{'dialog data'}->{'txoutputs_dialog'}->{$address}
	$box = $this->object('txconfirm_dialog_box_outputs');
	my @outputs;
	foreach my $address (keys %{$this->{'dialog data'}->{'txoutputs_dialog'}}){
		# $this->{'utxo set'}->{$item->{'address'}}->{$item->{'tx_hash'}}
		my $satoshi = $this->{'dialog data'}->{'txoutputs_dialog'}->{$address};
		$logger->debug("add output:[$address,$satoshi]");
		push(@outputs,[$address,$satoshi]);
		my $vbox = Gtk3::Box->new("vertical", 2);
		$vbox->set_homogeneous(FALSE);
		my $label = Gtk3::Label->new('');
		# address label
		$label->set_markup('<big>'.$address.'</big>');
		$vbox->pack_start($label, FALSE, FALSE, 0);
		$label->show();
		# amount label
		$label = Gtk3::Label->new('');
		
		$label->set_markup(
			'<big>'.$this->format_satoshi($satoshi,$default_unit).' '.
			$default_unit.'</big>'
		);
		$vbox->pack_start($label, FALSE, FALSE, 0);
		$label->show();
		$box->pack_start($vbox, FALSE, FALSE, 0);
		$vbox->show();
		
		# add delete sub here in order to clear everything on the screen when reloading
		push(@{$this->{'dialog data'}->{'callbacks txconfirm_dialog'}},sub{
			my $h1 = $vbox;
			$h1->destroy();
		});
	}
	$tx_hash->{'outputs'} = \@outputs;
	
	
	# check txconfirm_dialog_button_ok_clicked_cb for the formatting
	$tx_hash->{'txfee'} = 1500;
	$this->{'dialog data'}->{'transaction prototype'} = $tx_hash;
	
	$this->dialog($this->object('main_menu'),'txconfirm_dialog',"Confirm TX",sub{
		my $t1 = $this;
		$t1->object('txoutputs_dialog')->response(4);
		delete $t1->{'dialog data'}->{'transaction prototype'};
		return $_[0]->hide;
	});	
}

=pod

---+++ txconfirm_dialog_button_ok_clicked_cb

Send a $txhash to the kgc.
   * Formatting:<verbatim>$txhash = {
	'inputs' => [
			['addr1','tx_hash1','tx_index1', 40000],...
		],
	'outputs' => [
			['addr1', 3500 ],....
		],
	,
	'txfee' => 1500 # per kB
}</verbatim>

=cut

sub txconfirm_dialog_button_ok_clicked_cb {
	my ($this) = @_;
	
	my $tx_hash = $this->{'dialog data'}->{'transaction prototype'};
	$logger->debug(sub{
		"Funding Sources:".Data::Dumper::Dumper($tx_hash)
	});

	unless(
		defined $tx_hash && ref($tx_hash) eq 'HASH'
		&& defined $tx_hash->{'inputs'} && ref($tx_hash->{'inputs'}) eq 'ARRAY'
		&& 0 < scalar(@{$tx_hash->{'inputs'}}) 
	){
		$logger->error("No funding sources supplied");
		$this->object('txconfirm_dialog')->response(42);
		return undef;
	}
	
	unless(
		defined $tx_hash->{'inputs'} && ref($tx_hash->{'inputs'}) eq 'ARRAY'
		&& 0 < scalar(@{$tx_hash->{'outputs'}})
	){
		$logger->error("No outputs");
		$this->object('txconfirm_dialog')->response(42);
		return undef;
	}
	
	unless(defined $tx_hash->{'txfee'} && 0 < $tx_hash->{'txfee'}){
		$logger->error("No fee specified");
		$this->object('txconfirm_dialog')->response(42);
		return undef;
	}
	
	# must put this after the send_request, or else, the request will never go out
	# $this->txsend_dialog();
	
	$this->send_request(
		{
			'method' => 'api/icekyubspend',
			# see dialog_restore_fresh_version_1 on what the tree looks like
			'params' => $tx_hash
		},
		sub{
			my $response = shift;
			$logger->debug(sub{
				"Got spend response:".$response
			});
			my $t1 = $this;
			
			if($response->{'result'} ne 'error'){
				$logger->debug("success!");
				
				$t1->txsend_dialog_receive_response($response);
			}
			else{
				$logger->error("failure with error=".$response->{'error'});
				$t1->object('txconfirm_dialog')->response(42);
			}
		}
	);
	$this->txsend_dialog();
}

=pod

---+++ txconfirm_dialog_button_cancel_clicked_cb

=cut

sub txconfirm_dialog_button_cancel_clicked_cb {
	return shift->object('txconfirm_dialog')->response(42);
}

=pod

---++ txsend_dialog($response_from_txconfirm)

This comes after txconfirm_dialog.

=cut

sub txsend_dialog {
	my ($this) = @_;

	$this->object('txsend_dialog');
	$this->object('txsend_dialog_image_loading')->show();
	$this->object('txsend_dialog_button_next')->hide();
	$this->object('txsend_dialog_button_help')->hide();
	$this->object('txsend_dialog_label_explanation')->hide();
	
	
	$this->dialog($this->object('txconfirm_dialog'),'txsend_dialog',"Send TX",sub{
		my $t1 = $this;
		$t1->object('txconfirm_dialog')->response(4);
		my $qrpng = $t1->{'dialog data'}->{'txsend_dialog'}->{'qrcode'};
		if(-f $qrpng){
			unlink($qrpng);
		}
		
		return $_[0]->hide;
	});	
}

=pod

---+++ txsend_dialog_receive_response

When we get a response from the kgc with respect to the api/icekyubsend request

=cut

sub txsend_dialog_receive_response{
	my ($this,$response) = @_;
	my $data = $response->{'serialized transaction'};
	$logger->debug("got a response! data=$data");
	
	# split the length
	my $max_length = 150;
	my $data_length = length($data);
	my $n = int(length($data)*1.0/$max_length);
	my $m = 0;
	my @data_parts;
	while(0 < $data_length - $m){
		my $part = substr($data,$m,$max_length);
		$m += length($part);
		push(@data_parts,$part);
	}
	$this->{'dialog data'}->{'txsend_dialog'}->{'parts'} = \@data_parts;
	$this->{'dialog data'}->{'txsend_dialog'}->{'part index'} = -1;
	
	$this->txsend_dialog_next_qr();
	
	$this->object('txsend_dialog');
	$this->object('txsend_dialog_image_loading')->hide();
	$this->object('txsend_dialog_button_next')->show();
	$this->object('txsend_dialog_button_help')->show();
	$this->object('txsend_dialog_label_explanation')->show();
	
}

=pod

---+++ txsend_dialog_next_qr

Cycle to the next qr code.

=cut

sub txsend_dialog_next_qr {
	my ($this) = @_;

	$this->{'dialog data'}->{'txsend_dialog'}->{'part index'} += 1;
	my $i = $this->{'dialog data'}->{'txsend_dialog'}->{'part index'};
	
	my $dp = $this->{'dialog data'}->{'txsend_dialog'}->{'parts'};
	my $part = $dp->[$i];
	
	if(defined $part){
		$logger->debug("Transmit data=$part");
		my $qrpng = $this->{'dialog data'}->{'txsend_dialog'}->{'qrcode'};
		if(defined $qrpng && -f $qrpng){
			unlink($qrpng);
		}
		$qrpng = $this->create_qr_code_png($part,4);
		
		$this->{'dialog data'}->{'txsend_dialog'}->{'qrcode'} = $qrpng;
		
		
		$this->object("txsend_dialog"); #initialize it so we can access images	
		$this->object("txsend_dialog_image_qr")->set_from_file($qrpng);		
	}
	else{
		$logger->info("done!");
		$this->object('txsend_dialog')->response(4);
		return undef;
	}

	
}

=pod

---+++ txsend_dialog_button_ok_clicked_cb

The user hits the ok button once all of the qr codes have been sent.

=cut

sub txsend_dialog_button_next_clicked_cb {
	my $this = shift;
	$logger->debug("rotating to the next qr code");
	$this->txsend_dialog_next_qr();	
}



=pod

---+++ txsend_dialog_button_ok_clicked_cb

The user hits the ok button once all of the qr codes have been sent.

=cut

sub txsend_dialog_button_ok_clicked_cb {
	$logger->debug("finished!");
	shift->object('txsend_dialog')->response(4);
}

=pod

---+++ txsend_dialog_button_cancel_clicked_cb

The entire transaction process gets canceled.

=cut

sub txsend_dialog_button_cancel_clicked_cb{
	$logger->debug("cancelling!");
	shift->object('txsend_dialog')->response(42);
}




=pod

---++ dialog_cmdtx($url,$checksum,$utxorequest)

The user has to pick what command he/she wants to broadcast.


=cut

sub dialog_cmdtx {
	my ($this,$url,$checksum,$utxorequest) = (shift,shift,shift,shift);
	
	#$logger->debug("part 1: text=$url");
	
	# $this->dialog($main_menu,"saveqr_dialog","Save Configuration");
	
	my $main_menu = $this->object( "main_menu" );
	$this->dialog($main_menu,"cmdselect_dialog","Pick Command",sub{
		return $_[0]->hide;
	});
	
}

=pod

---+++ cmdselect_dialog_button_addkyub_clicked_cb

=cut

sub cmdselect_dialog_button_addkyub_clicked_cb {
	my $this = shift;
	
	# look at dialog_restore_fresh_version_1 for the account created for child kyub
	my $account = 'childkyub';
	
	$this->process_set('addkyub','cmdselect_dialog');
	
	# need to create a hard child of childkyub
	# api/createAccount/Cash
	$this->send_request(
		{
			'method' => 'api/exportkyubaccount',
			# see dialog_restore_fresh_version_1 on what the tree looks like
			'params' =>[$this->current_index(), 'childkyub' ]
		},
		sub {
			my $t1 = $this;
			my $response = shift;
			
			
			if(!($t1->process_check('addkyub'))){
				$logger->debug("process is finished, ignore");
				
			}
			elsif($response->{'result'} eq 'success'){
				# $response->{'address'}
				# $response->{'key'}
				my $qrpng = $this->create_qr_code_png($response->{'key'},4);
				
				$this->object("utxorequest_dialog"); #initialize it so we can access images	
				$this->object("utxorequest_dialog_image_qr")->set_from_file($qrpng);
				#$this->object("printbuy2_dialog_image_right")->set_from_file($p[1]);
				
				my $main_menu = $this->object( "main_menu" );
				$this->dialog($main_menu,"utxorequest_dialog","Get UTXO",sub{
					# need to delete png files
					my $qrpng_in = $qrpng;
					unlink($qrpng_in);
			
					return $_[0]->hide;
				});
				$t1->dialog($main_menu,"printchildkyub_dialog","Pick Command",sub{
					return $_[0]->hide;
				});
				
				
			}
			elsif(defined $response->{'error'}){
				
				$t1->dialog_error($response->{'error'},$t1->process_parent());
				$t1->process_set();
				return undef;
			}
			else{
				$t1->dialog_error('Unknown error has occurred',$t1->process_parent());
				$t1->process_set();
				return undef;				
			}
		}
	);
	
}


=pod

---+++ cmdselect_dialog_button_importchannel_clicked_cb

=cut

sub cmdselect_dialog_button_importchannel_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	my $dialog = $this->object("cmdselect_dialog");
	$dialog->response(42);
}


=pod

---+++ cmdselect_dialog_button_removekyub_clicked_cb

=cut

sub cmdselect_dialog_button_removekyub_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");	
}

=pod

---+++ cmdselect_dialog_button_channel_clicked_cb

=cut

sub cmdselect_dialog_button_channel_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");	
}

=pod

---+++ cmdselect_dialog_button_timestamp_clicked_cb

=cut

sub cmdselect_dialog_button_timestamp_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");	
}


=pod

---+++ cmdselect_dialog_button_cancel_clicked_cb

=cut

sub cmdselect_dialog_button_cancel_clicked_cb {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	my $dialog = $this->object("cmdselect_dialog");
	$dialog->response(42);
}


=pod

---+++ main_menu_button_activate_more

=cut


sub main_menu_button_activate_more {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	#$btn->set_label("don't press");
	
	#my $newwindow = $this->builder->get_object("buy_btc");
	
	#$newwindow->show_all();
}

=pod

---+++ main_menu_button_help

=cut


sub main_menu_button_activate_help {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	my $resp = $this->dialog($win,"about_dialog","Punch In Text!");
	
	print STDERR "Sub=$this_subs_name\n";
}

=pod

---+++ main_menu_button_settings

=cut


sub main_menu_button_activate_settings {
	my $this = shift;
	my ($btn,$win) = @_;
	
	#$lbl->set_text("eat my socks");
	
	# http://www.perlmonks.org/?node_id=1929
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	#$btn->set_label("don't press");
	
	my $newwindow = $this->builder->get_object('settings_window');
	$newwindow->set_transient_for($this->object('main_menu'));
	$this->object('main_menu')->hide();
	$newwindow->show();
	$newwindow->fullscreen();
}

=pod

---++ settings_window Stuff

=cut

sub settings_window_go_back_to_settings {
	my ($this,$subwindow) = @_;
	$subwindow->hide();
	$this->object('settings_window')->show();
	$this->object('settings_window')->fullscreen();
}

=pod

---+++ settings_window

All callbacks listed here.

=cut

sub settings_window_button_back_clicked_cb{
	my ($this,$btn,$win) = @_;
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	#$win->hide();
	$this->object('settings_window')->hide();
	$this->object('main_menu')->show();
	$this->object('main_menu')->fullscreen();
}

sub settings_window_button_language_clicked_cb {
	my $this = shift;
	my $win = $this->object('settings_language_window');
	$win->set_transient_for($this->object('settings_window'));
	$this->object('settings_window')->hide();
	$this->object('settings_language_window')->show();
	$this->object('settings_language_window')->fullscreen();
}
sub settings_window_button_depositeflamingo_clicked_cb{
	my ($this,$btn,$win) = @_;
	
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");	
	
	#$win->show();
	#$win->fullscreen();
}

sub settings_window_button_depositbank_clicked_cb{
	my ($this,$btn,$win) = @_;
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
	
	# check hook_pre_loop_loadswiftcodes
	# $this->{'swift_codes'}->{'Japan'}
	$this->object('simplelist_bank');
	my $response = $this->dialog($this->object('settings_window'),'settings_bank_dialog');
	
}

sub settings_window_button_depositaccount_clicked_cb{
	my ($this,$btn,$win) = @_;
	my $this_subs_name = (caller(0))[3];
	$logger->debug("Sub=$this_subs_name");
}

=pod

---+++ settings_depositbank_dialog


=cut


=pod

---+++ settings_language_window

All callbacks listed here.

=cut

sub settings_language_window_button_back_clicked_cb{
	my $this = shift;
	$this->settings_window_go_back_to_settings($this->object('settings_language_window'));
}

sub settings_language_window_button_english_clicked_cb{
	shift->settings_language_window_change_language('english');
}

sub settings_language_window_button_japanese_clicked_cb{
	shift->settings_language_window_change_language('japanese');
}

sub settings_language_window_button_french_clicked_cb{
	shift->settings_language_window_change_language('french');
}

sub settings_language_window_button_mandarin_clicked_cb{
	shift->settings_language_window_change_language('mandarin');
}

sub settings_language_window_button_spanish_clicked_cb{
	shift->settings_language_window_change_language('spanish');
}

sub settings_language_window_change_language {
	my ($this,$new_language) = @_;
	
	$logger->debug("Changing to language to $new_language");
	$this->object('settings_language_window')->hide();
	my $msg_dialog = $this->message_info("Language changing");
	$this->send_request({
			'method' => 'api/settings'
			,'params' => [{
				'language' => $new_language
				,'old_password' => $this->password()
			}]
		}
		,sub{
			my $t1 = $this;
			my $response = shift;
			
			if($response->{'result'} eq 'success'){
				$logger->debug("successfully changed language");
				$this->message_info_destroy($msg_dialog);
				$this->object('settings_window')->hide();
				$this->object('main_menu')->show();
				$this->object('main_menu')->fullscreen();
			}
			else{
				$logger->warn("problem changing language");
			}
		}
	);
}


=pod

---++ input_text_dialog

=cut

=pod

---+++ input_text_dialog_button_clicked_ok


* 'none' / 'GTK_RESPONSE_NONE'
* 'reject' / 'GTK_RESPONSE_REJECT'
* 'accept' / 'GTK_RESPONSE_ACCEPT'
* 'delete-event' / 'GTK_RESPONSE_DELETE_EVENT'
* 'ok' / 'GTK_RESPONSE_OK'
* 'cancel' / 'GTK_RESPONSE_CANCEL'
* 'close' / 'GTK_RESPONSE_CLOSE'
* 'yes' / 'GTK_RESPONSE_YES'
* 'no' / 'GTK_RESPONSE_NO'
* 'apply' / 'GTK_RESPONSE_APPLY'
* 'help' / 'GTK_RESPONSE_HELP' 

=cut

sub input_text_dialog_button_clicked_ok {
	my $this = shift;
	my ($btn,$label) = @_;
	
	my $this_subs_name = (caller(0))[3];
	print STDERR "Sub=$this_subs_name\n";
	
	# close window
	my $dialog = $this->object("input_text_dialog");
	$dialog->response(4);
	#$dialog->close();
	
}

=pod

---+++ input_text_dialog_button_clicked_cancel

=cut

sub input_text_dialog_button_clicked_cancel {
	my $this = shift;
	my ($btn,$label) = @_;
	
	my $this_subs_name = (caller(0))[3];
	print STDERR "Sub=$this_subs_name\n";


	my $dialog = $this->object("input_text_dialog");
	$dialog->response(42);
		
	#my $current_text = $label->get_text();
	#print STDERR "Current Text=$current_text\n";
	
	#$current_text .= 'X';
	#$label->set_text($current_text);
}

=pod

---++ text_input2_dialog

=cut

=pod

---+++ text_input2_dialog_button_clicked_ok


* 'none' / 'GTK_RESPONSE_NONE'
* 'reject' / 'GTK_RESPONSE_REJECT'
* 'accept' / 'GTK_RESPONSE_ACCEPT'
* 'delete-event' / 'GTK_RESPONSE_DELETE_EVENT'
* 'ok' / 'GTK_RESPONSE_OK'
* 'cancel' / 'GTK_RESPONSE_CANCEL'
* 'close' / 'GTK_RESPONSE_CLOSE'
* 'yes' / 'GTK_RESPONSE_YES'
* 'no' / 'GTK_RESPONSE_NO'
* 'apply' / 'GTK_RESPONSE_APPLY'
* 'help' / 'GTK_RESPONSE_HELP' 

=cut

sub text_input2_dialog_button_clicked_ok {
	my $this = shift;
	my ($btn,$label) = @_;
	
	my $this_subs_name = (caller(0))[3];
	print STDERR "Sub=$this_subs_name\n";
	
	# close window
	my $dialog = $this->object("text_input2_dialog");
	$dialog->response(4);
	$this->{'dialog data'}->{'text_input2_dialog'} = $this->object("text_input2_dialog_entry")->get_text();
	$this->object("text_input2_dialog_entry")->set_text('');
	#$dialog->close();
	
}

=pod

---+++ input_text_dialog_button_clicked_cancel

=cut

sub text_input2_dialog_button_clicked_cancel {
	my $this = shift;
	my ($btn,$label) = @_;
	
	my $this_subs_name = (caller(0))[3];
	print STDERR "Sub=$this_subs_name\n";


	my $dialog = $this->object("text_input2_dialog");
	$dialog->response(42);
		
	#my $current_text = $label->get_text();
	#print STDERR "Current Text=$current_text\n";
	
	#$current_text .= 'X';
	#$label->set_text($current_text);
}
	
=pod

---+++ text_input2_dialog Keypad

This keypad mimicks the ability of a typical cellphone to have multiple characters 
correspond to each key.  This is done by the user pressing a key (eg 2), and the keypad 
morphing to allow the selection of, for example, 	aAbBcC.

=cut

sub text_input2_dialog_button_clicked_1 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('1',@_);
}
sub text_input2_dialog_button_clicked_2 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('2',@_);
}
sub text_input2_dialog_button_clicked_3 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('3',@_);
}
sub text_input2_dialog_button_clicked_4 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('4',@_);
}
sub text_input2_dialog_button_clicked_5 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('5',@_);
}
sub text_input2_dialog_button_clicked_6 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('6',@_);
}
sub text_input2_dialog_button_clicked_7 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('7',@_);
}
sub text_input2_dialog_button_clicked_8 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('8',@_);
}
sub text_input2_dialog_button_clicked_9 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('9',@_);
}
sub text_input2_dialog_button_clicked_star {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('star',@_);
}
sub text_input2_dialog_button_clicked_0 {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('0',@_);
}
sub text_input2_dialog_button_clicked_pound {
	my $this = shift;	
	$this->text_input2_dialog_button_clicked_keypad('pound',@_);
}




# order: bottom 3 keys (*,0,#), 5, 1,2,3,6,9,8,7,4
# map state to keypad content
our $keypad_ref = {
	'2' => ['','','','2','a','A','b','B','c','C'],
	'3' => ['','','','3','d','D','e','E','f','F'],
	'4' => ['','','','4','g','G','h','H','i','I'],
	'5' => ['','','','5','j','J','k','K','l','L'],
	'6' => ['','','','6','m','M','n','N','o','O'],
	'7' => ['','','','7','p','P','q','Q','r','R','s','S'],
	'8' => ['','','','8','t','T','u','U','v','V'],
	'9' => ['','','','9','w','W','x','X','y','Y','z','Z'],
	'0' => ['','','','0','_','-','=','+','.',','],
	'1' => ['','','','1','$','&','%'],
	'original' => ['*','0','#',
		"5
(jkl)",
		"1
($&%)",
		"2
(abc)",
		"3
(def)",
		"6
(mno)",
		"9
(wxyz)",
		"8
(tuv)",
		"7
(pqrs)",
		"4
(ghi)",
	]
};

our $keypad_clockwise_order = {
	'star' => 0,'0' => 1,'pound' => 2,'5' => 3,'1' => 4,'2' => 5,
	'3' => 6,'6' => 7,'9' => 8,'8' => 9,'7' => 10,'4' => 11
};

=pod

---++++ text_input2_dialog_button_clicked_keypad($number,@_)

=cut



sub text_input2_dialog_button_clicked_keypad {
	my ($this,$number,$btn,$entry) = @_;
	
	my $this_subs_name = (caller(0))[3];
	#$logger->debug("Sub=$this_subs_name with keypress=$number");
	
	unless(defined $this->{'state'}->{'text_input2_dialog'}->{'keypad'}){
		$this->{'state'}->{'text_input2_dialog'}->{'keypad'} = 'original';
	}
	
	if($this->{'state'}->{'text_input2_dialog'}->{'keypad'} eq 'original'){
		# use has pressed key, so bring up the detail menu with characters for input
		$this->input_dialog_change_keys("text_input2_dialog",$number);
		return undef;
	}
	else{
		# user has pressed key, now needs to select character
		# with $number, find out what the content is
		if(
			defined $keypad_ref->{$this->{'state'}->{'text_input2_dialog'}->{'keypad'}}
			&& defined $keypad_ref->{$this->{'state'}->{'text_input2_dialog'}->{'keypad'}}->[$keypad_clockwise_order->{$number}]
		){
			return $this->text_input2_dialog_entry_change_text(
				$keypad_ref->{$this->{'state'}->{'text_input2_dialog'}->{'keypad'}}->[$keypad_clockwise_order->{$number}]
			);
		}
		else{
			return $this->text_input2_dialog_entry_change_text('');
		}
	}
}

sub text_input2_dialog_entry_change_text {
	my $this = shift;
	my $key = shift;

	
	
	#my $subname = (caller(0))[3];
	#print STDERR "Sub=$subname Input={$key}\n";
	
	my $txtbox = $this->object( "text_input2_dialog_entry" );
	$txtbox->set_text($txtbox->get_text().$key);
	
	
	
	# http://search.cpan.org/dist/X11-GUITest/GUITest.pm
	
	# change keys to original
	$this->input_dialog_change_keys("text_input2_dialog",'original');
}


sub input_dialog_change_keys {
	my $this = shift;
	my $id = shift;
	return undef unless defined $id && $id =~ m/input/;
	my $key = shift;
	$key = 'original' unless defined $key;
	
	my $number = '1';
	
	
	return undef unless defined $keypad_ref->{$key};
	my @a = @{$keypad_ref->{$key}};
	
	# there are 12 buttons
	foreach my $i ('star','0','pound','5','1','2','3','6','9','8','7','4'){
#		$logger->debug("Label:".$id.'_label_'.$i);
		my $btn = $this->object($id.'_label_'.$i);
		my $x = shift(@a);
		if(defined $x){
			$btn->set_text($x);
		}
		else{
			$btn->set_text('');
		}
	}
	$this->{'state'}->{$id}->{'keypad'} = $key;
}


sub text_input2_dialog_button_clicked_delete {
	my $this = shift;
	#$this->text_input2_dialog_entry_change_text('original');
	
	my $txtbox = $this->object( "text_input2_dialog_entry" );	
	my $x = $txtbox->get_text();
	$x = substr($x,0,length($x) - 1);
	#chop($x);
	$txtbox->set_text($x);
}

sub text_input2_dialog_button_clicked_clear {
	my $this = shift;
	$this->text_input2_dialog_entry_change_text('original');
	
	my $txtbox = $this->object( "text_input2_dialog_entry" );
	$txtbox->set_text('');
}


=pod

---+++ text_input2_dialog_button_clicked_camera

Scan qr code.

=cut

sub text_input2_dialog_button_clicked_camera {
	my $this = shift;
	my ($btn,$label) = @_;
	
	my $this_subs_name = (caller(0))[3];
	print STDERR "Sub=$this_subs_name\n";
	# if we dont do this, when qrcode returns, the screen will be all greyed out
	#$this->object('main_menu')->hide();
	#$this->object('text_input2_dialog_entry')->hide();
	
	$this->scan_qr(sub{
		my ($t1,$qrcode) = @_;
		#$logger->debug("hello, got qrcode=$qrcode");
		#my $already_here_text = $t1->object('text_input2_dialog_entry')->get_text();
		#if(defined $already_here_text){
		#	$qrcode = $already_here_text.$qrcode;
		#}
		my $txtbox = $this->object( "text_input2_dialog_entry" );
		$txtbox->set_text($txtbox->get_text().$qrcode);
		#$t1->object('text_input2_dialog_entry')->set_text($qrcode);
		#$t1->object('main_menu')->show();
		#$t1->object('main_menu')->fullscreen();
		#$t1->object('text_input2_dialog')->show();
		#$t1->object('text_input2_dialog')->fullscreen();
	});
	
}

=pod

---+ IPC

=cut


=pod

---++ connect

Upon connection to the kgc, this process sends an view/home request to see if we need to login.  The dialog_login is triggered when an error is returned prompting us to log in.  

Keep trying to connect for 5 minutes.

=cut

sub connect {
	my $this = shift;
	
	# Splash Screen
	#$this->dialog_preconnect();
	$this->object('preconnection_dialog')->show();
	
	# check Kgc::General::HotKyubu for a connection path
	my ($socket,$timeout);
	
	$timeout = time() + 60*5; # 5 minute time out
	while(!( defined $socket && fileno($socket)) && time() < $timeout){
		$socket = IO::Socket::UNIX->new(
			Type => SOCK_STREAM(),
			Peer => '/var/run/kgc.hotkyubu.unix',#$this->path()
		) || $logger->error("cannot connect to unix socket. $!");
		#$this->dialog_preconnect();
		
		sleep 10;
	}
	die "cannot connect to kgc" unless defined $socket;
	$this->object('preconnection_dialog')->hide();
	
	$socket->blocking(0);
	$socket->autoflush(1);
	
	#$this->socket($socket);	

	$this->{'watchers'}->{$socket} = EV::io fileno($socket), EV::READ | EV::WRITE , sub {
		my ($w, $revents) = @_; # all callbacks receive the watcher and event mask
		my $t1 = $this;
		my $s1 = $socket;
		if($revents & EV::READ){
			$t1->on_read($s1,$w,$revents);
		}
		if($revents & EV::WRITE){
			$t1->on_write($s1,$w,$revents);
		}
		
	};
	$this->{'kgc socket'} = $socket;
	
	
	
	# test the connectiono and force the login to come up
	$this->send_request({'method' => 'view/home','params' => [0]});
}

=pod

---++ on_read

Read 8192 bytes from the socket, parse out responses and send it to receive_response.

Format:[4B, size][4B, nonce][body...]

=cut

sub on_read {
	my $this = shift;
	my ($socket,$watcher,$revents) = @_;
	
	my $size = 0;
	my $nonce = -1;
	my $response = '';
	
	# read in a message
	use POSIX qw(:errno_h);
	my $n = 0;
	my $i = 0;
	my $x = '';
	
	$i = sysread($socket,$x,8192,$n);
	if ( ! defined $i && ( $! == EAGAIN || $! == EWOULDBLOCK ) ) {
		
	}
	elsif(!defined $i){
		$logger->debug("socket has closed with fileno=".fileno($socket));
		#$this->finish();
		exit(1);
	}
	elsif($i == 0){
		# EOF!
		$logger->debug("socket has received an EOF");
		#$this->finish();
		$this->finish();
		
		exit(0);
	}
	$logger->debug("Read in $i bytes");
	$n += $i;
	
	# run thru what we got, see if there are any messages (aka responses)
	while(1){
		# do we have the size
		if($size > 0){
			# do we have the nonce
			if($nonce > -1){
				# do we have the body?
				if($n >= $size){
					# we have the body
					#$this->log("Have response=$nonce");
					# print body to screen
					#$this->display_job($nonce,substr($x,0,$size));
					$this->receive_response($socket,$nonce,substr($x,0,$size));
					#$this->screen("job_id=$nonce\n".substr($x,0,$size));
					substr($x,0,$size) = "";
					$n = $n - $size;
					$size = 0;
					$nonce = 0;
				}
				else{
					$logger->debug("still waiting for body bytes with size=$size and nonce=$nonce and n=$n");
					last;
				}
			}
			else{
				if($n > 4){
					# we are getting the nonce
					$nonce = unpack('L',substr($x,0,4));
					die "bad nonce" unless $nonce > -1;
					$logger->debug("Got nonce=$nonce");
					# TODO: match nonce with another nonce we have (make sure we getting good responses back)
					substr($x,0,4) = "";
					$n = $n -4;
				}
				else{
					# still waiting for nonce bytes
					#$this->log("still waiting for nonce bytes");
					last;
				}
			}
		}
		else{
			# we are getting the size
			if($n >= 4){
				$size = unpack('L',substr($x,0,4));
				$logger->debug("Got Size=$size");
				substr($x,0,4) = "";
				$n = $n -4;
			}
			else{
				#$this->log("still waiting for size bytes");
				last;
			}
		}
	}
}



=pod

---++ send_request($request,$callback)

Put a request on the write queue.

The $callback is called with the following args=($response).
The $this object must be embedded as a closure.

=cut

sub send_request {
	my ($this,$request,$callback) = @_;
	my @x = ($request);
	return undef unless defined $request && ref($request) eq 'HASH';
	if(defined $callback && ref($callback) eq 'CODE'){
		$logger->debug("Callback is CODE");
		$x[2] = $callback;
	}
	elsif(defined $callback){
		$logger->error("Callback is not a CODE block");
	}
	$x[1] = $this->nonce();
	$this->nonce_increment();
	
	unless(defined $this->{'send requests'}){
		$this->{'send requests'} = [];
	}
	
	# change event mask
	#foreach my $socket (keys %{$this->{'watchers'}}){
	#	
	#}
	$this->{'watchers'}->{$this->kgc_socket()}->events(EV::READ | EV::WRITE);

	# add cookie to request
	if(defined $this->{'cookie'} && $request->{'method'} ne 'api/login' ){
		$request->{'connection'}->{'cookie'} = $this->{'cookie'};	
		$logger->debug("Adding request");
		push(@{$this->{'send requests'}},\@x);
	}
	elsif($request->{'method'} eq 'api/login'){
		push(@{$this->{'send requests'}},\@x);
	}
	else{
		$logger->debug("no cookie, need to login");
		$this->dialog_login();
	}



}

=pod

---++ listeners

Sometimes, the kgc sends unsolicited messages to the client.  For example, the kgc sends gpg --card-status updates to the client in order for the client to know the latest number of signatures.

=cut


=pod

---+++ listener_run($socket,$response_hash)

Run all callbacks corresponding to $method.

This subroutine is run in receive_response.

=cut

sub listener_run{
	my $this = shift;
	my ($socket,$response) = @_;
	my $method = $response->{'method'};
	return undef unless defined $method && length($method) > 0;
	
	
	if(
		defined $this->{'callbacks'}->{$method}
		&& ref($this->{'callbacks'}->{$method}) eq 'HASH'
		&& scalar(keys %{$this->{'callbacks'}->{$method}}) > 0
	){
		foreach my $index (keys %{$this->{'callbacks'}->{$method}}){
			$this->{'callbacks'}->{$method}->{$index}->($socket,$index,$response);
		}
	}
}

=pod

---+++ listener_add($method,$callback)

Add a listener to listen for unsolicited messages from the kgc.

Args in callback: ($index,$response)

=cut

sub listener_add{
	my $this = shift;
	my ($method,$callback) = @_;
	die "no method" unless defined $method && length($method) > 0;
	die "no callback" unless defined $callback && ref($callback) eq 'CODE';

	if(defined $this->{'callbacks'}->{$method}){
		my $n = scalar(keys %{$this->{'callbacks'}->{$method}});
		$this->{'callbacks'}->{$method}->{$n + 1} = $callback;
	}
	else{
		$this->{'callbacks'}->{$method}->{1} = $callback;
	}
	
}

=pod

---+++ listener_remove($method,$index)

Remove one callback reachable at:
	 $this->{$socket}->{'callbacks'}->{$method}->{$index};

=cut

sub listener_remove{
	my ($this,$method,$index) = @_;
	die "no method" unless defined $method && length($method) > 0;
	if(defined $index){
		delete $this->{'callbacks'}->{$method}->{$index};	
	}
	else{
		delete $this->{'callbacks'}->{$method};
	}
}


=pod

---++ process

If an error occurs in the middle of a process, we need to ignore future callbacks and exit back to the main_menu (or other $parent_window).

=cut

=pod

---+++ process_set($process,$parent_window)

Indicate what process we are in the middle of.  Some options include:
   * dialog_buybtc
   * dialog_sellbtc

=cut

sub process_set {
	my ($this,$process,$parent) = @_;
	$logger->debug("Setting current process to $process");
	$this->{'current process'} = $process;
	if(defined $parent && $this->object($parent)){
		$this->{'current process parent'} = $parent;
	}
	elsif(defined $parent){
		$logger->error("Parent not well defined, defaulting to main_menu");
		$this->{'current process parent'} = 'main_menu';
	}
	else{
		$this->{'current process parent'} = 'main_menu';
	}
}

=pod

---++ process_clear

Run this if we are done with a process.

=cut

sub process_clear {
	my ($this) = @_;
	$this->{'current process'} = '';
	$this->{'current process parent'} = 'main_menu';
}

=pod

---+++ process_check

Check what process we are in the middle of.  Some options include:
   * dialog_buybtc
   * dialog_sellbtc
   
Check dialog_error to see how this subroutine typically gets called.

=cut

sub process_check {
	my ($this,$process) = @_;
	if(defined $process && $this->{'current process'} eq $process ){
		return 1;
	}
	else{
		return 0;
	}
}

=pod

---+++ process_parent

Return the name of the window to which the gui needs to go back to in the event of an error.

=cut

sub process_parent {
	my ($this) = @_;
	
	return $this->{'current process parent'};
}


=pod

---++ on_write

When the event lool (epoll) says it is time to write to the socket, shift a request off of the request queue.
Then, go through a while loop and write the request out the socket.

on_write organizes the requests, while on_write_syswrite handles the syswrites.

Format: [4B, size][4B, nonce][body...]

Callbacks are also stored in tandem with the request being written.  Callbacks are organized by nonce.

See receive_response to see how callbacks are called.


=cut

sub on_write {
	my $this = shift;
	my ($socket,$watcher,$revents) = @_;
	
	use POSIX qw(:errno_h);
	
	# go through queue, write messages
	unless(defined $this->{$socket}->{'sending target'}){
		my $xref = shift(@{$this->{'send requests'}});

		my $request = $xref->[0];
		unless(defined $request){
			$logger->debug("no requests available, change to read only");
			$watcher->events(EV::READ);
			return undef;
		}
		
		my $nonce = $xref->[1];
		$logger->debug("Nonce=$nonce");
		
		my $target = JSON::XS::encode_json($request);
		$target = pack('L',length($target)).pack('L',$nonce).$target;
		
		$this->{$socket}->{'sending target'} = $target;
		$this->{$socket}->{'sending target bytes'} = 0;
		if(defined $xref->[2]){
			$logger->debug("Storing callback ".$xref->[1]);
			$this->{$socket}->{'callbacks'}->{$xref->[1]} = $xref->[2];
		}
		
		
	}
	
	$this->on_write_syswrite($socket);
	
}

sub on_write_syswrite {
	my ($this,$socket) = @_;
	my $target = $this->{$socket}->{'sending target'};
	
	my $n = $this->{$socket}->{'sending target bytes'};
	my $i = 0;
	# don't care about blocking here....so no select
	while($n < length($target)){
		$i = syswrite($socket,$target,8192,$n);
		if ( ! defined $i && ( $! == EAGAIN || $! == EWOULDBLOCK ) ) {
			$logger->debug("write socket is blocking");
			return undef;
		}
		elsif(!defined $i){
			$logger->debug("socket has closed with fileno=".fileno($socket));
			exit(1);
		}
		
		$i ||= 0;
		$logger->debug("Sending $i bytes to fileno=".fileno($socket));
		
		$n += $i;
	}
	
	if($n == length($target)){
		$logger->debug("Finished sending request");
		$this->{$socket}->{'sending target'} = undef;
		$this->{$socket}->{'sending target bytes'} = 0;
	}
	else{
		$logger->debug("Not finished sending request");
		$this->{$socket}->{'sending target bytes'} = $n;
	}
}


=pod

---++ kgc_socket


=cut

sub kgc_socket {
	return shift->{'kgc socket'};
}

=pod

---++ data_to_load

This contains data parsed from the login procedure.

=cut

sub data_to_load {
	return shift->{'data_to_load'};
}

=pod

---++ nonce

Nonce must be incremented for every request

=cut

sub nonce {
	return shift->{'nonce'};
}


=pod

---++ nonce_increment

Increment the nonce by 1

=cut

sub nonce_increment {
	my $this = shift;
	$this->{'nonce'} += 1;
	return $this->{'nonce'};
}


=pod

---++ create_qr_code_png($text)->$file_path

Create a png file.  Then return the file path.

TODO: create a regex to untaint $text

=cut

sub create_qr_code_png {
	my $this = shift;
	my $text = shift;
	my $scale = shift;
	$scale = 9 unless defined $scale;
	
	die "no text here" unless defined $text && length($text) > 1;
	
	my @chars = ('0'..'9',"A".."Z", "a".."z");
	my $string = '';
	$string .= $chars[rand @chars] for 1..8;
	
	if($string =~ m/^([0-9a-zA-Z]+)$/){
		$string = $1;
	}
	
	# create the image
	qrpng (text => $text, out => '/tmp/'.$string.'.png', scale => $scale);
	
	return '/tmp/'.$string.'.png';
}

=pod

---++ password

=cut

sub password {
	return shift->{'password'};
}

=pod

---++ format_satoshi($satoshi,$unit)

$unit =~ m/(BTC|mBTC)/

=cut

sub format_satoshi{
	my ($this,$satoshi,$unit) = @_;
	if(defined $this->{'Number::Format'}->{$unit}){
		my $x = $this->{'Number::Format'}->{$unit}->{'_divisor'};
		$x = 1.0/$x * $satoshi;
		return $this->{'Number::Format'}->{$unit}->format_number($x);		
	}
	else{
		$logger->error("bad unit");
		return $satoshi;
	}
	return shift->{'Number::Format'};
}

=pod

---++ convert_to_satoshi($satoshi,$unit)

$unit =~ m/(BTC|mBTC)/

=cut

sub convert_to_satoshi {
	my ($this,$amount,$unit) = @_;
	if(defined $this->{'Number::Format'}->{$unit}){
		return int(1.0*$amount / $this->{'Number::Format'}->{$unit}->{'_divisor'});
	}
	else{
		$logger->error("unit not defined");
		return $amount;
	}
}


=pod

---++ loop

Program exists after infinite loop.

=cut


sub loop {
	my $this = shift;

	$this->hook_pre_loop();

	#my $timer = EV::timer 1, 1, sub { print "I am here!\n" };
	$this->connect();

	#$builder = undef;
	Gtk3->main();
	
	exit;
}

=pod

---++ hook_pre_loop

=cut

sub hook_pre_loop {
	my $this = shift;
	$this->{'child pids'} = [];
	$logger->debug("running zbarcam");
	$this->hook_pre_loop_zbarcam();
	$this->hook_pre_loop_loadswiftcodes();
}

=pod

---++ hook_pre_loop_loadswiftcodes

Read the text files containing bank names.

$col = [
          '3000',
          '農林中央金庫',
          'NOCUJPJT',
          'NORINCHUKIN BANK THE'
        ];


=cut

sub hook_pre_loop_loadswiftcodes {
	my $this = shift;
	$logger->debug("looking for text file.");
	
	my $fp = module_directory().'/swift-codes.jp.txt';
	die "no swift codes" unless -f $fp;
	
	open(my $fh,'<',$fp) || die "cannot open swift codes file";
	my @codes;
	my $i = 0;
	# see special_object for formating of columns
	while(my $line = <$fh>){
		#$logger->debug("Line=$line");
		chomp($line);
		
		my @cols = split('	',$line);
		shift(@cols); # get rid of the index
		push(@codes,$cols[0]);
		$i++;
		last unless $i < 30;
	}
	$logger->debug("Got n=".scalar(@codes));
	$this->{'swift codes'}->{'Japan'} = \@codes;
	#my $x = $this->object('settings_depositbank_dialog');
	#my $bankstore = $this->object('simpelist_bank');
	#@{$bankstore->{data}} = @codes;

	close($fh);
}


=pod

---++ hook_pre_loop_zbarcam

Format:


=cut

sub hook_pre_loop_zbarcam {
	my $this = shift;
	use Socket;
	my ($parent,$child);
	socketpair($child,$parent,AF_UNIX,SOCK_STREAM,PF_UNSPEC)
            or die 'socketpair creation failure: '.$!;
	
	$parent->blocking(1);
	$parent->autoflush(1);
	$child->blocking(1);
	$child->autoflush(1);
	
	my $pid = fork();
	
	if($pid > 0){
		# parent
		close($child);
		push(@{$this->{'child pids'}},$pid);
		$logger->debug("Parent fileno=".fileno($parent));
		$this->{'zbarcam ids'} = [];

		$this->{'watchers'}->{$parent} = EV::io fileno($parent), EV::READ , sub {
			my ($w, $revents) = @_; # all callbacks receive the watcher and event mask
			my $t1 = $this;
			my $s1 = $parent;
			if($revents & EV::READ){
				$logger->debug("part 1");
				while(my $qrcode = <$s1>){
					$qrcode =~ s/\s//g;
					$logger->debug("part 2");
					my $callback = shift(@{$t1->{'zbarcam ids'}});
					$logger->debug("QR Code(id=$callback):$qrcode");
					
					eval{
						$callback->($t1,$qrcode);	
					};
					my $error = $@;
					if($error){
						$logger->error("Callback failed:$error");
					}
					else{
						$logger->debug("Callback successfully run");
					}
					last;
				}
				$logger->debug("part 3");
			}			
		};

		$this->{'zbarcam socket'} = $parent;
	}
	elsif($pid == 0){
		# child
		
		close($parent);
		open(STDOUT, ">&".fileno($child));
		$logger->debug("zbarcam child running");
		# if we recieve any lines, then scan the camera
		while(<$child>){
			$logger->debug("Received command=".$_);
			Kgc::Client::Gtk3GUI::getqrcode(30);
			#$x = '' unless defined $x && $x =~ m/^([0-9a-zA-Z]+)$/;
			#print $child "$x\n";
		}
		exit(0);
	}
	else{
		die "could not fork zbarcam";
	}
}


=pod

---+ receive_response

Once a response from the socket is received, we have this subroutine to figure out what to do with it.

   1. Check to see if we got a failure message.

=cut

sub receive_response {
	my ($this,$socket,$nonce,$response) = @_;
	
	
	
	$logger->debug(sub{
		require Data::Dumper;
		my $xo = Data::Dumper::Dumper($response);
		return "Response nonce=$nonce and XO=$xo\n\n";
	});
	
	eval{
		my $ref = JSON::XS::decode_json($response);
			die "need to login" if $ref->{'result'} eq 'no go';
		my $error_bool = 0;
		if(
			$ref->{'result'} eq 'error'
		){
			$logger->debug("got an error");
			$this->handle_error($ref);
			$error_bool = 1;
		}
		
		if(
			defined $nonce && -1 < $nonce  
		){
			# check for callbacks
			$logger->debug("Running a callback with nonce=$nonce");
			
			if(defined $this->{$socket}->{'callbacks'}->{$nonce}){
				$this->{$socket}->{'callbacks'}->{$nonce}->($ref);
				delete $this->{$socket}->{'callbacks'}->{$nonce};				
			}
			$this->listener_run($socket,$ref) unless $error_bool;
		}
		else{
			$logger->debug("handle stuff here with nonce=$nonce");
		}
		
	};
	my $error = $@;
	if($error eq 'need to login'){
		$this->dialog_login();
	}
	elsif($error){
		$logger->error("Have error=$error");
		$this->dialog_error('Error:'.$error,'main_menu',5);
	}
	else{
		$logger->debug("successfully responded");
	}
	
}

=pod

---++ message_info($message)->

Display info for either 15 seconds or until the user clicks OK.

Is this a duplicate of dialog_error?

=cut

sub message_info {
	my $this = shift;
	my $message = shift;
	return undef unless defined $message && length($message) > 0;
	my $timeout = shift;
	$timeout = 15 unless defined $timeout && $timeout =~ m/^\d+$/;
	

	
	my $dialog = Gtk3::MessageDialog->new (
		$this->object('main_menu'),
		'destroy-with-parent',
		'info', # message type
		'ok', # which set of buttons?
		$message
	);

	my $destroyself = sub{
		my $t1 = $this;
		my $d1 = $dialog;
		$t1->message_info_destroy($d1);
	};
	
	my $w = EV::timer( $timeout, 0, sub {
		$logger->debug("timeout called");
		$destroyself->();
	});
	$this->{'watchers'}->{$dialog} = $w;
	
	
	$dialog->signal_connect(
		'response' => sub{
			$destroyself->();
		}
	);
	$dialog->show();
	$dialog->fullscreen();
	
	return $dialog;
}

=pod

---++ message_info_destroy($dialog)

=cut

sub message_info_destroy{
	my $t1 = shift;
	$logger->debug("kill info window");
	my $d1 = shift;
	$d1->destroy();
	delete $t1->{'watchers'}->{$d1};
}

=pod

---++ message($message,{'x' => 1, ..})

A generalized message window;

=cut

sub message {
	my ($this,$options) = @_;
	
}

=pod

---+++ progress_message({'x' => 1, ..})

Show progress on an ongoing process.

$option = {
	'message' => 'Initiating settings.  Please wait.'
	,'progress' => 0 # anything between 0 and 100 is ok
	,'current task' => 'creating root account'
	,'parent' => $this->object("main_menu")
}

=cut

sub progress_message {
	my ($this,$options) = @_;
	# validate options
	$logger->debug("doing progress message - part 1");
	die "bad options" unless defined $options 
		&& ref($options) eq 'HASH' && defined $options->{'message'}
		&& defined $options->{'parent'};
	
	$options->{'current task'} = '' unless defined $options->{'current task'};
	$options->{'progress'} = 0 unless defined $options->{'progress'};
	die "bad progress" unless defined $options->{'progress'}
		&& $options->{'progress'} =~ m/^(\d+)$/ && $options->{'progress'} >= 0
		&& $options->{'progress'} <= 100;
	$logger->debug("doing progress message - part 2");
	# get the window
	my $id = 'progress_dialog';
	my $dialog = $this->object($id);	
	$dialog->set_transient_for($options->{'parent'});
	$logger->debug("doing progress message - part 3");
	# set text and progress
	$this->object($id.'_label_top')->set_label($options->{'message'});
	$this->object($id.'_label_bottom')->set_label($options->{'current task'});
	$this->object($id.'_progressbar')->set_fraction( $options->{'progress'}/100.0 );
	$logger->debug("doing progress message - part 3");
	$dialog->signal_connect (
		response => sub {
			return $_[0]->hide;
		}
	);
	$logger->debug("doing progress message - part 4");
	$dialog->show();
	$dialog->fullscreen();
	$logger->debug("doing progress message - part 5");
	#my $resp = $dialog->run();
	#$logger->debug("doing progress message - part 6");
	return $dialog;
}

sub progress_message_update {
	my ($this,$options) = @_;
	
	die "no options specified" unless defined $options && ref($options) eq 'HASH';
	$logger->debug("part 1");
	if(defined $options->{'progress'} && $options->{'progress'} =~ m/^(\d+)$/ 
		&& $options->{'progress'} >= 0
		&& $options->{'progress'} <= 100 
	){
		$logger->debug("change progress");
		$this->object('progress_dialog_progressbar')->set_fraction($options->{'progress'}/100.0);
	}
	elsif(defined $options->{'progress'}){
		die "bad progress";
	}

	if(defined $options->{'message'}){
		$logger->debug("change message");
		$this->object('progress_dialog_label_top')->set_label($options->{'message'});
	}
	
	if(defined $options->{'current task'}){
		$logger->debug("change task");
		$this->object('progress_dialog_label_bottom')->set_label($options->{'current task'});
	}
	# see text_input2_dialog_button_clicked_ok for response codes
	if(defined $options->{'response'} && $options->{'response'} eq 'ok'){
		# means "OK"
		$logger->debug("got ok response");
		$this->object('progress_dialog')->response(4);
		$this->object('progress_dialog')->hide();
		return 'ok';
	}
	elsif(defined $options->{'response'} && $options->{'response'} eq 'cancel'){
		$logger->debug("got cancel response");
		$this->object('progress_dialog')->response(42);
		$this->object('progress_dialog')->hide();
		return 'cancel';		
	}
	$logger->debug("part 4");
}

sub progess_dialog_button_cancel_clicked_cb {
	my $this = shift;
	$logger->debug("cancel button clicked");
	
}

=pod

---++ handle_error($response)

This subroutine kicks off the restoration procedure upon receiving _error="no accounts"_ response.

=cut

sub handle_error {
	my $this = shift;
	my $response = shift;
	if($response->{'error'} eq 'no accounts'){
		# need to initiate restore procedure
		$logger->error("initializing restore procedure");
		#$this->dialog_error('Initializing restore procedure','main_menu');
		#$this->dialog_restore_choice('main_menu');
		$this->dialog_restore();
	}
	elsif($response->{'error'} eq 'bad password'){
		$logger->error("bad password");
		$this->dialog_error('Error:'.$response->{'error'},'dialog_login',5);
	}
	else{
		$logger->error("got an error ".$response->{'error'});
		$this->dialog_error('Error:'.$response->{'error'},'main_menu',5);
	}
}


=pod

---++ handle_signature_count($index,$response)

   * Input:<verbatim>
{
	"method": "update signature account",
	"status": {
		"ssb>  2048R/0900B0D3  created: 2015-11-18  expires": "2020-11-16",
		"PIN retry counter": "3 0 3",
		"Signature counter": "26",
		"Sex": "unspecified",
		"ssb>  2048R/D2C8310A  created: 2015-11-18  expires": "2020-11-16",
		"Signature PIN": "forced",
		"Manufacturer": "ZeitControl",
		"sec#  2048R/E8AA2671  created: 2015-11-18  expires": "2020-11-16",
		"General key info": "pub  2048R/0900B0D3 2015-11-18 Customer Two <customer002@kyubu.bit>",
		"Login data": "[not set]",
		"Key attributes": "2048R 2048R 2048R",
		"Signature key": "6895 DBCA 4775 94D5 ED57  6799 C1EF 3E36 0900 B0D3",
		"card-no": "0005 00001A76",
		"Max. PIN lengths": "32 32 32",
		"ssb>  2048R/43A75FDE  created: 2015-11-18  expires": "2020-11-16",
		"Authentication key": "AB51 64C9 2155 5761 E469  3340 FD13 FCC1 D2C8 310A",
		"Language prefs": "de",
		"Private DO 2": "[not set]",
		"created": "2015-11-18 14:07:46",
		"Name of cardholder": "[not set]",
		"Application ID": "D276000124010200000500001A760000",
		"URL of public key": "[not set]",
		"Version": "2.0",
		"Encryption key": "D0FE AC29 FDE2 783C 62CA  1555 D84C DFC0 43A7 5FDE",
		"Private DO 1": "[not set]",
		"Serial number": "00001A76"
	}
}
   </verbatim>

=cut

sub handle_signature_count {
	my $this = shift;
	my $response = shift;
	
	if(
		defined $response && ref($response) eq 'HASH'
		&& defined $response->{'status'}
		&& defined $response->{'status'}->{'Signature counter'}
		&& $response->{'status'}->{'Signature counter'} =~ m/^(\d+)$/
	){
		# 
		# $response->{'Signature counter'}
		$this->signature_count($1);
	}
	elsif(
		defined $response->{'status'}
		&& defined $response->{'status'}->{'Signature counter'}	
	){
		$logger->error("bad format for signature counter");
	}
	
	
	
}

=pod

---++ signature_count

Returns the number of signatures done so far on the OpenPGP smart card.

This also updates the current_index if the signature count is higher.

=cut

sub signature_count {
	my ($this,$x) = @_;
	if(defined $x && $x =~ m/^(\d+)$/){
		$this->{'signature count'} = $1;
		
		if($this->current_index() < $this->{'signature count'}){
			$this->current_index($this->{'signature count'});
		}
		$logger->debug("Changing signature count to i=".$this->{'signature count'});
	}
	elsif(defined $x){
		die "bad format for signature count";
	}
	else{
		return $this->{'signature count'};
	}

	
}

=pod

---++ current_index

This is the index number used on child_ids for new addresses generated.

=cut

sub current_index {

	my ($this,$x) = @_;
	if(defined $x && $x =~ m/^(\d+)$/){
		$this->{'current index'} = $1;
		$logger->debug("Changing current index to i=".$this->{'current index'});
	}
	elsif(defined $x){
		die "bad format for current index";
	}
	else{
		return $this->{'current index'};
	}

}

=pod

---++ scan_qr($callback)

Send a request to the zbar child process, and get it to scan a qr code.

See hook_pre_loop_zbarcam to see how the callback is executed.

=cut

sub scan_qr {
	my $this = shift;
	my $callback = shift;
	$callback = sub{$logger->debug("got back response from zbar")} unless defined $callback;
	
	push(@{$this->{'zbarcam ids'}},$callback);
	my $fh = $this->{'zbarcam socket'};
	
	print $fh "scan\n";
	$logger->debug("Sending command to get qr code");
}

=pod

---++ Tx Related

=cut



=pod

---+ view

=cut

=pod

---++ view/home


http://search.cpan.org/~tvignaud/Gtk3-SimpleList-0.15/lib/Gtk3/SimpleList.pm

=cut

sub view_home {
	my $this = shift;
	$this->send_request({
			'method' => 'view/home',
			'params' => [1]
		},
		sub{
			my $t1 = $this;
			$logger->debug("running callback for view/home");
			$t1->view_home_callback(shift);
		}
	);
}


sub view_home_callback {
	my $this = shift;
	my $response = shift;
	require Data::Dumper;
	my $xo = Data::Dumper::Dumper($response);
	$logger->debug("$xo");
	
	# populate top level account tree
	
	$this->{'settings'} = $response->{'settings'};
}


=pod

---+ api

=cut

=pod

---++ api/xyz

=cut

1;

__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Kgc::Client::Gtk3GUI - GUI for debian-kgc

=head1 SYNOPSIS

  use Kgc::Client::Gtk3GUI;
  my $app = Kgc::Client::Gtk3GUI->new("ice-kyubu.glade");
  $app->loop();
  

=head1 DESCRIPTION

This GUI runs full screen and interacts with debian-kgc over a unix socket.

=head2 EXPORT

None by default.



=head1 SEE ALSO

debian-kgc

=head1 AUTHOR

Joel DeJesus (Work email), E<lt>dejesus.joel@e-flamingo.jp<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Joel DeJesus

This software is not free software.  All rights reserved.


=cut
