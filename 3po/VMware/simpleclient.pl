#!/usr/bin/perl
use strict;
use warnings;
use VMware::VIRuntime;

# http://pubs.vmware.com/vsphere-50/index.jsp?topic=%2Fcom.vmware.perlsdk.pg.doc_50%2Fviperl_proggd_preface.2.1.html

my %opts = (
      entity => {
      type => "=s",
      variable => "VI_ENTITY",
      help => "ManagedEntity type: HostSystem, etc",
      required => 1,
      },
);
 
Opts::add_options(%opts);
Opts::parse();
Opts::validate();

Util::connect();

# Obtain all inventory objects of the specified type
my $entity_type = Opts::get_option('entity');
my $entity_views = Vim::find_entity_views(
      view_type => $entity_type);

# Process the findings and output to the console
 
foreach my $entity_view (@$entity_views) {
   my $entity_name = $entity_view->name;
   Util::trace(0, "Found $entity_type:    $entity_name\n");
}

# Disconnect from the server
Util::disconnect();
