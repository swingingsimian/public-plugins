package EnsEMBL::Web::Object::Healthcheck;

use strict;

use DBI;

use base qw(EnsEMBL::Web::Object);

sub view_type         { return shift->{'_view_type'}; }
sub view_param        { return shift->{'_view_param'}; }
sub view_title        { (my $title = ucfirst ($_[1] || $_[0]->{'_view_type'})) =~ s/_/ /g; return $title; }
sub first_release     { return shift->{'_first_release'}; }
sub current_release   { return shift->{'_curr_release'}; }
sub requested_release { return shift->{'_req_release'}; }
sub compared_release  { return shift->{'_cmp_release'}; }
sub available_views   { return {'DBType' => 'database_type', 'Database' => 'database_name', 'Testcase' => 'testcase', 'Species' => 'species', 'Team' => 'team_responsible'}; }
sub last_session_id   { return shift->_get_session_id('last'); }
sub first_session_id  { return shift->_get_session_id('first'); }

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  
  $self->{'_view_type'}     = $self->available_views->{$self->function};
  $self->{'_view_param'}    = $self->function eq 'Species' ? ($self->hub->species eq 'common' ? '' : $self->hub->species) : $self->hub->param('q');
  $self->{'_first_release'} = $SiteDefs::ENSEMBL_WEBADMIN_HEALTHCHECK_FIRST_RELEASE;
  $self->{'_curr_release'}  = $self->hub->species_defs->ENSEMBL_VERSION;
  $self->{'_req_release'}   = $self->hub->param('release') || $self->current_release;
  $self->{'_req_release'}   = 0 if $self->{'_req_release'} < $self->{'_first_release'} || $self->{'_req_release'} > $self->{'_curr_release'};
  $self->{'_cmp_release'}   = $self->hub->param('release2') || 0;
  $self->{'_cmp_release'}   = 0 if $self->{'_cmp_release'} < $self->{'_first_release'} || $self->{'_cmp_release'} > $self->{'_curr_release'};

  return $self unless $self->{'_req_release'};
  
  my $method = lc 'fetch_for_'.($self->action || $self->default_action);
  
  $self->$method if $self->can($method);

  return $self;
}

sub fetch_for_summary {
  ## Healthcheck summary page
  my $self = shift;

  my $session = $self->rose_manager('Session')->fetch_single($self->requested_release);
  my $groupby = [qw(database_type database_name species testcase team_responsible)];

  if ($session) {
    $self->rose_objects($session);
    $self->rose_objects('reports', $self->rose_manager('Report')->count_failed_for_session({
      'session_id' => $session->session_id,
      'group_by'   => $groupby
    }));

    if (my $compared = $self->compared_release) {
      if ($compared = $self->rose_manager('Session')->fetch_single($compared)) {
        $self->rose_objects('compare_reports', $self->rose_manager('Report')->count_failed_for_session({
          'session_id' => $compared->session_id,
          'group_by'   => $groupby
        }));
      }
    }
  }
}

sub fetch_for_details {
  ## Healthcheck details page
  my $self = shift;
  
  if ($self->view_type && $self->view_param) {
    $self->rose_objects('reports', $self->rose_manager('Report')->fetch_for_session({
      'session_id'        => $self->last_session_id,
      'with_users'        => 1,
      'with_annotations'  => 1,
      'query'             => [$self->view_type, $self->view_param]
    }));
  }
  else {
    $self->rose_objects('reports', $self->rose_manager('Report')->count_failed_for_session({
      'session_id' => $self->last_session_id,
      'group_by'   => [ $self->view_type ]
    }));
  }
}

sub fetch_for_annotation {
  ## Annotation display page and saving command
  my $self = shift;

  my $report_ids = $self->hub->param('rid');
  $report_ids    = [ split ',', $report_ids ] if $report_ids;
  
  if ($report_ids && @$report_ids) {
    $self->rose_objects($self->rose_manager('Report')->fetch_by_primary_keys($report_ids, {
      'with_objects' => 'annotation',
      'with_users'   => ['annotation.created_by', 'annotation.modified_by']
    }));
  }
}

