
More mkdi
=========

.. contents::


List of files
-------------

(in order of appearance)

These files should provide good examples how to use this system to create
hierarchy of docker container images for every imaginable use case. Here
the number of files are so small that base "platforms" for other containers
were done only once, in the test-mattermost container. Nevertheless the
idea here should be pretty clear.

``debian-en-ie-locale.sh``
  script usually run my mkdi-01-* scripts which use debian/ubuntu base and
  want to add en_IE.UTF-8 locale to the system. executed in the container

``helper.sh``
  contains convenience commands to help exploring *mkdi* further

``LICENSE``
  http://www.apache.org/licenses/LICENSE-2.0.txt

``mkdi-00-lib.sh``
  the main workhorse of this system, documented in `README <README.rst>`_

``mkdi-01-all-template.sh``
  template file, can be used as a base for new script

``mkdi-01-base-for-mm.sh``
  parent script for ``mkdi-02-test-mattermost.sh``: installs all
  required packages and does downloads for *mattermost* container

``mkdi-01-debian-enie-locale.sh``
  creates debian/ubuntu image which has ``en_IE.UTF-8`` locale set up.
  requires one argument which will determine the base image

``mkdi-01-notmuch-build-env.sh``
  somewhat more complicated host side execution part than in other scripts.
  one should be able to compile notmuch mail cli program in the containers
  started from the images build with this script. this image plays with
  non-root user and requires [--privileged] -v $HOME:$HOME docker run command
  line option[s] to work as expected

``mkdi-01-test.sh``
  simple test script. executes quickly. demonstrates (almost) all relevant
  mkdi_* functions defined in ``mkdi-00-lib.sh``
  (mkdi-01-notmuch-build-env.sh demonstrated use of USER change…)

``mkdi-02-test-mattermost.sh``
  the script which will configure mkdi-test-mattermost image into *fully*
  working state (fully as in test setup). read `test-mattermost/README.md
  <test-mattermost/README.md>`_ for more information

Note that all of the above *mkdi-0?-* files copy the files used to build
the image to the container -- it is possible to recreate the image without
original source by copying these files from e.g. ``/root/.docker-setup/``
in the image to the host and rearrange the build from there.


Image builder perl program functionality
----------------------------------------

The image is built using embedded perl program which is located at the end
of ``mkdi-00-lib.sh``:

* the ``mkdi-00-lib.sh`` function ``mkdi_create`` executes this program
  with ``create-image`` as first argument. this makes it possible to add
  more commands there in the future

* validates whether all source files given with ``mkdi_add_file`` function
  calls exists

* does **not** validate changes, should do, maybe later...

* if ``mkdi_name`` function call had only name (i.e. no tags) argument, set
  ``latest`` as (being the only) tag. on the other hand, there is a special
  handling for tag ``:day:`` — which is converted to *yyyymmdd*

* reads through id/hash values of currently existing docker images. **mkdi**
  hash values are stored as md5 checksum values for ``mkdi-digest`` label
  in the image metadata. if such label is found, the hash value is used as
  a key for the image (if not, the image id is used instead…). if base image
  is found during this scan this key is stored as the identity of the base
  image. all these keys are stored in a hashmap. if the command (these mkdi
  scripts) used to create the image matches current image command, tags of
  the image is stored as a value in the hashmap, else '**!**' — to indicate
  that the key in question cannot be used as an identity of already built
  image

* if base image was not found in previous step, the base must be 'pull'able
  image, which will be pulled and its base hash collected. if base was
  not 'pull'able there has been error somewhere and program exits

* next, image hash calculation begins. basehash, filenames/directories
  (to be) added (with permissions), changes made and mkdi script arguments
  are put as initial list of strings to be hashed. to this list,
  md5 digests of all the files to be added are calculated and appended.
  note that initially this list of added files contains the build script
  name and (in the first layer) ``mkdi-00-lib.sh``

* the list of strings got in previous step are concatenated together
  and hashed again with Digest::MD5 to get the final md5 checksum

* the final md5 checksum is compared with all previously collected hashes
  of the docker images. if match is found (and value is not '**!**'), the
  *name:tag* list accompanied with the match are checked for missing tags.
  every missing tag (if any) are added to the image. then program announces
  **Done** and exits

* if match was not found (or match value was '**!**'), new image creation
  begins. a container from base image is created, directories and files are
  added there and then this shell script that was used to start this build
  will be executed in the container. as in the container, pid will be 1, the
  script knows to execute the container part of itself. eventually the
  script execution in the container completes; container stops and execution
  continues in this perl program on the host

(**!**) this can happen if the resulting image has been used as a base to
new image. fyi that is pretty also pretty easy to *fake* command and
metadata to have matching image, so always use trusted sources…

* the last things to do is to commit and possibly add more tags to the
  image. first each change given with ``mkdi_add_change`` are converted to
  *change* arguments and then the calculated hash of the image and given
  comment (if any) are appended to the list of *change* arguments (former
  as ``-c 'LABEL mkdi-digest=digest'`` and latter as ``-m 'comment'``).
  the first *name:tag* combination is used to name the image in the
  execution of ``docker commit`` that follows. if there were more
  (than zero or one) tags given with ``mkdi_name``, the rest of the
  *name:tag* combinations will be tagged to the image by
  (somewhat confusingly documented) ``docker tag`` command

* rest of the code are support functions. if more "commands" are to be
  added to this file, there is good location just before these support
  functions

That's it. If the code looks, works, or seems to work differently than this
documentation, code wins.
