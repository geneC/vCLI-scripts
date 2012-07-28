#!/usr/bin/perl

#
# Copyright 2012 Gene Cumm <gene.cumm@gmail.com>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
#   Boston MA 02111-1307, USA; either version 2 of the License, or
#   (at your option) any later version; incorporated herein by reference.
#

use strict;
use warnings;

my $debug = 0;
my $stime = 10;

use Switch;
use VMware::VIRuntime;
use VMware::VILib;
use VMware::VIExt;


my %opts = (
	# esxcli uses -s for --server
   host => {
      alias => "H",
      type => "=s",
      help => qq!  The managed entity (vCenter / ESX(i) host; an alias for --server). !,
      required => 0,
   },
	# esxcli uses -h for --vihost
   vihost => {
      alias => "h",
      type => "=s",
      help => qq!  The host to use when connecting via a vCenter Server. !,
      required => 0,
   },
   user => {
      alias => "u",
      type => "=s",
      help => qq!  The username to use against the managed entity (alias for --username). !,
      required => 0,
   },
   pass => {
      alias => "p",
      type => "=s",
      help => qq!  The password to use against the managed entity (alias for --password). !,
      required => 0,
   },
   'status-all' => {
      type => "",
      help => qq!  Queries the status of all services on the host!,
      required => 0,
   },
   'list' => {
      alias => 'l',
      type => "",
      help => qq!  Lists the services!,
      required => 0,
   },
   'policy' => {
      type => "=s",
      help => qq!  Sets the startup policy (on/off/automatic)!,
      required => 0,
   },
   'v' => {
      type => ":s",
      help => qq!  Verbose output!,
      required => 0,
   },
   'debug' => {
      alias => 'd',
      type => ":s",
      help => qq!  Debug output!,
      required => 0,
   },
);

Opts::add_options(%opts);
dprint2("Options added\n");
Opts::parse();
dprint2("Options parsed\n");

my $status_all = Opts::get_option('status-all');
my $list = Opts::get_option('list');
my $policy = Opts::get_option('policy');

my $host = Opts::get_option('host');
my $server;
if (defined($host)) {
	Opts::set_option('server', $host);
	$server = $host;
} else {
	$server = Opts::get_option('server');
	$host = $server;
}
my $vihost = Opts::get_option('vihost');
if (defined($vihost)) {
	$host = $vihost;
}
my $user = Opts::get_option('user');
if (defined($user)) {
	Opts::set_option('username', $user);
}
my $pass = Opts::get_option('pass');
if (defined($pass)) {
	Opts::set_option('password', $pass);
}

my $verbose = Opts::get_option('v');
if (defined($verbose)) {
	Opts::set_option('verbose', $verbose);
} else {
	$verbose = Opts::get_option('verbose');
}
if (Opts::option_is_set('debug')) {
	my $idbg = Opts::get_option('debug');
	if ($idbg eq "") { $idbg = 1;}
	if ($idbg > $debug) { $debug = int($idbg); }
}
if ($debug) {
	print "debug=$debug\n";
}

my $svcid;	# Service ID

print "--Server: '" . $server . "'\n";
if (defined($vihost)) {
	print "  --viHost: '" . $vihost . "'\n";
}

Opts::validate();
dprint2("Options validated\n");

Util::connect();
dprint2("Util::connect()\n");
if ($debug >= 2) {
	# no need to call this for now outside of debugging
	$svc_cont = get_service_content($svc_cont);
	my $abt = $svc_cont->about;
	dprint2("    Version: '" . $abt->version . "' 'b" . $abt->build . "'\n");
}


my $host_view = get_host_view_serviceSystem();
Opts::assert_usage(defined($host_view), "Invalid host.");
dprint("  Host name: '" . $host_view->{'name'} . "'\n");

sub svc_main_host{
	if (defined($vihost)) {
		print "  --viHost: '" . $vihost . "'\n";
	}
	$host_view = get_host_view_serviceSystem();
	dprint2("get_host_view_serviceSystem()-done\n");
	Opts::assert_usage(defined($host_view), "Invalid host: '$host'.");
	if ($debug >= 1) {
		dprint("  Host name: '" . $host_view->{'name'} . "'\n");
	}
	if ($debug >= 2) {
		$host_prod = get_host_product($host_view);
		dprint2("Got host product\n");
		dprint2("    Version: '" . $host_prod->version . "' '" . $host_prod->build . "'\n");
	}

	$host_svc = get_host_serviceSystem($host_view);

	$services = $host_svc->{serviceInfo}->{service};

	svc_main();
}
my $host_svc = get_host_serviceSystem($host_view);
my ($service, $services);

