package EnsEMBL::Users::Component::Account::Bookmark::AddEdit;

### Component to edit bookmark
### @author hr5

use strict;

use base qw(EnsEMBL::Users::Component::Account);

sub content {
  my $self          = shift;
  my $object        = $self->object;
  my $hub           = $self->hub;
  my $user          = $hub->user;
  my $is_add_new    = $hub->function eq 'Add';

  if (my ($bookmark, $record_owner) = $object->fetch_bookmark_with_owner( $is_add_new ? 0 : ($hub->param('id'), $hub->param('group')) )) {

    my $form = $self->new_form({'action' => $hub->url({qw(action Bookmark function Save)})});

    $form->add_hidden({'name' => 'id',        'value' => $bookmark->record_id });
    $form->add_hidden({'name' => 'object',    'value' => $bookmark->name || $hub->referer->{'ENSEMBL_TYPE'} }) if $is_add_new;

    $form->add_field({'type'  => 'string',    'name'  => 'name',        'label' => 'Bookmark name',       'value' => $bookmark->name        || $hub->param('name')      || '',  'required' => 1 });
    $form->add_field({'type'  => 'string',    'name'  => 'shortname',   'label' => 'Short description',   'value' => $bookmark->shortname   || $hub->param('shortname') || ''});
    $form->add_field({'type'  => 'text',      'name'  => 'url',         'label' => 'Bookmark URL',        'value' => $bookmark->url         || $hub->param('url')       || '',  'required' => 1 });

    my $buttons_field = {'type' => 'submit', 'name' => 'button', 'value' => $is_add_new ? 'Add' : 'Save'};

    # add these extra fields for a shared bookmark (group record)
    if ($record_owner->RECORD_TYPE eq 'group') {

      $form->add_hidden({'name' => 'group', 'value' => $record_owner->group_id});

      if ($user->is_admin_of($record_owner) || $bookmark->created_by eq $user->user_id) {

        $buttons_field = {'inline' => 1, 'elements' => [{'type' => 'submit', 'name' => 'save', 'value' => 'Save'}, {'type' => 'submit', 'name' => 'save_new', 'value' => 'Save as new'}]};

      } else {
        $form->add_notes({'location' => 'head', 'heading' => 'Info', 'text' => q(You can't modify the existing bookmark, so this will be saved as a new bookmark.)});

      }
    }

    $form->add_field($buttons_field);

    return $form->render;

  } else {

    my $bookmarks = $hub->user->bookmarks;

    # display form to select a bookmark if no group was specified
    return $self->js_section({
      'heading'     => 'Edit bookmark',
      'subsections' => [ @$bookmarks ? $self->select_bookmark_form({
        'bookmarks'   => $bookmarks,
        'action'      => $hub->url({'action' => 'Bookmark', 'function' => 'Edit'}),
        'label'       => 'Select a bookmark to edit',
        'submit'      => 'Edit'
      })->render : $self->no_bookmark_message(1) ]
    });
  }
}

1;