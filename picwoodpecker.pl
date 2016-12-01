#!/usr/bin/perl
use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use Tk;
use Tk qw(:eventtypes);
use Tk::JPEG;
use Tk::Pane;

use GD;
use Image::ExifTool qw(:Public);
use MIME::Base64;

use File::Spec;
use File::Copy;
use Fcntl;
use Time::Hires;

###
$|++;

# from GD docs:
# For backwards compatibility with scripts previous versions of GD, new
# images created from scratch (width, height) are palette based by default.
# To change this default to create true color images use:
# (somewhere before creating new images.)
# [it must unneeded for jpg but if you comment the following line you'll
#  get color noise]
GD::Image->trueColor(1);

################################################################################
# default configuration (that can be modified via command line parameters)
################################################################################
# source folder or glob expression to find jpg images
my $glob = './*.jpg';
# destination folder used when copying files
my $dest = '.';
# debug
my $debug = 0;
# ratio of the photo and of photo window
my $win_ratio=0.25;
my $ph_ratio= 0.25;
# index of last column and row(starting from 0(but -1 applpied after getopts!))
# used to display thumbs in a grid
my $grid_col = 6;
my $grid_row = 4;
# how many photos to preload after and before current one
my $preload = 1;
# do not load thumbnails at all!
my $nothumbs = 0;
# jpeg quality
my $jpeg_quality;
# output extension (jpg as commodity alias of jpeg)
my $out_ext = 'jpg';
# png compression factor (0-9)
my $png_compression;
# date format used by Image::ExifTool
my $date_format = '%Y_%m_%d_%H_%M_%S';
################################################################################
# Getoptions
################################################################################
unless (GetOptions (
                       "source|src|s=s"       => \$glob,
                       "destination|dest|d=s" => \$dest,
                       "debug!"               => \$debug,
                       "phratio|pr=f"         => \$ph_ratio,
                       "winratio|wr=f"        => \$win_ratio,
                       "gridx|x=i"            => \$grid_col,
                       "gridy|y=i"            => \$grid_row,
                       "preload|p=i"          => \$preload,
                       "nothumbs!"            => \$nothumbs,

                       "jpegquality|quality=i"=> \$jpeg_quality,
                       "extension|e=s"        => \$out_ext,
                       "pngcompression=i"=> \$png_compression,
                       "dateformat|df=s" => \$date_format,
                    )
        ) {
            print "GetOpt::Long returned errors (see above),".
                  "review available options:";
            pod2usage(-verbose => 1);
}
# sanitize destination path
$dest = &sanitize_dest($dest);
# adjust x and y for the grid (which is zero based)
$grid_col -= 1;
$grid_row -= 1;
################################################################################
# other global variables
################################################################################

# @files is ArrayOfArray
# each element contains pic data as follow:
# 0 path
# 1 x
# 2 y
# 3 orientation
# 4 datetime joined with underscores
# 5  GD object of THUMB
# 6  [ GD object of PHOTO]
# the last field [6] will be filled only for current file ( which index is hold in $ph_index)
# and for elelments to be preloaded: from ($ph_index - $preload)  to ($ph_index + $preload)
# thumb data [5] will be empty if $nothumbs is defined via -nothumbs commandline switch
my @files;
# @prepost is filled and cleared by next_pic
# it holds indexes of file preloaded
my @prepost;
# is the current index of photo list (@files)
my $ph_index = 0;
# display mode
my $display_mode = $nothumbs ? 'photo' : 'thumbs';
# status of loading and copying operations
my $status = "- status informations -";
# used to jump to a photo
my $gotonum;
# autoplay
my $toggle_autoplay = 0;
# seconds interval during autoplay
my $autoplay_sleep_interval = 3.0;
# the timer to do autoplay
my $tk_timer;
#
my $mw = new MainWindow ();
# output window used for big photos and thumbnails
# see  http://www.perlmonks.org/?node_id=1172209
# to know why secondary windows is not yet created
  my $phwin;
# the frame used in the photo window
  my $scrolledframe;
# main big photo Tk::Photo object
  my $tk_ph_image ;
# the label container of the current photo
  my $photo_label;

# rows of thumbnails
my @temp_frames;
# curent thumbnails
my @temp_thumbs;

# help text window
my $hw;
# ADVANCED OPTIONS USED TO COPY AND POSTPROCESS PHOTOS
# advanced copy options TopLevel window
my $advw;
# allow files copied to replace file already present
my $allow_overwrite = 1;
# bypass original file GD elaboration, simply copying it
my $bypass_orig_el = 0;
# jpeg quality label
my $jpeg_quality_lbl;
# jpeg quality entry
my $jpeg_quality_ent;
# enable multi copies off by default
my $enable_multiple_copies = 0;
# skip original image
my $skip_orig = 0;
# skip original label
my $skip_orig_lbl;
# checkbutton associated to the above
my $skip_orig_chk;
# the pattern used to have multiple copies (800x600 1024x768 ..)
my $multi_pattern = '';
# pattern label
my $multi_pattern_lbl;
# entry widget for the above
my $multi_pattern_ent;
# enable post process of copied images off by default
my $enable_postprocess = 0;
my $exiftool_path = '';
my $exiftool_args = '';
# widget used by the above
my ($post_prog_lbl, $post_prog_btn,
    $post_prog_ent, $post_prog_arg_lbl, $post_prog_arg_ent);
# a lookup table for all global bindings that use chars:
# used to prevent Entry widgets to invoke callbacks when inappropriate
# see http://www.perlmonks.org/?node_id=1173808
my %bind_table = (
   '<space>' => sub{&copy_with_name},
   '<KeyRelease-question>' => \&help_me,
   '<KeyRelease-p>' => \&autoplay,
);
################################################################################
# build immediatley the file list
@files = &build_list($glob);
################################################################################
    $mw->Icon(-image => $mw->Pixmap(-data => &woodpecker_icon));
    $mw->geometry("850x480+0+0");
    $mw->title(" Pic Wood Pecker ");
    $mw->optionAdd('*font', 'Courier 10');
    $mw->optionAdd('*Label.font', 'Courier 10');
    $mw->optionAdd( '*Entry.background',   'lavender' );
    $mw->optionAdd( '*Entry.font',   'Courier 12 bold'  );

# title frame
my $fr0 = $mw->Frame(-borderwidth => 2, -relief => 'groove'
      )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
    $fr0->Label(-text => "$0"
      )->pack(-fill=>'x',-expand=>1,-side=>'left',-pady=>10);
    $fr0->Button(-text => "?",-borderwidth => 4,
                -command => \&help_me,
    )->pack(-side=>'right',-padx=>10);

# list options frame
my  $fr1 = $mw->Frame(-borderwidth => 2, -relief => 'groove'
      )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
    $fr1->Label(-text => "source")->pack(-side => 'left');
    $fr1->Entry(-width => 20,-borderwidth => 4, -textvariable => \$glob
      )->pack(-side => 'left', -expand => 1,-padx=>5);
     # 10.9 addition
     $fr1->Button(-padx=> 5,-text => "browse",-borderwidth => 4,
                -command => sub{
                                $glob = $mw->chooseDirectory(-initialdir => '~',
                                   -title => 'Choose a folder');
                }
    )->pack(-side => 'left',-expand => 1,-padx=>5);
    # end of 10.9 addition
    $fr1->Button(-padx=> 5,-text => "new list",-borderwidth => 4,
                -command => sub{
                                &clear_current;
                                $ph_index = 0;
                                $display_mode = 'photo';
                                @files=&build_list($glob,undef);
                                &setup_draw_area;
                                next_pic(0);
                }
    )->pack(-side => 'left',-expand => 1,-padx=>5);
    $fr1->Button( -padx=> 5,-text => "view list",-borderwidth => 4,
                  -command => sub{
                                  if(@files){
                                        print "Current files:\n",
                                        map{"\t$_->[0]\n"}@files;
                                   }
                                   else{
                                      print "No files in the list\n";
                                      return;
                                   }
                  }
      )->pack(-side => 'left',-expand => 1,-padx=>5);
    $fr1->Button( -padx=> 5,-text => "add to list",-borderwidth => 4,
                  -command => sub{
                                  &clear_current;
                                  if (scalar @files){
                                      @files = (@files,&build_list($glob,'add'));
                                  }
                                  else{
                                       @files = &build_list($glob);
                                       $ph_index = 0;
                                  }
                                  $ph_index = 0 if $ph_index > $#files;
                                  $display_mode = 'photo';
                                  &setup_draw_area;
                                  next_pic(0);
                  }
      )->pack(-side => 'left',-expand => 1,-padx=>5);
    $fr1->Button( -padx=> 5,-text => "clear list",-borderwidth => 4,
                  -command => sub{
                                  &clear_current;
                                  $ph_index = 0;
                                  $display_mode = 'photo';
                                  @files=();
                  }
      )->pack(-side => 'left',-expand => 1,-padx=>5);

