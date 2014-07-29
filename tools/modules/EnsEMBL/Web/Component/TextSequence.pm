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

package EnsEMBL::Web::Component::TextSequence;

use strict;
use warnings;

use previous qw(buttons);

sub buttons {
  my $self    = shift;
  my $hub     = $self->hub;
  my $input   = $hub->input;
  my @buttons = $self->PREV::buttons(@_);

  if ($hub->type ne 'Tools') {
    push @buttons, {
      'caption'   => 'BLAST this sequence',
      'url'       => $hub->url({qw(type Tools action Blast)}),
      'class'     => 'blast hidden _blast_button'
    };
  }

  return @buttons;
}

1;
