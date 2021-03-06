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

package EnsEMBL::Selenium::Test::Blat;
use strict;
use base 'EnsEMBL::Selenium::Test::Species';
use Test::More; 

__PACKAGE__->set_default('timeout', 50000);
#------------------------------------------------------------------------------
# Ensembl Blat test
# Can add more cases or extend the existing test cases
#------------------------------------------------------------------------------
sub test_blat {
  my ($self) = @_;
  my $sel    = $self->sel;
  my $SD     = $self->get_species_def;    
  my $sp_bio_name = $SD->get_config($self->species,'SPECIES_BIO_NAME'); 
  
  if(lc($self->species) eq 'dasypus_novemcinctus' || lc($self->species) eq 'ochotona_princeps') {
    print "  BLAT DISABLED FOR ".$self->species."\n";
  } else { 
    $self->open_species_homepage($self->species,undef,$sp_bio_name);
    $sel->ensembl_click_links(["link=Example transcript"],"50000");
    $sel->ensembl_click_links(["link=cDNA","link=BLAST this sequence"],"20000");
   
    print "  Running BLAT(dna) for ".$self->species."\n";  
    $sel->click_ok("name=stage_results_run")
    and $sel->ensembl_wait_for_page_to_load  
    and $sel->ensembl_is_text_present("Alignment Locations vs. Karyotype")
    and $sel->ensembl_is_text_present("Start");  
  }

  print "TESTING BLASTP \n";  
  $self->open_species_homepage($self->species,undef, $sp_bio_name);
  $sel->ensembl_click_links(["link=Example transcript"],"50000");
  $sel->ensembl_click_links(["link=Protein","link=BLAST this sequence"],"20000");  
  
  print "  Running BLASTP for ".$self->species."\n";  
  $sel->click_ok("name=stage_results_run")
  and $sel->ensembl_wait_for_page_to_load;
  
  # wait for a minute and check if the result came back.
  $sel->pause('60000');
  $sel->ensembl_click("name=_retrieve")
  and $sel->ensembl_wait_for_page_to_load;
  
  my $result = $sel->get_eval(qq{
    \var \$ = selenium.browserbot.getCurrentWindow().jQuery; 
    \$('*:contains("RawResult")');
  });
  
  # if no result came back wait for another 30sec and check again (break out of the loop if it's taking too long)
  my $counter;
  while(!$result) {    
    last if($counter eq '2');
    $sel->pause('30000');
    $sel->ensembl_click("name=_retrieve")
    and $sel->ensembl_wait_for_page_to_load;
    
    $result = $sel->get_eval(qq{
      \var \$ = selenium.browserbot.getCurrentWindow().jQuery; 
      \$('*:contains("RawResult")');
    });
    $counter++;
  }  
  $sel->ensembl_is_text_present("RawResult");   #double check if RawResult link is present
  print "  Clicking on RawResult \n";
  
  my $result_link = $sel->get_eval(qq{
    \var \$ = selenium.browserbot.getCurrentWindow().jQuery; 
    \$('a[target^=BLAST_RESULT]').attr('href');
  });
  
  $sel->open_ok($result_link);
  $sel->pause(2000);
  $sel->ensembl_is_text_present("Sequences producing");
}
1;