# photos destination folder options frame
my  $fr1b = $mw->Frame(-borderwidth => 2, -relief => 'groove'
      )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
    $fr1b->Label(-text => "destination"
      )->pack(-side => 'left');
    $fr1b->Entry( -width => 50,-borderwidth => 4,
                  -textvariable => \$dest
      )->pack(-side => 'left', -expand => 1,-padx=>5);
     $fr1b->Button( -padx=> 5,-text => "set",
                    -borderwidth => 4,
                    -command => sub{$mw->focus}
      )->pack(-side => 'right',-expand => 1,-padx=>5);
# photo ratio and window ratio options frame
my  $fr2 = $mw->Frame(-borderwidth => 2, -relief => 'groove'
      )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
    $fr2->Label(-text => "photo ratio"
      )->pack(-side => 'left',-expand => 1);
    $fr2->Entry(-width => 4,-borderwidth => 4,
                -textvariable => \$ph_ratio,
      )->pack(-side => 'left', -expand => 1,-padx=>5);
    $fr2->Label(-text => "window ratio"
      )->pack(-side => 'left',-expand => 1);
    $fr2->Entry(-width => 4,-borderwidth => 4,
                -textvariable => \$win_ratio
      )->pack(-side => 'left', -expand => 1,-padx=>5);
    $fr2->Button( -padx=> 5,-text => "set ratios",-borderwidth => 4,
                  -command => sub{&set_ratio}
      )->pack(-side => 'left',-expand => 1,-padx=>5);
    $fr2->Label(-text => "debug"
      )->pack(-side => 'left',-expand => 1);
    $fr2->Checkbutton(-variable =>\$debug,
                      -command => sub { status('DarkGreen',
                                        "debug informations to the console ".
                                        ($debug ? 'ENABLED' : 'DISABLED'))
                      }
      )->pack();

# current photo exif information frame
my $label_exif_txt = "too soon to have photo data..";
my  $fr3 = $mw->Frame(-borderwidth => 2, -relief => 'groove'
      )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
    $fr3->Label(  -justify  => 'left',-foreground => 'black',
                  -textvariable => \$label_exif_txt
      )->pack;
# new name frame
my $newname;
my $suffix='';
my  $fr4 = $mw->Frame(-borderwidth => 2, -relief => 'groove'
      )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
    $fr4->Label(-text => "copy name"
      )->pack(-side => 'left',-expand => 1);
my $entryname=$fr4->Entry(-width => 30,-borderwidth => 4,
                          -textvariable => \$newname
      )->pack(-side => 'left', -expand => 1,-padx=>5);
    $fr4->Label(-text => "suffix name"
      )->pack(-side => 'left',-expand => 1);
    $fr4->Entry(-width => 20,-borderwidth => 4,
                -textvariable => \$suffix
      )->pack(-side => 'left', -expand => 1,-padx=>5,-fill=>'x');

my $fr4b = $mw->Frame(-borderwidth => 2, -relief => 'groove'
  )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
my $entrynamebutton = $fr4b->Button(-borderwidth => 4,
                                    -text => '      copy this photo      ',
                                    -command => \&copy_with_name,
  )->pack(-expand=>1,-side=>'left',-padx=>5);#
$fr4b->Button(-text => "advanced",-borderwidth => 4,
                -command => \&advanced_options,
    )->pack(-side=>'right',-padx=>10);

# status frame
my $fr4c = $mw->Frame(-borderwidth => 2, -relief => 'groove'
    )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
my $statuslabel = $fr4c->Label( -justify  => 'left',-foreground => 'black',
                                -textvariable => \$status
    )->pack;

# commands frame
my $fr5 = $mw->Frame(-borderwidth => 2, -relief => 'groove'
  )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
my $butrwd = $fr5->Button(-borderwidth => 4,
                          -text => '      <      ',
                          -command => sub {
                                            if ($display_mode eq 'photo'){
                                                &next_pic(-1);
                                            }
                                            else{
                                                &prev_thumbs;
                                            }
                          } )->pack(-side => 'left',-expand => 1,-padx=>5);
my $butfwd = $fr5->Button(-borderwidth => 4,
                          -text => '      >      ',
                          -command => sub {
                                            if ($display_mode eq 'photo'){
                                                &next_pic(1);
                                            }
                                            else{
                                                &next_thumbs;
                                            }
                          })->pack(-side => 'left',-expand => 1,-padx=>5);
### these packed right side are in reverse order!
$fr5->Label(-text => "seconds"
              )->pack(-side => 'right',-expand => 1);
$fr5->Entry(-width => 4,-borderwidth => 4,
                -textvariable => \$autoplay_sleep_interval
      )->pack(-side => 'right', -expand => 1,-padx=>5,-fill=>'x');
$fr5->Label(-text => "each"
              )->pack(-side => 'right',-expand => 1);
$fr5->Button( -borderwidth => 4,
              -text => 'autoplay',
              -command =>  \&autoplay
              )->pack(-side => 'right',-expand => 1,-padx=>5);

#
$fr5->Entry(-width => 3,-borderwidth => 4,
            -textvariable => \$gotonum
  )->pack(-side => 'right', -padx=>5);
$fr5->Button( -padx=> 5,-text => "go to photo number",-borderwidth => 4,
              -command => sub{&gotonum($gotonum)}
  )->pack(-side => 'right',-padx=>5);
  
# bindings valid for all display modes
# see http://www.perlmonks.org/?node_id=1173808
foreach my $bind (keys %bind_table){
      $mw->bind($bind => $bind_table{$bind});
      # remove bindings for all Tk::Entry in all windows
      $mw->bind('Tk::Entry', $bind,sub{Tk->break});
}
# bind Return to for Tk::Entry to give the focus to parent
$mw->bind('Tk::Entry','<Return>' => sub{$_[0]->parent->focus});

if (@files){
    print "Starting with $files[$ph_index]->[0]\n";

    $butrwd->configure( -text => 'not available',-state => 'disabled' );
    # see  http://www.perlmonks.org/?node_id=1172209
    $mw->update;
    &setup_draw_area;
    $nothumbs ? &next_pic(0) : &draw_thumbs;
    $phwin->focus();
}
else{ print "No file to process\n" }