sub svc_main {
	if (defined($status_all)) {
		print_service_status_all($host_svc, $services, "  ");
	} elsif (defined($list)) {
		list_services_all($host_svc, $services, "  ");
	} elsif ($#ARGV >= 0) {
		svc_cmd(@ARGV);
	} else {
		Opts::usage();
	}
}

$services = $host_svc->{serviceInfo}->{service};
if (defined($status_all)) {
	print_service_status_all($host_svc, $services, "  ");
} elsif (defined($list)) {
	list_services_all($host_svc, $services, "  ");
} elsif ($#ARGV >= 0) {
	my $isvc = $ARGV[0];
	$svcid = $isvc;
	my $valid = 1;
	if ($#ARGV == 0) {
		if (!defined($policy)) {	$valid = 0;	}
	} else {
		my $cmd = $ARGV[1];
		my $valcmd = 1;
		switch ($cmd) {
			case "restart"	{
				print "Restarting '" . $svcid . "': ";
				restart_service($host_svc, $svcid, $service);	}
			case "start"	{
				print "Starting '" . $svcid . "': ";
				start_service($host_svc, $svcid, $service);	}
			case "status"	{ }
			case "stop"	{ 
				print "Stopping '" . $svcid . "': ";
				stop_service($host_svc, $svcid, $service); }
			else		{ $valcmd = 0; }
		}
		if (!$valcmd) {
			print "Command '" . $cmd . "' not valid\n";
			$valid = 0;
		}
	}
	if ($valid) {
		if (defined($policy)) {
			set_service_policy($host_svc, $svcid, $policy);
		}
		$host_svc = get_host_serviceSystem($host_view);
		get_print_service_status($host_svc, $svcid, $service, "  ");
	} else {
		Opts::usage();
	}
} else {
	Opts::usage();
}

sub get_service_content {
	if (defined($_[0]) && UNIVERSAL::isa($host_svc, 'ServiceContent')) {
		return $_[0];
	} else {
		return Vim::get_service_content();
	}
}

# Disconnect from the server
Util::disconnect();

sub get_host_view_serviceSystem {
	if (!($verbose || $debug)) {
		return VIExt::get_host_view(1, ['configManager.serviceSystem']);
	} elsif ($debug < 2) {
		return VIExt::get_host_view(1, ['configManager.serviceSystem', 'name']);
	} else {
		return VIExt::get_host_view(1, ['configManager.serviceSystem', 'name', 'config']);
	}
}

#	use this instead of $host_svc->RefreshServices(); since it doesn't
#	  appear to work; HostServiceSystem->RefreshServices()
sub get_host_serviceSystem {
	my ($host_view) = @_;
	return Vim::get_view (mo_ref => $host_view->{'configManager.serviceSystem'});
# 	return Vim::get_view (mo_ref => $host_view->configManager->serviceSystem);
}

sub get_host_product {
	my ($host_view) = @_;
	# config is not a managed object
# 	return Vim::get_view(mo_ref => $host_view->{'config.product'});
	return $host_view->config->product;
}

sub cmd_ok {
	return ($_[0] =~ /^(query|restart|start|status|stop)$/);
}

# Present continuous indicative
sub cmd_conj_pci {
	my ($c, $cpci) = @_;
	if (defined($cpci)) {	return $cpci;	}
	if (defined($c)) {
		switch($c) {
		case /^(query|restart|start)$/	{ return $c . "ing"; }
		case "stop"	{ return "stopping"; }
		}
	}
}

# Present perfect indicative
sub cmd_conj_ppi {
	my ($c, $cppi) = @_;
	if (defined($cppi)) {	return $cppi;	}
	if (defined($c)) {
		switch($c) {
		case /^(query|restart|start)$/	{ return $c . "ed"; }
		case "stop"	{ return "stopped"; }
		}
	}
}

sub cmd2state_cur {
	return run2st(cmd2run_cur(@_));
}

sub cmd2state_opp {
	return run2st(cmd2run_opp(@_));
}

sub cmd2run_cur {
	if (defined($_[0])) {
		switch($_[0]) {
		case "start"	{ return 0; }
		case /^(stop|restart)$/	{ return 1; }
		else		{ return; }
		}
	}
}

