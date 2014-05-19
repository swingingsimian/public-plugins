=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::Web::Object::Tools;

### Base class for all the Tools based objects
### Avoid using an instance of this class, use child classes instances by calling get_sub_object() method

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);

use EnsEMBL::Web::Exceptions;
use EnsEMBL::Web::Tools::RandomString qw(random_string);
use EnsEMBL::Web::Tools::FileSystem qw(create_path remove_empty_path copy_dir_contents);

use parent qw(EnsEMBL::Web::Object);

sub caption               { return 'Tools'; } # override in child class
sub long_caption          { return 'Tools'; } # override in child class

sub short_caption {
  ## Caption for the tab
  ## @return 'Tools' for landing page, or 'Blast' or 'VEP' for tools specific pages and 'Blast result' etc if current page is not tools related
  my ($self, $global) = @_;
  my $hub = $self->hub;

  # If page is not Tools related
  if ($hub->type ne 'Tools' && $global && $global eq 'global') {
    my $job       = $self->get_requested_job;
    my $ticket    = $job && $job->ticket;
    my $job_count = $ticket && $ticket->job_count;
    return $job && $job->status eq 'done' ? sprintf('%s results: %s'.($job_count > 1 ? ' (%s)' : ''), $ticket->ticket_type_name, $ticket->ticket_name, $job->job_number) : 'Jobs';
  }

  my $sub_object = $self->get_sub_object;
  return $self eq $sub_object ? 'Tools' : $sub_object->ticket_type; # generic /Tools page or Blast/VEP pages
}

sub default_action {
  ## URL action part of the tools tab
  ## @return Current action for all tools page, link to the Results page for external pages if the url contains a valid job id
  my $self  = shift;
  my $hub   = $self->hub;

  return join '/', $hub->action || (), $hub->function || () if $hub->type eq 'Tools';

  my $job   = $self->get_requested_job;

  return $job && $job->status eq 'done' ? sprintf '%s/%s', $job->ticket->ticket_type_name, 'Results' : '';
}

sub get_sub_object {
  ## Gets the actual web object according to the 'action' part of the url
  ## @param Object type if action part is missing or invalid
  ## @return Blast or VEP web object if available for the hub->action (or the param provided), Tools object otherwise
  my $self = shift;
  my $type = shift || $self->hub->action || '';
  return $self->{"_sub_object_$type"} ||= $type && ref $self eq __PACKAGE__ && $self->new_object($type, {}, $self->__data) || $self;
}

sub ticket_type {
  ## @abstract method
  ## Should return the ticket type as saved in ticket_type table
  throw exception('AbstractMethodNotImplemented');
}

sub ticket_class {
  ## Class name for the ticket object
  ## @return package name
  my $self = shift;
  return $self->dynamic_use_fallback('EnsEMBL::Web::Ticket::'.$self->ticket_type, 'EnsEMBL::Web::Ticket');
}

sub create_url_param {
  ## Creates a URL param from the given ticket or job
  ## The purpose of keeping these three params in one URL param is to prevent losing this info when clicking around the tabs on ensembl page
  ## @param Hashref with keys ticket_name, job_id and result_id
  ## If no key is provided, it returns current valid 'tl' param
  ## If only 'result_id' is provided, it uses ticket_name and job_id from current URL
  ## If only 'job_id' is provided, it uses ticket_name from the current URL
  my ($self, $params) = @_;

  if (!$params->{'ticket_name'}) {
    my $ex_params = $self->parse_url_param;
    if (!$params->{'job_id'}) {
      if (!$params->{'result_id'}) {
        $params->{'result_id'} = $ex_params->{'result_id'};
      }
      $params->{'job_id'} = $ex_params->{'job_id'};
    }
    $params->{'ticket_name'} = $ex_params->{'ticket_name'};
  }

  throw exception('ParamRequired', 'Ticket name is needed to create URL param') unless $params->{'ticket_name'};
  return join '-', grep $_, $params->{'ticket_name'}, $params->{'job_id'}, $params->{'result_id'};
}

