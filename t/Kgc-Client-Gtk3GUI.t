# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Kgc-Client-GtkGUI.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 1;

ok(1,'cannot test gui here');

#BEGIN { use_ok('Kgc::Client::Gtk3GUI') };


#chdir(Kgc::Client::Gtk3GUI::module_directory());
#warn "Dir=".Kgc::Client::Gtk3GUI::module_directory()."\n";
#my $app = Kgc::Client::Gtk3GUI->new(
#	Kgc::Client::Gtk3GUI::module_directory()
#);
#warn "Hello-----------\n";
#$app->loop();


=cut

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

