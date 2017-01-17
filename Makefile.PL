use strict;
use warnings;
use ExtUtils::MakeMaker;
#use File::ShareDir::Install;

eval 'use ExtUtils::MakeMaker::Coverage';



# Must handle v4l to get /dev/video0:
# so install libv4l-dev and sudo modprobe bcm2835-v4l2
#  libx11-dev libxtst-dev

#File::ShareDir::Install::install_share(module => 'Kgc::Client::Gtk3GUI', 'static');
#install_share 'static';
#install_share module => 'Kgc::Client::Gtk3GUI', 'static';
 
WriteMakefile(
	'NAME' => 'Kgc::Client::Gtk3GUI',
	'AUTHOR' => 'Joel DeJesus (Work email) <dejesus.joel@e-flamingo.jp>',
	'LICENSE' => 'Private',
	'LIBS' => [ ' -lzbar -lX11 -lXtst ' ],
	'VERSION_FROM' => 'lib/Kgc/Client/Gtk3GUI.pm',
	'ABSTRACT' => 'Get Kgc::Client::Gtk3GUI',
	'PREREQ_PM' => { # also, libperl-dev
		'Devel::PPPort' => 0, # libdevel-patchperl-perl
		'HTTP::Request' => 0, # libhttp-parser-perl
		'LWP::UserAgent' => 0, # liblwp-protocol-https-perl
		'MIME::Base64' => 0, # libmime-base64-urlsafe-perl
		'Digest::SHA' => 0, # libdigest-sha-perl
		'JSON::PP' => 0, # libjson-pp-perl
		'Image::PNG::QRCode' => 0, # libimage-png-qrcode-perl
		'MIME::Base64' => 0,  # libmime-base64-urlsafe-perl
		'Gtk3' => 0, # libgtk3-perl
		'Glib' => 0, # libglib-perl
		'Glib::EV' => 0, # libglib-ev
		'EV' => 0, # libev-perl
		'Gtk3::SimpleList' => 0 # libgtk3-simplelist-perl
	#	'X11::GUITest' => 0 # libx11-guitest-perl
	},
	,($ExtUtils::MakeMaker::VERSION >= 6.3002
	      ? ('LICENSE'=> 'gpl_3')
	      : ())
	,'PL_FILES'            => {},
	'EXE_FILES' => [
		'scripts/ice-kyub-gui'
	],
	,'dist'                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', }
	,'clean'               => { FILES => 'libkgc-client*' }
);

package MY;
#use File::ShareDir::Install qw(postamble);

# Remove the Makefile dependency. Causes problems on a few systems.
sub MY::makefile { '
static::
	mkdir -p $(INST_LIB)/auto/Kgc/Client/Gtk3GUI/icons
	$(CP) -r --remove-destination --verbose static/* $(INST_LIB)/auto/Kgc/Client/Gtk3GUI/
' }
#  -e 'pm_to_blib({@ARGV}, '\''$(INST_LIB)'\'')'

# $(NOECHO) $(ABSPERLRUN) -MExtUtils::Install -e \'pm_to_blib({@ARGV}, \'\\\'\'$(INST_LIB)\'\\\'\')\' -- $(INST_LIB)/auto/share/module/Kgc-Client-Gtk3GUI