sub cmd2run_opp {
	if (defined($_[0])) {
		switch($_[0]) {
		case "start"	{ return 1; }
		case /^(stop|restart)$/	{ return 0; }
		else		{ return; }
		}
	}
}

sub run2st {
	return (defined($_[0]) ? ($_[0] ? "running" : "stopped") : "");
}

sub cmd2func {
	my ($c) = @_;
	if (defined($c) && ($c =~ /^(restart|start|stop)$/)) {
		return ucfirst($c) . "Service";
	}
	return;
}

sub service_command_print {
	my ($host_svc, $svcid, $service, $c, $cpci, $cppi) = @_;
	my $ret;
	if (!defined($c)) {
		printerr("No command specified\n");
		return;
	}
	if (!cmd_ok($c)) {
		printerr("Unknown command '$c'\n");
		return;
	}
	get_service_verify_fail($host_svc, $svcid, $service);
	print "Service '$svcid' " . cmd_conj_pci($c) . ":  ";
	$ret = service_command($host_svc, $svcid, $service, $c, $cpci, $cppi);
	if ($ret == 0) {
		print "\tdone.\n";
	} else {	#error message printed in service_command()
	}
}

sub service_command {
	my ($host_svc, $svcid, $service, $c, $cpci, $cppi) = @_;
	my $ret = 0;
	if (!defined($c)) {
		printerr("No command specified\n");
		return;
	}
	if (!cmd_ok($c)) {
		printerr("Unknown command '$c'\n");
		return;
	}
	dprint2("service_command('$svcid', '$c')\n");
	$cpci = cmd_conj_pci($c, $cpci);
	dprint2("  $cpci\n");
	get_service_verify_fail($host_svc, $svcid, $service);
	$_[2] = $service;
	if (($service->running) != cmd2run_cur($c)) {
		print("\nService '$svcid' is currently " . run2st($service->running) . " but should be " . run2st($service->running ? 0 : 1) . " for command '$c'\n");
		return 2;
	} else {
		dprint2("Service '$svcid' is currently " . run2st($service->running) . "\n");
	}
	my $func = cmd2func($c);
	dprint2($func . "(", $svcid, "): ");
	eval { $host_svc->$func(id => $svcid); };
	if ($@) {
	  $ret = svc_err($@, $svcid, $c) + 1;
	} else {
		dprint2(cmd_conj_ppi($c, $cppi) . "\n");
	}
	return $ret;
}

sub restart_service {
	my ($host_svc, $svcid, $service) = @_;
	get_service_verify_fail($host_svc, $svcid, $service);
	$_[2] = $service;
	if ($service->running) {
		dprint2("Service '" . $svcid . "' is currently running\n");
	} else {	# on v5,stopped may be restarted
		dprint2("Service '" . $svcid . "' is currently stopped\n");
	}
	dprint2("RestartService(", $svcid, "): ");
	eval { $host_svc->RestartService(id => $svcid); };
	if ($@) {
	  my $kf = 0;	# known fault
	  if (ref($@) eq 'SoapFault') {
	    if (defined $@->{name}) {
		if ($@->{name} eq 'InvalidStateFault') {
			$kf = 1;
			print "Service '" . $svcid . "': Invalid state for restart; likely stopped\n";
		}
	    }
	  }
	  if ($kf == 0) {
		print "Error restarting '" . $svcid . "': {" . $@ . "}\n";
	  }
	} else {
		dprint2("Restarted\n");
	}
}

sub start_service {
	my ($host_svc, $svcid, $service) = @_;
	get_service_verify_fail($host_svc, $svcid, $service);
	$_[2] = $service;
	if ($service->running) {
		print "Service '" . $svcid . "': already running\n";
		return;
	} else {
		dprint2("Service '" . $svcid . "' is currently stopped\n");
	}
	dprint2("StartService(", $svcid, "): ");
	eval { $host_svc->StartService(id => $svcid); };
	if ($@) {
	  my $kf = 0;	# known fault
	  if (ref($@) eq 'SoapFault') {
	    if (defined $@->{name}) {
		if ($@->{name} eq 'InvalidStateFault') {
			$kf = 1;
			print "Service '" . $svcid . "': Invalid state for start; likely running\n";
		}
	    }
	  }
	  if ($kf == 0) {
		print "Error starting '" . $svcid . "': {" . $@ . "}\n";
	  }
	} else {
		dprint2("Started\n");
	}
}

