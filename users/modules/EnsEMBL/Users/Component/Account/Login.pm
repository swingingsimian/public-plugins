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

package EnsEMBL::Users::Component::Account::Login;

### Component for User Login page
### @author hr5

use strict;

use base qw(EnsEMBL::Users::Component::Account);

sub caption {
  return sprintf 'Login to %s', shift->site_name;
}

sub content {
  my $self = shift;
  return $self->js_section({'subsections' => [ $self->login_form->render ]});
}

sub login_form {
  my ($self, $is_ajax)  = @_;
  my $object            = $self->object;
  my $hub               = $self->hub;
  my $form              = $self->new_form({'id' => 'login', 'action' => {qw(action User function Authenticate)}});
  my $then_param        = $is_ajax ? '' : $self->get_then_param;
  my $ex_email          = $is_ajax ? '' : $hub->param('email');

  $form->add_hidden({ 'name' => 'then',      'value' => $then_param       }) if $then_param;
  $form->add_hidden({ 'name' => 'modal_tab', 'value' => 'modal_user_data' });
  $form->add_field([
    {'type'  => 'Email',    'name'  => 'email',     'label' => 'Email',     'required' => 'yes', $ex_email ? ('value' => $ex_email) : ()},
    {'type'  => 'Password', 'name'  => 'password',  'label' => 'Password',  'required' => 'yes'},
    {'type'  => 'Submit',   'name'  => 'submit',    'value' => 'Log in',    'notes'    => sprintf('<p><a href="%s" class="modal_link">Lost password</a> | <a href="%s" class="modal_link">Register</a></p>',
      $hub->url({qw(action Password function Lost), $ex_email ? ('email' => $ex_email) : ()}),
      $hub->url({qw(action Register)})
    )}
  ]);

  return $form;
}

1;