sub parse_url_param {
  ## Reverse of create_url_param
  ## @return Hashref with keys: ticket_name OR job_id OR job_id and result_id
  my $self = shift;

  unless (exists $self->{'_url_param'}) {

    my @param = split '-', $self->hub->param('tl') || '';

    $self->{'_url_param'} = {
      'ticket_name' => $param[0],
      'job_id'      => $param[1],
      'result_id'   => $param[2]
    };
  }

  return $self->{'_url_param'};
}

sub get_job_dispatcher {
  ## Gets new or cached job dispatcher
  ## @return EnsEMBL::Web::JobDispatcher subclass
  my ($self, $ticket_type) = @_;

  $ticket_type ||= $self->ticket_type;

  unless ($self->{'_job_dispatcher'}) {

    my $dispatcher  = ($self->hub->species_defs->ENSEMBL_TOOLS_JOB_DISPATCHER || {})->{$ticket_type};

    throw exception('WebToolsException', "Job dispatcher for ticket type $ticket_type not configured.") unless $dispatcher;

    $dispatcher = $self->dynamic_use_fallback("EnsEMBL::Web::JobDispatcher::$dispatcher");
    $dispatcher = $dispatcher->new($self->hub);

    $self->{'_job_dispatcher'} = $dispatcher;
  }

  return $self->{'_job_dispatcher'};
}

sub generate_ticket_name {
  ## Generates a unique ticket name
  ## @return String of length same as the column's allowed length for ticket name
  my $self    = shift;
  my $manager = $self->rose_manager(qw(Tools Ticket));
  my $length  = $manager->object_class->meta->column('ticket_name')->length;
  my $name    = '';

  while (!$name || !$manager->is_ticket_name_unique($name)) {
    $name = random_string($length);
  }

  return $name;
}

sub delete_ticket_or_job {
  ## Deletes a ticket (or just a job linked to a ticket) according to the URL params
  ## @return 1 if deleted successfully, undef if there was a problem
  my $self    = shift;
  my $params  = $self->parse_url_param;

  my ($ticket_type, $ticket, $job);

  # if job_id is provided, it's a request to delete the job (not the parent ticket)
  if ($params->{'job_id'}) {

    $job = $self->get_requested_job;

    if ($job) {

      # if there's only one job linked to a ticket, mark the ticket for removal
      $ticket       = $job->ticket;
      $ticket_type  = $ticket->ticket_type_name;
      $ticket       = undef if $ticket->job_count > 1;
    }

  # if job_id is missing, but ticket_name is provided, it's a request to the ticket
  } elsif ($params->{'ticket_name'}) {
    $ticket       = $self->get_requested_ticket;
    $ticket_type  = $ticket->ticket_type_name if $ticket;
  }

  return unless $ticket || $job;

  # get the path of the related directory that needs to be removed
  ($job) = $ticket->job if !$job && $ticket;
  my @dir_path = $job ? split /\//, $job->job_dir : ();
  pop @dir_path if !$dir_path[-1];       # trailing slash
  pop @dir_path if $ticket && @dir_path; # this is to get the parent directory for all jobs (required if removing a ticket)

  # get the dispatcher job ids of the jobs that need to be removed
  my @dispatcher_references = map { $_ && $_->dispatcher_reference || () } $ticket ? $ticket->job : $job;

  # after deleting the ticket or the job successfully, remove the directories, and the dispatched jobs
  if ($ticket ? $ticket->delete : $job && $job->delete) {

    # remove dispatched jobs
    $self->get_job_dispatcher($ticket_type)->delete_jobs($ticket_type, @dispatcher_references) if @dispatcher_references;

    # remove dirs
    remove_empty_path(join('/', @dir_path), { 'remove_contents' => 1, 'exclude' => [ $ticket_type ], 'no_exception' => 1 }) if @dir_path; # ignore any error - files left orphaned will eventually get removed.

    return 1;
  }
}

