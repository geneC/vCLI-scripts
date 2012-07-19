#!/usr/bin/perl

#
# Copyright 2012 Gene Cumm
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
   host => {
      alias => "H",
      type => "=s",
      help => qq!  The managed entity (vCenter / ESX(i) host; an alias for --server). !,
      required => 0,
   },
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
Opts::parse();

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


my $svcid;	# Service ID

print "--Server: '" . $host . "'\n";
if (defined($vihost)) {
	print "  --viHost: '" . $vihost . "'\n";
}

Opts::validate();

Util::connect();

my $host_view = get_host_view_serviceSystem();
Opts::assert_usage(defined($host_view), "Invalid host.");
dprint("  Host name: '" . $host_view->{'name'} . "'\n");

my $host_svc = get_host_serviceSystem($host_view);
my ($service, $services);

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


# Disconnect from the server
Util::disconnect();

sub get_host_view_serviceSystem {
	return VIExt::get_host_view(1, ['configManager.serviceSystem', 'name']);
}

#	use this instead of $host_svc->RefreshServices(); since it doesn't
#	  appear to work; HostServiceSystem->RefreshServices()
sub get_host_serviceSystem {
	my ($host_view) = @_;
	return Vim::get_view (mo_ref => $host_view->{'configManager.serviceSystem'});
# 	return Vim::get_view (mo_ref => $host_view->configManager->serviceSystem);
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
	if ((!defined($service)) || ($service->key ne $svcid)) {
		$service = get_service(($host_svc, $svcid));
	}
	if (!defined($service)){
		VIExt::fail("No service '" . $svcid . "'\n");
	}
	$_[2] = $service;
}

sub get_service {
	my ($host_svc, $svcid) = @_;
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

sub dprint {	if ($debug) {	print @_;	}	}
sub dprint2 {	if ($debug >= 2) {	print @_;	}	}
sub printerr {	print STDERR @_;	}


__END__