sub stop_service {
	my ($host_svc, $svcid, $service) = @_;
	get_service_verify_fail($host_svc, $svcid, $service);
	$_[2] = $service;
	if (! $service->running) {
		print "Service '" . $svcid . "': already stopped\n";
		return;
	} else {
		dprint2("Service '" . $svcid . "' is currently running\n");
	}
	dprint2("StopService(", $svcid, "): ");
	eval { $host_svc->StopService(id => $svcid); };
	if ($@) {
	  my $kf = 0;	# known fault
	  if (ref($@) eq 'SoapFault') {
	    if (defined $@->{name}) {
		if ($@->{name} eq 'InvalidStateFault') {
			$kf = 1;
			print "Service '" . $svcid . "': Invalid state for stop; likely stopped\n";
		}
	    }
	  }
	  if ($kf == 0) {
		print "Error stopping '" . $svcid . "': {" . $@ . "}\n";
	  }
	} else {
		dprint2("Stopped\n");
	}
}

sub set_service_policy {
	my ($host_svc, $id, $p) = @_;	# policy
	eval { $host_svc->UpdateServicePolicy(id=>$id, policy=>$p); };
	if ($@) {
		print "Error setting service '" . $id . "' to policy '" . $p . "': {" . $@ . "}\n";
	}
}

sub get_print_service_status {
	my ($host_svc, $svcid, $service, $p) = @_;
	if ((!defined($service)) || ($service->key ne $svcid)) {
		$service = get_service(($host_svc, $svcid));
	}
	if (defined($service)) {
		print_service_status($service, $p);
	} else {
		print $svcid . " not found\n";
	}
	$_[2] = $service;	# passback
}

sub get_service_verify_fail {
	my ($host_svc, $svcid, $service) = @_;
	if (!defined($svcid)) {
		VIExt::fail("ERROR in get_service_verify_fail():Empty \$svcid\n");
	}
	if ((!defined($service)) || ($service->key ne $svcid)) {
		$service = get_service(($host_svc, $svcid));
	}
	if (!defined($service)){
		VIExt::fail("No service '" . $svcid . "' found\n");
	}
	$_[2] = $service;
}

sub get_service {
	my ($host_svc, $svcid) = @_;
	if (!defined($svcid)) {
		dprint2("get_service(): No \$svcid\n");
		return;
	}
	if (!defined($host_svc) || !UNIVERSAL::isa($host_svc, 'HostServiceSystem')) {
		dprint2("get_service(): \$host_svc not valid\n");
		return;
	}
	my $service;
	my $services = $host_svc->{serviceInfo}->{service};
	foreach(@$services) {
		dprint2("Found service '" . $_->key . "'\n");
		if ($_->key eq $svcid) {
			$service = $_;
			dprint2("got it\n");
		}
	}
	return $service;
}

sub list_services_all {
	my ($host_svc, $services, $p) = @_;
	print "Found: ";
	foreach(@$services) {
		print "'", $_->key, "' ";
	}
	print "\n";
}

sub print_service_status_all {
	my ($host_svc, $services, $p) = @_;
	foreach(@$services) {
		print_service_status($_, $p);
	}
}

sub print_service_status {
	my ($sv, $p) = @_;	# service, line prefix
	if (!defined($p)) { $p = "" }
	if (defined($sv) && UNIVERSAL::isa($sv, 'HostService')) {
		print $p . "'" . $sv->key . "' is " . (($sv->running) ? "running" : "stopped") . " with policy of '" . $sv->policy . "'\n";
	}
}

# Error handler
#	svc_err($@, $svcid, $c);
sub svc_err {
	my ($err, $svcid, $c) = @_;
	my $kf = 0;	# known fault
	if (ref($err) eq 'SoapFault') {
	  if (defined $err->{name}) {
		if ($err->{name} eq 'InvalidStateFault') {
			$kf = 1;
			printerr("Service '$svcid': Invalid state for $c; "
			  . "likely " . cmd2state_opp($c) . "; previously detected as " . $service->running . "\n");
		} elsif ($err->{name} eq 'RestrictedVersionFault') {
			$kf = 2;
			printerr("Command not supported on free licenses\n");
		}
	  }
	}
	if ($kf == 0) {
		printerr("Error " . cmd_conj_pci($c) . " '$svcid': {$err}\n");
	}
	return $kf;
}

sub dprint {	if ($debug) {	print @_;	}	}
sub dprint2 {	if ($debug >= 2) {	print @_;	}	}
sub printerr {	print STDERR @_;	}


__END__