sub save_ticket_to_account {
  ## Saves a ticket to the logged-in user account
  ## @return 1 if saved successfully, undef if there was a problem
  my $self = shift;
  my $result;

  if (my $ticket = $self->get_requested_ticket) {

    my $ticket_type = $ticket->ticket_type_name;
    my %dirs;

    for ($ticket->job) {
      my $old_job_dir = $_->job_dir or next;
      my $new_job_dir = $old_job_dir =~ s/temporary/persistent/r;

      next if $new_job_dir eq $old_job_dir; # very unlikely, but you never know!

      # make the new directory path to copy the files across
      try {
        create_path($new_job_dir); #mkdir $new_job_dir
        copy_dir_contents($old_job_dir, $new_job_dir); #cp job_dir/* new_job_dir/
        $dirs{$old_job_dir} = $new_job_dir;
      } catch {

        # rollback if it failed somewhere i.e. remove all the new dirs
        remove_empty_path($_, { 'remove_contents' => 1, 'exclude' => [ $ticket_type ], 'no_exception' => 1 }) for values %dirs; # ignore any error

        throw $_;
      };

      # change the job_dir column value for the job object
      $_->job_dir($new_job_dir);
    }

    $ticket->owner_id($self->hub->user->user_id);
    $ticket->owner_type('user');

    $result = $ticket->save('cascade' => 1);

    # now we have two copies of the ticket dir, remove the one not required
    remove_empty_path($_, { 'remove_contents' => 1, 'exclude' => [ $ticket_type ], 'no_exception' => 1 }) for $result ? keys %dirs : values %dirs;
  }

  return $result;
}

sub get_current_tickets {
  ## Gets (and caches) all the current tickets either for the logged in user or the session
  ## @return Arrayref of ticket objects
  my $self = shift;

  unless (exists $self->{'_current_tickets'}) {
    my $hub     = $self->hub;
    my $user    = $hub->user;
    my $action  = $hub->action;

    my $ticket_types  = $self->rose_manager(qw(Tools TicketType))->fetch_with_current_tickets({
      'site_type'       => $hub->species_defs->ENSEMBL_SITETYPE,
      'session_id'      => $hub->session->session_id, $user ? (
      'user_id'         => $user->user_id ) : (), ref $self ne __PACKAGE__ ? ( # If object is Tools, show all tickets
      'type'            => $self->ticket_type) : ()
    });

    my @tickets = sort { $b->created_at <=> $a->created_at } map $_->ticket, @$ticket_types;
    $self->update_jobs_from_dispatcher(\@tickets);
    $self->{'_current_tickets'} = \@tickets;
  }

  return $self->{'_current_tickets'};
}

sub get_requested_ticket {
  ## Gets a ticket object from the database with param from the URL and caches it for subsequent requests
  ## @return Ticket rose object, or undef if not found or if ticket does not belong to logged-in user or session
  my $self = shift;

  unless (exists $self->{'_requested_ticket'}) {
    my $hub         = $self->hub;
    my $user        = $hub->user;
    my $ticket_name = $self->parse_url_param->{'ticket_name'};
    my $ticket;

    if ($ticket_name) {
      my $ticket_type = $self->rose_manager(qw(Tools TicketType))->fetch_with_current_tickets({
        'site_type'     => $hub->species_defs->ENSEMBL_SITETYPE,
        'ticket_name'   => $ticket_name,
        'session_id'    => $hub->session->session_id, $user ? (
        'user_id'       => $user->user_id ) : ()
      });

      if (@$ticket_type) {
        $ticket = $ticket_type->[0]->ticket->[0];
        $self->update_jobs_from_dispatcher([ $ticket ]);
      }
    }

    $self->{'_requested_ticket'} = $ticket;
  }

  return $self->{'_requested_ticket'};
}

sub update_jobs_from_dispatcher {
  ## Updates jobs linked to the given tickets from the corresponding ones in the dispatcher
  ## @param Arrayref of Ticket objects to which jobs are linked
  ## @return No return value
  my ($self, $tickets) = @_;

  $self->get_job_dispatcher($tickets->[0]->ticket_type_name)->update_jobs( [ map { grep {$_->status eq 'awaiting_dispatcher_response'} $_->job } @$tickets ] );
}