$mw->MainLoop;
################################################################################
# SUBS
################################################################################
sub autoplay {
     if ($toggle_autoplay == 0){
        $toggle_autoplay = 1 ;
        $display_mode = 'photo';
        &setup_draw_area();
        $ph_index--;
        $tk_timer = $phwin->repeat(
                                    1000 * $autoplay_sleep_interval,
                                    [\&next_pic,1]
        );
     }
     else {
           $toggle_autoplay = 0;
           $tk_timer->cancel if $tk_timer;
     }
     if ($ph_index == $#files){ $tk_timer->cancel;}
}
################################################################################
sub setup_draw_area {
  print "\tsetup_draw_area called\n" if $debug ;
    # chek if the window exists
    if (! Exists($phwin)) {
      $phwin = $mw->Toplevel();
      $phwin->Icon(-image=>$mw->Pixmap(-data => &woodpecker_icon=~s/#296D17/#5c6998/r ));
      # photo window starts just right (+865) of command window
      $phwin->geometry("0x0+865+0");

      $scrolledframe = $phwin->Scrolled('Frame',
                      -background=>'black',
                      -scrollbars => 'osoe',
      )->pack(-expand => 1, -fill => 'both');

      $photo_label = $scrolledframe->Label(-image => $tk_ph_image,
                      -background =>'black'
                      )->pack(-side => 'top',
                       -anchor => 'n',
                       -fill => 'both',
                       -expand => 1,
                      );  # was just pack

      $tk_ph_image = $phwin->Photo(-file => '' ) or die $!;
      # see again: http://www.perlmonks.org/?node_id=1172209
      # even if here is not used
      # $phwin->protocol( 'WM_DELETE_WINDOW', [sub{shift->withdraw}, $phwin], );
    }
    # window Exists
    else {
          $phwin->deiconify( ) if $phwin->state() eq 'iconic';
          $phwin->raise( ) if $phwin->state() eq 'withdrawn';
    }
$phwin->focus;
    # THUMBS display
    if ($display_mode eq 'thumbs') {
        return if $nothumbs;
        return unless @files;
        # tadàààà packForget !!
        $photo_label->packForget();
        my $max_x = 164 * ($grid_col + 1) + 50;
        my $max_y = 164 * ($grid_row + 1) + 50;


        $phwin->geometry($max_x."x".$max_y.""
                        );
        $phwin->update();
        # enable buttons
        $butfwd->configure( -text => '      >      ',-state => 'normal' );
        $butrwd->configure( -text => '      <      ',-state => 'normal' );
        $entrynamebutton->configure(-state=>'disabled');
        # BINDINGS
        $phwin->bind('<KeyRelease-Down>' => sub {&next_thumbs()} );
        $phwin->bind('<KeyRelease-Up>' => sub {&prev_thumbs()} );
        #
        $phwin->bind('<KeyRelease-Left>' => sub {$_[0]->focusPrev;} );
        $phwin->bind('<KeyRelease-Right>' => sub {$_[0]->focusNext;});
        #
        $mw->bind('<KeyRelease-Right>' => sub {&next_thumbs()} );
        $mw->bind('<KeyRelease-Left>' => sub {&prev_thumbs()} );

    }
    # PHOTO display
    else{
        &clear_thumbs();
        $photo_label->pack();
        return unless @files;
        $phwin->geometry( int($files[$ph_index]->[1]*$win_ratio+30) .
                          "x".
                          int($files[$ph_index]->[2]*$win_ratio+30).
                          ""
                          );
        $phwin->title( &file_name($files[$ph_index]->[0]) );
        $entrynamebutton->configure(-state=>'normal');
        # PHOTO display BINDINGS
        $phwin->bind('<KeyRelease-Down>' =>
                      sub {
                            return if $nothumbs;
                            $display_mode = 'thumbs';
                            $tk_ph_image->delete if $tk_ph_image->blank;
                            &clear_current();
                            &setup_draw_area();
                            &draw_thumbs()
        } );
        $phwin->bind('<KeyRelease-Up>' =>
                      sub {
                            return if $nothumbs;
                            $display_mode = 'thumbs';
                            $tk_ph_image->delete if $tk_ph_image->blank;
                            &clear_current();
                            &setup_draw_area();
                            &draw_thumbs();
        } );
        $phwin->bind('<KeyRelease-Left>' => sub {&next_pic(-1) if $ph_index > 0} );
        $phwin->bind('<KeyRelease-Right>' => sub {&next_pic(1) if $ph_index < $#files} );
        #
        $mw->bind('<KeyRelease-Left>' => sub {&next_pic(-1) if $ph_index > 0} );
        $mw->bind('<KeyRelease-Right>' => sub {&next_pic(1) if $ph_index < $#files} );

    }# end of PHOTO display setup
    
    # bindings valid for all display modes
    # see http://www.perlmonks.org/?node_id=1173808
    foreach my $bind (keys %bind_table){
          $phwin->bind($bind => $bind_table{$bind});
    }
}
################################################################################
sub draw_thumbs {
    print "\tdraw_thumbs called\n" if $debug;
    next_pic(0) if $nothumbs;
    my $row = 0;
    my $col = 0;
    &clear_thumbs();
    # just get ids of which thums to load
    my @cur_thumbs = &which_thumbs();
    $phwin->title( 'thumbnails '.($#cur_thumbs >= 1 ?
                                  (join '-',@cur_thumbs[0,-1]):
                                  $cur_thumbs[0]).
                " of 0-$#files (use TAB to navigate,".
                " RETURN to view, UP and DOWN to load other thumbnails) " );

    my $temp_frame = $scrolledframe->Frame(
      -background => 'black', -borderwidth => 0,
    )->pack(-side=>'top',-fill=>'x');

    push @temp_frames,$temp_frame;

    foreach my $th_ind (@cur_thumbs){
        my $ph_thumb = $scrolledframe->Photo(-file => '' ) or warn $!;
        $ph_thumb->configure( -file => undef,
                              -data => MIME::Base64::encode($files[$th_ind]->[5]->jpeg())
        );
        push @temp_thumbs,$ph_thumb;
        my $canv = $temp_frame->Canvas(
                     -background =>'black',
                     -borderwidth => 0,
                     # no white border when not selected
                     -highlightbackground => 'black',
                     # do not allow scrolling pics inside..
                     -scrollregion => [0,0,160,160],
                     -highlightcolor => 'red3',
                     -takefocus => 1,
                     -height => 160,
                     -width => 160  ,
         )->pack(-side => 'left',-expand => 1,-padx=>5);

         $canv->createImage(  81,81,
                              -image => $ph_thumb,
                              -tags => ["$th_ind"],
         );
         # bind the selected canvas
         $canv->CanvasBind('<Return>', sub{&choice_thumb($th_ind) } );
         # highlight the first one of the current grid
         $canv->focusForce if $th_ind == $ph_index;
         # grid mamagement
         if ($col > 0  and ($col % ($grid_col || 1)) == 0){
            $col = 0;
            $row++;
            $temp_frame = $scrolledframe->Frame(
                -background => 'black', -borderwidth => 0,
                )->pack(-side=>'top',-fill=>'x');
            push @temp_frames,$temp_frame;
         }
         else{$col++}
    } # end of foreach my $th_ind (@cur_thumbs)
    $phwin->focus;
}
################################################################################
sub draw_photo {
  my $ph_index = shift;

  print "\tdraw_photo got:\n\t",(join '|',map{defined $_ ? $_ : 'undef'}
      (@{$files[$ph_index]}[0..4],
        $files[$ph_index]->[5]?'THUMB':'NO DATA',
        $files[$ph_index]->[6]?'PHOTO':'NO DATA',
      )),"\n" if $debug;
  $tk_ph_image->delete if $tk_ph_image->blank;

  $phwin->geometry( int($files[$ph_index]->[1]*$win_ratio+30) .
                    "x".int($files[$ph_index]->[2]*$win_ratio+30));
  $phwin->title( &file_name($files[$ph_index]->[0]) );
  my $small_w = int($files[$ph_index]->[1] * $ph_ratio);
  my $small_h = int($files[$ph_index]->[2] * $ph_ratio);

  # create the resized but still empty GD image
  my $resized = GD::Image->new($small_w,$small_h);
  # copy from source into resized on
     $resized->copyResampled($files[$ph_index]->[6],0,0,0,0,
              $small_w,
              $small_h,
              $files[$ph_index]->[6]->width,
              $files[$ph_index]->[6]->height);

  $tk_ph_image->configure( -file => undef,
                           -data => MIME::Base64::encode($resized->jpeg())
  );
  # configure the Tk::Label to use the Tk::Photo as image
  $photo_label->configure(-image => $tk_ph_image );
  # update exif text
  my @times=split /_/,($files[$ph_index]->[4] || '');
  $label_exif_txt = "file ".($ph_index+1)." of ".($#files+1)." ".
                    "$files[$ph_index]->[0]\n".
                    "width:\t\t$files[$ph_index]->[1]\n".
                    "height:\t\t$files[$ph_index]->[2]\n".
                    "orientation:\t".
                        ($files[$ph_index]->[3] ?
                        $files[$ph_index]->[3]  :
                        '-NOT FOUND-')."\n".
                    "creation:\t".
                        (join '.',map{defined $_ ? $_ : 'x'} @times[0..2]).' '.
                        (join ':',map{defined $_ ? $_ : 'x'} @times[3..5])."\n".
                    "data loaded:\t".
                        (defined $files[$ph_index]->[6] ? 'OK' : 'ERROR');
  # udate the name used to (eventually) save current pic
  $newname = &create_name($files[$ph_index]->[4]);
  $phwin->focus();
}
################################################################################
sub next_pic {
    return unless @files;
    my $increment = shift;
    $ph_index = $ph_index + $increment;
$tk_timer->cancel if $ph_index > $#files;
    $ph_index = $#files if $ph_index > $#files;
    $ph_index = 0 if $ph_index < 0;
    #return unless @files;
    print +($debug ? "\n" : '').
          "Considering files[$ph_index] $files[$ph_index]->[0]\n";
    &setup_draw_area unless Exists($phwin);
    # enable button back because it starts disabled
    if ($ph_index > 0 && $butrwd->cget('-state') eq 'disabled'){
       $butrwd->configure( -text =>'      <      ',-state => 'normal' );
    }
    # disable it if first photo
    if ($ph_index == 0 ){
       $butrwd->configure( -text =>'not available',-state => 'disabled' );

    }
    # disable fwd button if last photo
    if ($ph_index == $#files ){
       $butfwd->configure( -text =>'not available',-state => 'disabled' );

    }
    # enable it again if not last photo
    if ($ph_index < $#files && $butfwd->cget('-state') eq 'disabled'){
       $butfwd->configure( -text =>'      >      ',-state => 'normal' );
    }
    # preload
    if ($preload > 0){
      # check if img is yet loaded(change of ratio cleared it?)
      if (defined $files[$ph_index]->[6]) {
          print "\tphoto data yet defined for files[$ph_index]\n" if $debug;
          &draw_photo($ph_index);
      }
      else {
          print "\tphoto data NOT defined for files[$ph_index]\n" if $debug;
          $files[$ph_index]->[6] = &get_ph_data($ph_index);
          print "\tfilled photo data for current: files[$ph_index]\n" if $debug;
          &draw_photo($ph_index);
      }
      # elaborate preload: filling and clearing actions
      @prepost = grep {$_ !=  $ph_index &&
                          $_ >= 0 &&
                          $_  <= $#files}
                    ($ph_index - $preload)..($ph_index + $preload);
      print "\tcurrent $ph_index preload [@prepost]\n" if $debug;
      foreach my $ind (@prepost){
        if (defined $files[$ind]->[6]){
            print "\tskipping PRELOADED files[$ind] (yet defined)\n" if $debug;
            next;
        }
        else {$files[$ind]->[6] = &get_ph_data($ind);
        print "\tfilled files[$ind] photo data\n" if $debug; }

      }
      # delete unneeded elements leaved behind  or forward
      if ($increment == 1){
        if ( $prepost[0]-1 >= 0 && $prepost[0]-1 < $ph_index){
            $files[$prepost[0]-1]->[6] = undef;
            print "\tcleared files[".($prepost[0]-1)."] photo data\n" if $debug;
        }
       }
       elsif ($increment == -1){
            if ($prepost[-1]+1  <= $#files){
              $files[$prepost[-1]+1]->[6] = undef;
              print "\tcleared files[".
                    ($prepost[-1]+1)."] photo data\n" if $debug;
            }
       }
       else{print "\tzero or other non significant increment for next_pic\n" if $debug}
      # update status
      if ((scalar grep{defined $files[$_]->[6]}@prepost,$ph_index )
            ==
          (@prepost +1)){
          status('DarkGreen',"\tOK loaded ".
                              (@prepost +1).
                              " photo data for files[".
                              (join',',$ph_index,@prepost)."]");
      }
      else{status('red3',"\tERROR not all loaded correctly!");}
    }
    # no preload activated
    else{
      @prepost = ($ph_index);
      $files[$ph_index]->[6] = &get_ph_data($ph_index);
      &draw_photo($ph_index);
      if (defined $files[$ph_index - 1]->[6]){
           $files[$ph_index - 1]->[6] = undef;
           print  "\tCurrent $ph_index cleared files[".
                  ($ph_index-1)."]\n" if $debug;
      }
    }
    # ultradebug file list
    if ($debug == 2){
      foreach my $f (0..$#files){
          print "FOR FILES[$f]",
              (defined $files[$f]->[6]?'DATA DEFINED':'undef'),
              "\n";
      }
    }
}
################################################################################
sub get_ph_data {
   my $index = shift;
   return unless -e $files[$index]->[0];
   # load original pic file in GD using general purpose method
   my $gd_image = GD::Image->new($files[$index]->[0]);
   # if not defined try newFromJpeg
   unless ($gd_image){
      status('red3', "\tGD image not defined for [$files[$index]->[0]]".
              " i'll try assuming it is JPEG");
      $gd_image = GD::Image->newFromJpeg($files[$index]->[0]);
   }
   # if it is still undefined...
   unless ($gd_image){
      status('red3', "\tGD image UNAVAILABLE for [$files[$index]->[0]] $!\n");
            #added in 9.12e
            return undef;
   }
   # handle rotation
   if (defined $files[$index]->[3] && $files[$index]->[3] =~/(\d+)/){
      my $rot = $1;
      print "\tRotation detected in main photo: $rot\n" if $debug;
      $gd_image = &handle_rotation(\$gd_image,$rot);
   }
   # check if dimensions are not present (probably never happens)
   unless ($files[$index]->[1]){
          $files[$index]->[1] = $gd_image->width;
          print "\twidth not in EXIF tags: i'll use [$files[$index]->[1]]\n";
   }
   unless ($files[$index]->[2]){
          $files[$index]->[2] = $gd_image->height;
          print "\theight not in EXIF tags: i'll use [$files[$index]->[2]]\n";
   }
   return $gd_image;
}
################################################################################
sub clear_thumbs{
 foreach my $temp_thumb(@temp_thumbs){
         $temp_thumb->delete if $temp_thumb->blank;
         $temp_thumb = undef;
        }
    foreach my $slave_frame (@temp_frames){
        next unless Exists($slave_frame);
        $slave_frame->destroy;
    }
    @temp_frames = ();
    @temp_thumbs = ();
}
################################################################################
sub clear_current {
      return unless @files;# prevent autovivification in the next line
      map { $files[$_]->[6] = undef} @prepost,$ph_index;
      print "\tcleared photo data of preloaded files [@prepost]\n" if $debug;
}
################################################################################
sub next_thumbs {
    print "\tnext_thumbs: index was $ph_index\n" if $debug;
    $ph_index += ($grid_col + 1) * ($grid_row + 1) ;
    print "\tnext_thumbs: index is now $ph_index\n" if $debug;
    if ($ph_index > $#files){$ph_index = $#files}
    &setup_draw_area() unless Exists $phwin;
    &draw_thumbs();
}
################################################################################
sub prev_thumbs {
    print "\tprev_thumbs: index was $ph_index\n" if $debug;
    $ph_index -= ($grid_col + 1) * ($grid_row + 1) ;
    print "\tprev_thumbs: index is now $ph_index\n" if $debug;
    if ($ph_index < 0){$ph_index = 0}
    &setup_draw_area() unless Exists $phwin;
    &draw_thumbs();
}
################################################################################
sub which_thumbs {
    my $last = ($grid_col + 1) * ($grid_row + 1) - 1 + $ph_index;
    if ($last > $#files){$last = $#files}
    print "\twhich_thumbs: [",(join ' ',($ph_index .. $last)),"]\n" if $debug;
    $label_exif_txt = "thumbnail grid of photos: ".
                      (join '-',($ph_index,$last))."(0 .. $#files)";
    return ($ph_index .. $last);
}
################################################################################
sub choice_thumb {
  # see master zentara: http://www.perlmonks.org/?node_id=969034
  # http://www.perlmonks.org/?node_id=931375
  my ($index) = @_;
      print "\tchoice_thumb received $index\n" if $debug;
  &clear_thumbs();#added in v9.12b
      $display_mode = 'photo';
      &setup_draw_area;
      &gotonum($index +1);
}
################################################################################
sub get_exif_data {
    my $file = shift;
    my $exifTool = new Image::ExifTool;
    $exifTool-> Options(Binary => 1, Composite => 1,
                        DateFormat => $date_format, #'%Y_%m_%d_%H_%M_%S',
                        Unknown => 2, Verbose => 0);
    my $exifinfo = $exifTool->ImageInfo($file,'ImageWidth',
                                              'ImageHeight',
                                              'Orientation',
                                              'DateTimeOriginal',
                                              'ThumbnailImage');

    my $gd;                               # double dereference only for thumb!!!
    eval{$gd = GD::Image->newFromJpegData(${$$exifinfo{'ThumbnailImage'}}||'')};
    if ($@){
        print "ERROR creating a thumbnail for file [$file].".
              "I will use an empty one.\n";
        $gd = GD::Image->new(160,160);
    }
    # handle rotation
    if(defined $$exifinfo{'Orientation'} && $$exifinfo{'Orientation'}=~/(\d+)/){
          my $rot = $1;
          print "Rotation detected in thumbnail: $rot\n" if $debug;
          $gd = &handle_rotation(\$gd,$rot);
          if ($rot == 90 or $rot == 270){
              # rearrange returned exif infos to adjust the photo window too
              my $orig_w = $$exifinfo{'ImageWidth'};
              my $orig_y = $$exifinfo{'ImageHeight'};
              $$exifinfo{'ImageHeight'} = $orig_w;
              $$exifinfo{'ImageWidth'} = $orig_y;
          }
    }
    # return a five elements list
    return ($$exifinfo{'ImageWidth'},
            $$exifinfo{'ImageHeight'},
            $$exifinfo{'Orientation'},
            $$exifinfo{'DateTimeOriginal'},
            ($nothumbs ? '' : $gd)
    );
}
################################################################################
sub handle_rotation {
      my $imgref = shift;
      my $rot = shift;
      my $gd = $$imgref;
      if ($rot == 90){
         $gd=$gd->copyRotate90();
      }
      elsif($rot == 180){
         $gd=$gd->copyRotate180();
      }
      elsif($rot == 270){
         $gd=$gd->copyRotate270();
      }
      else{print "Warning! unexpected rotation [$rot] received!\n"}
      return $gd;
}
################################################################################
sub build_list{
    my $glob=shift;
    my $add = shift;
    print "build_list received [$glob]\n"  if $debug;
    my @list = glob($glob);
    if (@list == 1 and -d $glob) {
      print "DIR found: [$glob] will be converted to [$glob".
            '/*.jpg]'."\n" if $debug;
      @list = glob($glob.'/*.jpg');
    }
    elsif (scalar @list and ! -e $list[0] ){
      print "[$glob] NOT found:  './*.jpg' will be used\n" if $debug;
      @list = glob('./*.jpg');
    }
    elsif(scalar @list == 0){print "Empty list searching [$glob]!\n";return();}
    else {1}
    return () unless @list;
    print "Please wait while processing ".(scalar @list)." files....\n";
    # rel2abs
    @list = map {File::Spec->file_name_is_absolute($_) ?
                        $_ : File::Spec->rel2abs($_)} @list;
    # when adding to the list check for duplicates
    if ($add){
        my %uniq;
        @uniq{@list}=map {1} @list;
        foreach my $yet (@files){
              if (defined $yet->[0] && exists $uniq{$yet->[0]} ){
                  print "\tskipping $yet->[0] because yet in the list\n";
                  delete $uniq{$yet->[0]};
              }
        }
        @list = keys %uniq;
    }
    my @files_to_add;
    # populate every [0] entries with absolute path
    map { push @files_to_add,[$_] } @list;
    if ($debug){print "\tadding $$_[0]\n" for @files_to_add;}
    # fill every [1..5] with values got from get_exif_data
    foreach my $index (0..$#files_to_add){
        @{$files_to_add[$index]}[1..5] = &get_exif_data($files_to_add[$index]->[0]);
    }
    return @files_to_add;
}
################################################################################
sub file_name{
    my $path = shift;
    my (undef,undef,$name) = File::Spec->splitpath( $path );
    return $name;
}
################################################################################
sub gotonum{
    my $num = shift;
    unless ($num =~ /^\d+$/){status ('red3',"[$num] is not a number!");return}
    if ( $num < 0 or $num > $#files+1){
        status ('red3',"[$num] not in range!");
        return;
    }
    &clear_current();
    $ph_index = $num - 1;
    print "\tjumping to photo $num\n" if $debug;
    $display_mode = 'photo';
    &setup_draw_area();
    &next_pic(0);
    $phwin->focus();
}
################################################################################
sub status{
    my ($color,$str)=@_;
    ($status = $str) =~s/^\s+//;
    chomp $str;
    print "$str\n";# if $debug;
    $statuslabel->configure(-foreground=>$color);
    $phwin->focus;
}
################################################################################
sub set_ratio{
    foreach my $tocheck($win_ratio,$ph_ratio){
      $tocheck = 0.25 if $tocheck =~/[^\d\.]+/;
      $tocheck = 0.25 if $tocheck > 1;
    }
    my @prepost = grep { $_ >= 0 &&
                         $_  <= $#files }
                       (($ph_index - $preload)|| 0)..($ph_index + $preload);
    print "\tset_ratio will clear photo data for indexes [@prepost]\n" if $debug;
    if (@files){ #prevent autovivification?
                 map {  $files[$_]->[6] = undef } @prepost;
    }
    print "\tcleared photo $ph_index and preloaded [@prepost]\n" if $debug;
    &next_pic(0);
}
################################################################################
sub copy_with_name{
  return if $display_mode eq 'thumbs';
  my $name = &create_name($files[$ph_index]->[4]);
  my @wrote;
  # just original image
  unless ($skip_orig){
        # bypass GD if $bypass_orig_el copying directly (better quality)
        if ($bypass_orig_el){                         # forced jpg extension!!
           my $copy = File::Spec->catfile($dest,$name.'.'.'jpg');
           print "\tJust copying [$files[$ph_index]->[0]]\t[$copy]\n" if $debug;
           if ( copy ($files[$ph_index]->[0],$copy)) {
                push (@wrote, $copy);
           }
        }
        # elaborate original with GD
        else {
              if (my $ok = &write_file(\$files[$ph_index]->[6],$name)){
                  push (@wrote, $ok);
              }
        }
  }
  # multiple copies enabled in advanced options
  if ($enable_multiple_copies){
    my @res = split /\s+/,$multi_pattern;
    foreach my $size(@res){
      my ($w,$h) = split /x/i,$size;
      # swap dimension if original are swapped
      # brutally cheching if y > x  (necessary to avoid malformed images)
      if ($files[$ph_index]->[2] > $files[$ph_index]->[1]){
        my $temp_w = $h;
        $h = $w;
        $w = $temp_w;
        print "\trotation detected, swapping dimensions to [$w]\t[$h]\n" if $debug;
      }
      my $resized = GD::Image->new($w,$h);
      $resized->copyResampled($files[$ph_index]->[6],0,0,0,0,
              $w,
              $h,
              $files[$ph_index]->[6]->width,
              $files[$ph_index]->[6]->height);
      print "\tDebug size: PHOTO data is [$files[$ph_index]->[1]]\t".
            "[$files[$ph_index]->[2]]\n".
            "                  resized [$w]\t[$h]\n" if $debug;
      if (my $ok = &write_file(\$resized,$name.'_'.$w.'x'.$h)){
          push (@wrote, $ok);
      }
    }
  }# end of multiple copies

  # post processing enabled in advanced options
  if ($enable_postprocess){
      # check if the program exists and can be run
      unless( -e $exiftool_path && -x $exiftool_path){
        print "warning! [$exiftool_path] not executable or not found!".
              " No postprocessing for [@wrote]\n";
        return 0;
      }
      foreach my $file(@wrote){
         my @args = map{s/^\$$/$files[$ph_index]->[0]/e;$_} split /\s+/,$exiftool_args;
         print "I'll execute the following command:\n".
            "$exiftool_path ".(join ' ',@args)." $file\n";
         local $?; #needed?
         system($exiftool_path, @args, $file);
         if ($? == 0){
            status('DarkGreen',"OK the postprocess command was succesful")
         }
         elsif ($? == -1) {
            status('red3',"ERROR the postprocess command failed: $!\n");
         }
         elsif ($? & 127) {
            status ('red3',(sprintf "child died with signal %d, %s coredump\n",
              ($? & 127),  ($? & 128) ? 'with' : 'without'));
         }
         else {
            status('red3',(sprintf "child exited with value %d\n", $? >> 8));
         }
      }
  }
}
################################################################################
sub write_file{
    my $gd = shift; # a reference to GD data
    my $name = shift;
    my $flag = $allow_overwrite ?
              (O_WRONLY | O_CREAT) :
              (O_WRONLY | O_CREAT | O_EXCL);
    $name = File::Spec->catfile($dest,$name.'.'.$out_ext);
    if (sysopen my $out,$name,$flag){
        binmode $out;
        if (  $out_ext eq 'jpg' &&
              defined $jpeg_quality &&
              $jpeg_quality =~/^\d{1,3}$/ &&
              $jpeg_quality <= 100 &&
              $jpeg_quality >= 0 )
        { print $out $$gd->jpeg($jpeg_quality);
          print "\tquality $jpeg_quality used for jpeg\n" if $debug;
        }
        elsif ($out_ext eq 'jpg'){
          print $out $$gd->jpeg();
          print "\tdefault quality used for jpeg\n" if $debug;
        }
        elsif ($out_ext eq 'gif'){
          print $out $$gd->gif();
        }
        elsif ($out_ext eq 'png' &&
               defined $png_compression &&
               $png_compression >= 0 &&
               $png_compression <= 9 )
        {
          print $out $$gd->png();
          print "\tcompression $png_compression used for png\n" if $debug;
        }
        elsif ($out_ext eq 'png'){
          print $out $$gd->png();
          print "\tdefault cmpression used for png\n" if $debug;
        }
        elsif ($out_ext eq 'gd'){
          print $out $$gd->gd();
        }
        elsif ($out_ext eq 'gd2'){
          print $out $$gd->gd2();
        }
        else{0}

        close $out;
        status('DarkGreen',"OK wrote $name"),
        return $name;
    }
    else{
         status('red3',"NOT copied $name: $! - $^E"),
         return 0;
    }


}
################################################################################
sub create_name{
    my $timestr = shift;
    return  ( $timestr || 'timestring_not_defined').'_'.
              $ph_index.(length $suffix ? '_'.$suffix : '');
}
################################################################################
sub advanced_options {
    if (! Exists($advw)) {
      $advw = $mw->Toplevel();
      $advw->Icon(-image=>$mw->Pixmap(-data => &woodpecker_icon));
      $advw->geometry("620x315+0+0");

      $advw->title("advanced copy options");
      # allow overwrite frame
      my $frmult0 = $advw->Frame( -borderwidth => 2,
                                  -relief => 'groove'
        )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
      $frmult0->Label( -text => "allow overwrite",
                                        -disabledforeground=>'gray'
        )->pack(-side=>'left',-padx=>10);
      $frmult0->Checkbutton(
                                  -variable =>\$allow_overwrite,
        )->pack(-side=>'left',-padx=>10);
      # bypass original photo GD elaboration (just copy the file) frame
      my $frmult0a = $advw->Frame( -borderwidth => 2,
                                  -relief => 'groove'
        )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
      $frmult0a->Label(-text=>"bypass original file elaboration (simple copy)",
        )->pack(-side=>'left',-padx=>10);
      $frmult0a->Checkbutton(
                              -variable =>\$bypass_orig_el,
        )->pack(-side=>'left',-padx=>10);

      # change extension (and data type) of the output file, quality for jpeg
      my $frmult0b = $advw->Frame( -borderwidth => 2,
                                  -relief => 'groove'
        )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
      $frmult0b->Label( -text => "output file type",
                                        -disabledforeground=>'gray'
        )->pack(-side=>'left',-padx=>10);
      $frmult0b->Optionmenu(
                        -options => [qw(jpg gif png gd gd2)], # wbmp ?
                        -command => \&advanced_options,
                        -variable => \$out_ext,


        )->pack(-side=>'left',-padx=>10);
      $jpeg_quality_lbl = $frmult0b->Label( -text => "jpeg quality (0-100)",
                                        -disabledforeground=>'gray'
        )->pack(-side=>'left',-padx=>10);
      $jpeg_quality_ent = $frmult0b->Entry( -width => 3,-borderwidth => 4,
                                            -textvariable => \$jpeg_quality,

        )->pack(-side=>'left',-padx=>10);
      # multiple copies frame
      my $frmult1 = $advw->Frame( -borderwidth => 2,
                                  -relief => 'groove'
        )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');

      my $frmult2 = $frmult1->Frame(
        )->pack(-side=>'top',-padx=>10,-fill=>'x');
      $frmult2->Label(-text => "enable multiple copies",
        )->pack(-side=>'left');
      $frmult2->Checkbutton( -variable =>\$enable_multiple_copies,
                             -command => \&advanced_options
        )->pack(-side=>'left',-padx=>10);
      my $frmult3 = $frmult1->Frame(
        )->pack(-side=>'top',-padx=>10,-fill=>'x');
      $skip_orig_lbl = $frmult3->Label( -text => "do not copy original image",
                                        -state=>'disabled',
                                        -disabledforeground=>'gray'
        )->pack(-side=>'left',-padx=>10);
      $skip_orig_chk = $frmult3->Checkbutton( -state => 'disable',
                                              -variable =>\$skip_orig
        )->pack(-side=>'left',-padx=>10);

      my $frmult4 = $frmult1->Frame(
        )->pack(-side=>'top',-padx=>10,-fill=>'x');

      $multi_pattern_lbl = $frmult4->Label( -text => "multi copies pattern",
                                            -disabledforeground=>'gray',
                                            -state=>'disabled'
        )->pack(-side=>'left',-padx=>10);
      $multi_pattern_ent = $frmult4->Entry( -width => 30,-borderwidth => 4,
                                            -textvariable => \$multi_pattern,
                                            -state => 'disable'
        )->pack(-side=>'left',-padx=>10);


      # post processing frame
      my $frpost1 = $advw->Frame( -borderwidth => 2,
                                  -relief => 'groove'
        )->pack(-side=>'top',-padx=>5,-pady=>5,-fill=>'x');
      my $frpost2 = $frpost1->Frame(
        )->pack(-side=>'top',-padx=>10,-fill=>'x');
      $frpost2->Label(-text => "enable post processing",
        )->pack(-side=>'left');
      $frpost2->Checkbutton( -variable =>\$enable_postprocess,
                             -command => \&advanced_options
        )->pack(-side=>'left',-padx=>10);
      my $frpost3 = $frpost1->Frame(
        )->pack(-side=>'top',-padx=>10,-fill=>'x');
      $post_prog_lbl = $frpost3->Label( -text => "program  ",
                                            -disabledforeground=>'gray',
                                            -state=>'disabled'
        )->pack(-side=>'left',-padx=>10);
      $post_prog_ent = $frpost3->Entry( -width => 30,-borderwidth => 4,
                                            -textvariable => \$exiftool_path,
                                            -state => 'disabled'
        )->pack(-side=>'left',-padx=>10);
      $post_prog_btn = $frpost3->Button(  -text=>'locate exiftool',
                                          -command=> \&locate_exif,
                                          -state => 'disabled'
        )->pack(-side=>'left',-padx=>10);
      my $frpost4 = $frpost1->Frame(
        )->pack(-side=>'top',-padx=>10,-fill=>'x');
      $post_prog_arg_lbl = $frpost4->Label( -text => "arguments",
                                            -disabledforeground=>'gray',
                                            -state=>'disabled'
        )->pack(-side=>'left',-padx=>10); #-fill=>'x',-expand=>1,
      $post_prog_arg_ent = $frpost4->Entry( -width => 30,-borderwidth => 4,
                                            -textvariable => \$exiftool_args,
                                            -state => 'disabled'
        )->pack(-side=>'left',-padx=>10);
    $advw->focus;
    }
    # window Exists
    else {
      $advw->deiconify( ) if $advw->state() eq 'iconic';
      $advw->raise( ) if $advw->state() eq 'withdrawn';
      $advw->focus;

    }
    # enable quality selection if jpeg
    if ($out_ext eq 'jpg'){
      map{ $_->configure(-state => 'normal')
          }($jpeg_quality_lbl, $jpeg_quality_ent);

    }
    else{
      map{ $_->configure(-state => 'disabled')
          }($jpeg_quality_lbl, $jpeg_quality_ent);
    }
    # enable multi copies options if necessary
    if ($enable_multiple_copies){
          map{ $_->configure(-state => 'normal')
          }($skip_orig_lbl,$skip_orig_chk,$multi_pattern_lbl,$multi_pattern_ent
            );
    }
    # or disable them and clean values
    else{
          map{ $_->configure(-state => 'disabled')
          }($skip_orig_lbl,$skip_orig_chk,$multi_pattern_lbl,$multi_pattern_ent
            );
        $skip_orig = 0;
        $multi_pattern = '';
    }
    # enable post process options if necessary
    if ($enable_postprocess){
          map{ $_->configure(-state => 'normal')
          }($post_prog_lbl, $post_prog_btn,
          $post_prog_ent, $post_prog_arg_lbl, $post_prog_arg_ent);
    }
    # or disable them and clean values
    else{
          map{ $_->configure(-state => 'disabled')
          }($post_prog_lbl, $post_prog_btn,
          $post_prog_ent, $post_prog_arg_lbl, $post_prog_arg_ent);
    }

}
################################################################################
sub locate_exif {
    # directly populates $exiftool_path
    my $path;
    # $ENV{PATH} separator is ; in win and : in linux
    my $sep = ($^O eq 'MSWin32' ? ';' : ':');
    $path = (
        grep{-e -x}map{($_.'\exiftool.bat',$_.'\exiftool')}split $sep,$ENV{PATH}
    )[0];
    if ($path){ print "found exiftool at $path\n";
        $exiftool_path = File::Spec->file_name_is_absolute($path) ?
                        $path : File::Spec->rel2abs($path);
    }
    else { print "warning 'exiftool' program not found!\n"; }
}
################################################################################
sub help_me {
    if (! Exists($hw)) {
      $hw = $mw->Toplevel();
    }
    # window Exists
    else {
      $hw->deiconify( ) if $hw->state() eq 'iconic';
      $hw->raise( ) if $hw->state() eq 'withdrawn';
      $hw->focus;
    }
    my $chars = 'Courier 16';
    $hw->geometry("900x450+0+0");
    $hw->optionAdd('*Text.font' => $chars);
    $hw->title("help page for $0");
    my $txt = $hw->Scrolled('Text',
                      -scrollbars => 'osoe',
                      -background => 'blue3',
                      -foreground => 'gold2',
    )->pack(-expand => 1, -fill => 'both');
    $txt->Contents(`perldoc $0`);
}
################################################################################
sub sanitize_dest{
      my $dest_cand = shift;
      $dest_cand = File::Spec->file_name_is_absolute($dest_cand) ?
              $dest_cand :
              File::Spec->rel2abs($dest_cand);                           # nofile
      my ($volume,$directories,$file)= File::Spec->splitpath( $dest_cand, 1 );
      my @dirs = File::Spec->splitdir( $directories );
      # start with drive c: on win and '' on linux
      my $subdir = $volume;
      foreach my $dir (@dirs){
          $subdir = File::Spec->catdir( $subdir, $dir );
          # be sure to not touch root dir
          next if $subdir =~/^\w:[\\\/]$|^\/$/i;
          unless (-d -e $subdir){
            print "WARNING: [$subdir] not found, i'll create it\n";
            if (mkdir $subdir){
              print "[$subdir] succesfully created\n";
            }
            else{
              print "ERROR creating [$subdir] using '.' as destination\n";
              # setting the global $dest
              return File::Spec->rel2abs('.');
            }
          }
      }
      return $subdir;
}
################################################################################
sub woodpecker_icon{
return <<'EOI'
/* XPM */
static char * picchiorosso[] = {
"32 32 207 2",
"      c None",
".     c #296D17",
"+     c #256315",
"@     c #1B4A0F",
"#     c #112D09",
"$     c #102A09",
"%     c #223D0D",
"&     c #415F15",
"*     c #14360B",
"=     c #040B02",
"-     c #000100",
";     c #000000",
">     c #490303",
",     c #EA0F0A",
"'     c #863E10",
")     c #163A0C",
"!     c #090000",
"~     c #DE0808",
"{     c #F30A0A",
"]     c #F20A0A",
"^     c #774110",
"/     c #286C16",
"(     c #0F2A08",
"_     c #242626",
":     c #D6A2A0",
"<     c #F94747",
"[     c #F60E0E",
"}     c #C40707",
"|     c #270202",
"1     c #1A460E",
"2     c #2F6820",
"3     c #0C0E0C",
"4     c #040404",
"5     c #191918",
"6     c #303130",
"7     c #434343",
"8     c #EFEFEF",
"9     c #FFFFFF",
"0     c #FDD2D1",
"a     c #1F0909",
"b     c #384D32",
"c     c #749B67",
"d     c #131414",
"e     c #888B86",
"f     c #464B45",
"g     c #B4B8B2",
"h     c #FCFCFC",
"i     c #BFC2C2",
"j     c #191B1B",
"k     c #393A39",
"l     c #687066",
"m     c #2E711D",
"n     c #266715",
"o     c #969167",
"p     c #916B20",
"q     c #495347",
"r     c #0F110E",
"s     c #CFD1CF",
"t     c #F0F0F0",
"u     c #20201F",
"v     c #878787",
"w     c #F1F3F0",
"x     c #0E0E0E",
"y     c #82907E",
"z     c #4E7F40",
"A     c #286A17",
"B     c #163C0C",
"C     c #030A02",
"D     c #070502",
"E     c #4E3504",
"F     c #B3A27C",
"G     c #FAFBFC",
"H     c #848484",
"I     c #454645",
"J     c #DEDEDE",
"K     c #4E4F4E",
"L     c #121312",
"M     c #081305",
"N     c #0E2507",
"O     c #1E5111",
"P     c #235E13",
"Q     c #040C02",
"R     c #030303",
"S     c #0D0E11",
"T     c #101215",
"U     c #242423",
"V     c #484948",
"W     c #939592",
"X     c #BEBEBE",
"Y     c #282828",
"Z     c #FBFBFB",
"`     c #666666",
" .    c #12320A",
"..    c #276A16",
"+.    c #173F0D",
"@.    c #091805",
"#.    c #73866E",
"$.    c #A0B49A",
"%.    c #B2C4AD",
"&.    c #CBD0CA",
"*.    c #C8C8C8",
"=.    c #989898",
"-.    c #737373",
";.    c #0A0A0A",
">.    c #FDFDFD",
",.    c #464746",
"'.    c #050E03",
").    c #1F5211",
"!.    c #286A16",
"~.    c #225C13",
"{.    c #246014",
"].    c #468136",
"^.    c #BCD1B7",
"/.    c #A6A6A6",
"(.    c #090909",
"_.    c #D0D0D0",
":.    c #DCDCDC",
"<.    c #747474",
"[.    c #0B0C0B",
"}.    c #010501",
"|.    c #205712",
"1.    c #276816",
"2.    c #3F7C2F",
"3.    c #DDE8DA",
"4.    c #B7B7B7",
"5.    c #232322",
"6.    c #A6A7A6",
"7.    c #686868",
"8.    c #060606",
"9.    c #010400",
"0.    c #0A1D06",
"a.    c #266515",
"b.    c #B7CEB1",
"c.    c #E1E1E1",
"d.    c #0B0B0B",
"e.    c #111111",
"f.    c #151515",
"g.    c #A7A7A7",
"h.    c #EBEBEB",
"i.    c #CED0CD",
"j.    c #6A6D69",
"k.    c #1B480F",
"l.    c #A8C4A1",
"m.    c #AAAAAA",
"n.    c #505050",
"o.    c #969696",
"p.    c #141414",
"q.    c #E9EAE9",
"r.    c #D7D7D7",
"s.    c #191919",
"t.    c #205512",
"u.    c #A1BE99",
"v.    c #6B6B6B",
"w.    c #1D1D1D",
"x.    c #424242",
"y.    c #010101",
"z.    c #626362",
"A.    c #CFD1CE",
"B.    c #F1F1F1",
"C.    c #080808",
"D.    c #5B5B5B",
"E.    c #222222",
"F.    c #091905",
"G.    c #4C853D",
"H.    c #6E6E6E",
"I.    c #A0A0A0",
"J.    c #F8F8F8",
"K.    c #2D2D2D",
"L.    c #919191",
"M.    c #BDBDBD",
"N.    c #E6E6E6",
"O.    c #D2D2D2",
"P.    c #4C6645",
"Q.    c #CACACA",
"R.    c #656565",
"S.    c #020202",
"T.    c #565656",
"U.    c #C5D7C0",
"V.    c #3E772F",
"W.    c #F0F3F0",
"X.    c #CBCBCB",
"Y.    c #F4F4F4",
"Z.    c #F6F9F5",
"`.    c #518842",
" +    c #347523",
".+    c #E5EDE3",
"++    c #777777",
"@+    c #889485",
"#+    c #2F711E",
"$+    c #A1BF9A",
"%+    c #FAFAFA",
"&+    c #1B490F",
"*+    c #F3F6F2",
"=+    c #6E9C62",
"-+    c #FCFDFC",
";+    c #FEFEFE",
">+    c #B0B0B0",
",+    c #232323",
"'+    c #173D0C",
")+    c #E4EDE2",
"!+    c #454545",
"~+    c #0D0D0D",
"{+    c #256415",
"]+    c #8DB184",
"^+    c #DBDBDB",
"/+    c #A3A3A3",
"(+    c #3E5338",
". . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . ",
". . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . ",
". . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . ",
". . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . ",
". . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . ",
". . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . ",
". . . . . . . . . . . . + @ # $ % & . . . . . . . . . . . . . . ",
". . . . . . . . . . . * = - ; ; > , ' . . . . . . . . . . . . . ",
". . . . . . . . . . ) ; ; ; ; ! ~ { ] ^ . . . . . . . . . . . . ",
". . . . . . . . / ( ; ; ; ; _ : < [ } | 1 . . . . . . . . . . . ",
". . . . . . . . 2 3 4 5 6 7 8 9 9 0 a ; b . . . . . . . . . . . ",
". . . . . . . . c d e f g h 9 9 9 i j k l m . . . . . . . . . . ",
". . . . . . . n o p q r s 9 9 9 t u v w x y z A . . . . . . . . ",
". . . . . . B C D E F G 9 9 9 9 H ; I 9 J K L M N O . . . . . . ",
". . . . P Q ; ; R S T U V W X H ; ; Y Z 9 ` ; ; ; ;  .... . . . ",
". . / +.C = @.N #.$.%.&.*.=.-.;.; ; 7 >.9 9 ,.; ; ; ; '.).. . . ",
". . !.~.{.. . . . . . ].^.9 9 /.; (._.9 :.<.[.; ; ; ; ; }.|.1.. ",
". . . . . . . . . . . . 2.3.9 4.; 5.6.7.8.; ; ; ; ; ; ; ; 9.0.a.",
". . . . . . . . . . . . . b.c.d.; e.; f.g.h.i.j.(.; ; ; ; ; ; ;.",
". . . . . . . . . . . . . l.m.; n.o.p.q.9 9 9 9 r.s.; ; ; ; ; ;.",
". . . . . . . . . . . . . u.v.w.>.x.y.z.A.>.9 9 9 B.C.8.D.E.F.!.",
". . . . . . . . . . . . . G.H.I.J.K.; ; ;.D.L.M.9 9 N.O.9 9 9 9 ",
". . . . . . . . . . . . . . P.Q.>.R.; ; ; ; ; S.T.J.9 9 9 9 9 9 ",
". . . . . . . . . . . . . . V.W.9 X.S.; ; ; ; ; ; V Y.9 9 9 9 9 ",
". . . . . . . . . . . . . .  +.+9 9 ++; ; ; ; ; ; ; ; w.9 9 9 9 ",
". . . . . . . . . . . . . . . $+9 9 %+n.; ; ; ; ; ; ; ; &+. 9 9 ",
". . . . . . . . . . . . . . . . *+9 9 9 7.R ; ; ; ; ; ; ; ; ; ; ",
". . . . . . . . . . . . . . . . =+-+9 9 ;+>+,+; ; ; ; ; ; ; ; ; ",
". . . . . . . . . . . . . . . .  +)+9 9 9 9 h.!+~+; ; ; ; ; ; ; ",
". . . . . . . . . . . . . . . . . ]+9 9 9 9 9 >.^+/+(+!.; ; ; ; ",
". . . . . . . . . . . . . . . . . . 9 9 9 9 9 9 >.^+/+(+!.; ; ; ",
". . . . . . . . . . . . . . . . .Discipulus as in perlmonks.org ",};

EOI

}
__DATA__

=head1 NAME

PicWoodPecker

=head1 SYNOPSIS

perl picwoodpecker.pl [-s -d -debug -pr -wr -p -x -y -nothumbs -e -quality -pngcompression -df]

=head1 OPTIONS

     -s|src|source        path
                    the path where search for jpg files to be loaded
                    Can be modified in the Tk interface

     -d|dest|destination  path
                    path used to save files
                    Can be modified in the Tk interface

     -debug
                    print more information on the screen
                    Can be modified in the Tk interface

     -pr|phratio          floating point
                    the ratio used to display the current photo
                    Can be modified in the Tk interface

     -wr|winratio         floating point
                    the ratio to size the window where the photo is displayed
                    Can be modified in the Tk interface

     -p|preload           integer
                    how many photos load in memory after and before the current
                    one. Can increase drawing speed time

     -x|gridx             integer
                    how many columns in the thumbnail grid

     -y|gridy             integer
                    how many rows in the thumbnail grid

     -nothumbs
                    does not load thumbnails at all

     -e|extension             jpg|gif|png|gd|gd2
                    the exstension of saved files
                    Can be modified in the Tk interface

     -quality|jpegquality     0-100
                    the quality of the file used by GD when saving the current
                    photo in jpeg format
                    An empty value let GD to choose a good default
                    Can be modified in the Tk interface

     -pngcompression          0-9
                    the compression factor used by GD when saving the current
                    photo in png format
                    
     -dateformat|df         string
                    the format used for dates. It defaults to %Y_%m_%d_%H_%M_%S
                    in such way resulting pics can be ordered correctly.
                    See C<strftime> in L<POSIX> to more hints about formatting.



=head1 DESCRIPTION

The program is aimed to let you to easely choose among photos and save one (or
more) copy in the preferred format (jpg as default; gif png gd and gd2 are also
available). The name of the copy is crafted using the timestamp when the photo
was taken.

Basically the program will load all jpg files found globbing the path given with
command line parameter C<-source> or entered in the graphical interface,
and foreach file will examine some exif tags to get sizes, timestamps and the
thumbnail (if not present showing a black empty one).

Orientation of the image is handled automatically for thumbnails and main photo.

Advanced options are available to manipulate how many photos are copied, in which
format and let you to postprocess via C<exiftool> each created image.

The program uses L<GD> for image manipulation and L<Image::ExifTool> to load infos
from photos and in the postprocess of them.

=head1 THE GRAPHICAL INTERFACE

A main control window and a display one are created. Optionally a third window
is created to access the advanced copy options. The display window tends to take
the focus being the program focused on displaying photos.

=head3 control window

The control window contains:

=over

=item *

all controls to manipulate the photo list (C<'browse'> C<'new list'> C<'view list'> C<'add to list'> and C<'clear list'>)
Note the that the C<'browse'> does not fill the list; you need to use C<'new list'> or C<'add to list'> after using it.

=item *

an entry to choose the destination folder (that will be checked for existence)

=item *

the C<photo ratio> and the C<window ratio> controls and the C<debug> switch

=item *

an informative text about the current displayed photo or about the grid of thumbnails

=item *

the editable name of the current photo (and an eventual suffix) used to save it

=item *

an information text about the status of the main program (with only relevant information
about copying and loading operations as eventual errors)

=item *

the C<save> button and the C<advanced> options one.

=item *

controls to navigate the photo list

=back

=head3 display window

The display window will starts showing a grid of thumbnails. The first one
is selected. You can navigate the grid using C<right arrow> and C<left arrow> of
the keyboard to move the current selection on or back.

C<up arrow> and C<down arrow> let you load previous or next grids of thumbanails.

C<Enter> key will open the currently selected thumbanil in a bigger resolution (
determinted by C<photo ratio> parameter) photo filling the whole window.

When just one photo is displayed C<right arrow> and C<left arrow> of the keyboard
can be used to show next and previous photo while C<up arrow> and C<down arrow>
bring you back to the thumbnail view.

In both control and display window C<space bar> can be used to save the current
photo and C<p> key can be used to toggle autoplay. If autoplay is active the time
between photos can be set in the control window. Please note that specifying a
short amount of time (shorter than the time needed to load photos data) can
produce weird showing behaviours.

=head3 advanced copy options

This menu lets you to have a granular control about how original photo will be
copied.

The C<allow overwrite> if checked silently overwrite a photo wich has the same
name of what is composed for the current one.

C<bypass original file elaboration (simple copy)> make a copy of the original file
using the new name but without processing it with L<GD>

C<output file type> lets you to choose among different file fomrmats (jpeg, gif,
png, gd and gd2) and to set the quality (0-100) for jpeg ones.
For png files the compression factor (0-9) can be specified only via the command
line parameter C<-pngcompression>

C<enable multiple copies> is trickier. If enabled lets you to choose to copy the
file many times, each one with a different resolution. In the C<multi copies pattern>
you can specify different resolutions in the format widthxheigth as in 800x600 or
1024x768 and for each format a copy will be created.

C<enable post processing> can be used to postprocess every image with C<exiftool>
program that ships with L<Image::ExifTool> module. You can use alternative program
to postprocess your image inserting the full path in the C<program> field.
Arguments to such  program can be also specified where C<$> can be used to refer
to the full path of the original image. In the C<exiftool> command line you can
also specify C<@> to refer to the current file.
So you can postprocess every copy using the following arguments:

C<-overwrite_original -all= -tagsFromFile $ -ImageSize -ImageWidth -ImageHeight -ThumbnailImage -Orientation -DateTimeOriginal>

This C<exiftool> command will be issued for every copy made, overwriting each exif
tags in the copy, removing them all but taking some tag frome the original file
and applying them to the copy. See the L<exiftool> page for a lot of options
this wonderful program lets you to use.




=head1 LIMITATIONS

The program was tested against few different camera formats; i dont know if exif
tags extracted are widely valid.

The autoplay feature does not plays well with little time intervals: infact when
the interval is smaller than the overall time taken to load the the photo and to
redesign the display i'll notice photos and information skipped and the timer
going on. I tried fixing this using C<waitVisibility> Tk method, with no luck.


=head1 COPYRIGHT

This software and icons are copyright of Discipulus as found on www.perlmonks.org
You may redistribute or modify it under the same term of Perl itself.




=cut
