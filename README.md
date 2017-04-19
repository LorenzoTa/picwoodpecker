# picwoodpecker
perl Tk program to choose among photos and copy one or more modified copy


               This software is dedicated to my parents, who need to see printed pictures -- 6 July 1966 

NAME
SYNOPSIS
OPTIONS
DESCRIPTION
THE GRAPHICAL INTERFACE
control window
display window
advanced copy options
LIMITATIONS
COPYRIGHT
NAME

PicWoodPecker

SYNOPSIS

perl picwoodpecker.pl [-s -d -debug -pr -wr -p -x -y -nothumbs -e -quality -pngcompression -df]

OPTIONS

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

DESCRIPTION

The program is aimed to let you to easely choose among photos and save one (or more) copy in the preferred format (jpg as default; gif png gd and gd2 are also available). The name of the copy is crafted using the timestamp when the photo was taken.

Basically the program will load all jpg files found globbing the path given with command line parameter -source or entered in the graphical interface, and foreach file will examine some exif tags to get sizes, timestamps and the thumbnail (if not present showing a black empty one).

Orientation of the image is handled automatically for thumbnails and main photo.

Advanced options are available to manipulate how many photos are copied, in which format and let you to postprocess via exiftool each created image.

The program uses GD for image manipulation and Image::ExifTool to load infos from photos and in the postprocess of them.

THE GRAPHICAL INTERFACE

A main control window and a display one are created. Optionally a third window is created to access the advanced copy options. The display window tends to take the focus being the program focused on displaying photos.

control window

The control window contains:

all controls to manipulate the photo list (&#39;browse&#39; &#39;new list&#39; &#39;view list&#39; &#39;add to list&#39; and &#39;clear list&#39;) Note the that the &#39;browse&#39; does not fill the list; you need to use &#39;new list&#39; or &#39;add to list&#39; after using it.
an entry to choose the destination folder (that will be checked for existence)
the photo ratio and the window ratio controls and the debug switch
an informative text about the current displayed photo or about the grid of thumbnails
the editable name of the current photo (and an eventual suffix) used to save it
an information text about the status of the main program (with only relevant information about copying and loading operations as eventual errors)
the save button and the advanced options one.
controls to navigate the photo list
display window

The display window will starts showing a grid of thumbnails. The first one is selected. You can navigate the grid using right arrow and left arrow of the keyboard to move the current selection on or back.

up arrow and down arrow let you load previous or next grids of thumbanails.

Enter key will open the currently selected thumbanil in a bigger resolution ( determinted by photo ratio parameter) photo filling the whole window.

When just one photo is displayed right arrow and left arrow of the keyboard can be used to show next and previous photo while up arrow and down arrow bring you back to the thumbnail view.

In both control and display window space bar can be used to save the current photo and p key can be used to toggle autoplay. If autoplay is active the time between photos can be set in the control window. Please note that specifying a short amount of time (shorter than the time needed to load photos data) can produce weird showing behaviours.

advanced copy options

This menu lets you to have a granular control about how original photo will be copied.

The allow overwrite if checked silently overwrite a photo wich has the same name of what is composed for the current one.

bypass original file elaboration (simple copy) make a copy of the original file using the new name but without processing it with GD

output file type lets you to choose among different file fomrmats (jpeg, gif, png, gd and gd2) and to set the quality (0-100) for jpeg ones. For png files the compression factor (0-9) can be specified only via the command line parameter -pngcompression

enable multiple copies is trickier. If enabled lets you to choose to copy the file many times, each one with a different resolution. In the multi copies pattern you can specify different resolutions in the format widthxheigth as in 800x600 or 1024x768 and for each format a copy will be created.

enable post processing can be used to postprocess every image with exiftool program that ships with Image::ExifTool module. You can use alternative program to postprocess your image inserting the full path in the program field. Arguments to such program can be also specified where $ can be used to refer to the full path of the original image. In the exiftool command line you can also specify @ to refer to the current file. So you can postprocess every copy using the following arguments:

-overwrite_original -all= -tagsFromFile $ -ImageSize -ImageWidth -ImageHeight -ThumbnailImage -Orientation -DateTimeOriginal

This exiftool command will be issued for every copy made, overwriting each exif tags in the copy, removing them all but taking some tag frome the original file and applying them to the copy. See the exiftool page for a lot of options this wonderful program lets you to use.

LIMITATIONS

The program was tested against few different camera formats; i dont know if exif tags extracted are widely valid.

The autoplay feature does not plays well with little time intervals: infact when the interval is smaller than the overall time taken to load the the photo and to redesign the display i'll notice photos and information skipped and the timer going on. I tried fixing this using waitVisibility Tk method, with no luck.

COPYRIGHT

This software and icons are copyright of Discipulus as found on www.perlmonks.org You may redistribute or modify it under the same term of Perl itself.

L*