sub get_requested_job {
  ## Gets the job object according to the URL param
  ## @param Hashref with one of the following keys
  ##  - 'with_all_results'      Flag if on, will get all results linked to the job object
  ##  - 'with_requsted_result'  Flag if on, will only get the result object with ID in the URL 'tl' param
  ## @return Job object, or undef if no job found for the given id, or job doesn't belong to the logged in user or current session, or requested result doesn't belong to the job
  my ($self, $params) = @_;

  my $key = [ map { $params->{$_} ? "_requested_job_$_" : () } qw(with_all_results with_requested_result) ]->[0] || '_requested_job';

  unless (exists $self->{$key}) {
    my $hub         = $self->hub;
    my $user        = $hub->user;
    my $url_params  = $self->parse_url_param;
    my $job;

    if (my $job_id = $url_params->{'job_id'}) {

      my %results_key = $params->{'with_all_results'}
        ? ('result_id' => 'all')
        : ($params->{'with_requested_result'}
          ? ('result_id' => $url_params->{'result_id'})
          : ()
        );

      my $ticket_type = $self->rose_manager(qw(Tools TicketType))->fetch_with_given_job({
        'site_type'     => $hub->species_defs->ENSEMBL_SITETYPE,
        'ticket_name'   => $url_params->{'ticket_name'},
        'job_id'        => $job_id,
        'session_id'    => $hub->session->session_id, $user ? (
        'user_id'       => $user->user_id ) : (), ref $self ne __PACKAGE__ ? ( # If object is Tools, it could be any ticket being requested
        'type'          => $self->ticket_type) : (),
        %results_key
      });

      if ($ticket_type) {
        my $ticket = $ticket_type->ticket->[0];
        $self->update_jobs_from_dispatcher([ $ticket ]); # this will only update the required job but not all jobs linked to the ticket since only one job was actually fetched by providing job_id
        $job = $ticket->job->[0];
      }
    }

    $self->{$key} = $job;
  }

  return $self->{$key};
}

sub get_edit_jobs_data {
  ## @abstract
  ## Gets the data needed by JS for populating the input form while editing a ticket
  ## @return Arrayref of hashes, each corresponding to one of the multiple jobs being edited
  throw exception('AbstractMethodNotImplemented');
}

sub get_tickets_data_for_sync {
  ## Gets the data for all the current tickets as required by the ticket list page to refresh the page
  ## @return Tickets data hashref and auto refresh flag
  my $self          = shift;
  my $tickets       = $self->get_current_tickets;
  my $tickets_data  = {}; 
  my $auto_refresh  = undef; # this is set true if any of the jobs has status 'awaiting_dispatcher_response'

  if ($tickets && @$tickets) {

    for (@$tickets) {

      my $ticket_name = $_->ticket_name;

      for ($_->job) {
        $auto_refresh = 1 if $_->status eq 'awaiting_dispatcher_response';
        $tickets_data->{$ticket_name}{$_->job_id} = $_->dispatcher_status;
      }
    }
  }

  return (md5_hex($self->jsonify($tickets_data)), $auto_refresh);
}

sub handle_download {
  ## @override
  ## Handles the download request, and calls the handle_download method of the required sub object
  my $self = shift;
  return $self->get_sub_object->handle_download(@_);
}

sub get_time_now {
  # Gets the current time in a format that can be saved in the db
  my ($sec, $min, $hour, $day, $month, $year) = localtime;
  return sprintf '%d-%02d-%02d %02d:%02d:%02d', $year + 1900, $month + 1, $day, $hour, $min, $sec;
}

sub format_date { ## TODO ??? move to root?
  my ($self, $datetime) = @_;
  return unless $datetime;

  my @date = split(/-|T|:/, $datetime);
  $datetime = sprintf('%s/%s/%s, %s:%s',
    $date[2],
    $date[1],
    $date[0],
    $date[3],
    $date[4]
  );
  return $datetime;
}

1;