sub fetch_for_database {
  ## Database list page
  my $self = shift;

  if (my $last_session_id = $self->last_session_id) {
    my $first_session_id = $self->first_session_id || 0;
    $self->rose_objects('session_reports', $self->rose_manager('Report')->fetch_for_distinct_databases({'last_session_id' => $last_session_id}));
    $self->rose_objects('release_reports', $self->rose_manager('Report')->fetch_for_distinct_databases({'last_session_id' => $last_session_id, 'first_session_id' => $first_session_id}));
  }
}

sub fetch_for_userdirectory {
  ## User directory
  my $self = shift;
  $self->rose_objects($self->rose_manager('Group')->fetch_with_members($self->hub->species_defs->ENSEMBL_WEBADMIN_ID, 1));
}

sub fetch_for_annotationsave {
  ## Saving annotations after editing/adding new
  my $self = shift;
  
  $self->fetch_for_annotation;
}

sub get_database_list {
  ## Gives list of all the current servers and their databases
  ## @return HashRef of 'server name' => {'species name' => [list of database names]}
  my $self = shift;

  $self->{'_hc_mysql_driver'} ||= DBI->install_driver('mysql');
  my $database_list = {};
  
  for my $server (@$SiteDefs::ENSEMBL_WEBADMIN_DB_SERVERS) {
    $database_list->{$server->{'host'}} = {};
    my @db_list = $self->{'_hc_mysql_driver'}->func($server->{'host'}, $server->{'port'}, $server->{'user'}, $server->{'pass'}, '_ListDBs');
    for (@db_list) {
      my $species = '2others'; #'2' prefixed for sorting - '2' keeps 'others' at the end instead of considering it alphabetically
      if ($_ =~ /_core|_otherfeatures|_cdna|_variation|_funcgen|_compara|_vega/) {
        $_ =~ /^([a-z]+_[a-z]+)/; #get species
        $species = '1'.$1 if $self->validate_species(ucfirst $1); #'1' prefixed for sorting -  keeps it always above 'others'
      }
      $database_list->{$server->{'host'}}{$species} ||= [];
      push @{$database_list->{$server->{'host'}}{$species}}, $_;
    }
  }
  return $database_list;
}

sub get_default_list {
  ## Returns an arrayref of default list of testcases, species or databases required to display in the page
  ## @param View type (optional - defaults to current view type)
  ## @param View function (optional - defaults to current hub->function)
  ## @return ArrayRef of strings
  my ($self, $type, $function) = @_;

  $type      ||= $self->view_type;
  $function  ||= $self->function;
  
  if ($function =~ /^Database|Testcase$/) {
    return [] unless $self->first_session_id;
    my $method = lc "fetch_for_distinct_${function}s";
    return [ keys %{{ map {$_->$type => 1} @{$self->rose_manager('Report')->$method({'last_session_id' => $self->last_session_id, 'first_session_id' => $self->first_session_id}) || []} }} ];
  }
  elsif ($function eq 'Species') {
    return $self->hub->species_defs->ENSEMBL_DATASETS || [];
  }
  elsif ($function eq 'DBType') {
    return [qw(cdna core funcgen otherfeatures production variation vega)];
  }
  elsif ($function eq 'Team') {
    return [qw(COMPARA CORE GENEBUILD FUNCGEN RELEASE_COORDINATOR)];
  }
  return [];
}

sub validate_release {
  ## Private helper method
  ## Validates whether or not the given release can have healthchecks
  my ($self, $release) = @_;

  return $release >= $self->first_release && $release <= $self->current_release;
}

sub validate_species {
  ## Validates whether the given string is species or not
  my ($self, $species) = @_;
  
  $self->{'_valid_species'} ||= { map {$_ => 1} @{ $self->hub->species_defs->ENSEMBL_DATASETS || [] } };
  return $self->{'_valid_species'}->{$species} || 0;
}

sub _get_session_id {
  ## gets first or last session id for requested release
  my ($self, $which) = @_;
  exists $self->{"_${which}_session"} and return $self->{"_${which}_session"};
  my $s = $self->rose_manager('Session')->fetch_single($self->requested_release, $which);
  return $s ? ($self->{"_${which}_session"} = $s->session_id) : undef;
}

1;