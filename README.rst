
MKDI — MaKe Docker Images
=========================

:Authors:        Tomi Ollila  <t… . o… @ iki . fi>

.. contents::


Introduction
------------

Create docker images by writing modern shell scripts and execute those.

The support library ``mkdi-00-lib.sh`` (included) takes care of checking
whether matching image (and parent images!) has already been created and
separation of host and container executed content. One script creates
docker image which contains one filesystem layer on top of base image.
By stacking these scripts together multiple-layer images can be be
done with great flexibility. The level of automation is almost the
same as with Dockerfile(5) based building.


In short, the steps are:

#. script sources ``mkdi-00-lib.sh``

#. host part of script execution, files and (other) changes are collected

#. if script to create parent image is defined, execute it (recursively)

#. check (using perl helper in ``mkdi-00-lib.sh``) whether image is to be
   (re)created (based on existence of matching checksum) -- if not, exit

#. create work container, copy files over and start this same script in
   the container

#. execute container part of the script (in the container)

#. script exits in the container, and host part of the code execution
   commits new image including image ``mkdi`` checksum added into image
   metadata


A bit of history
----------------

This system is an outcome of my iterations to build ``mkdi-test-mattermost``
docker image. In order to utilize reusable components and able to
expand common values the first version used ``m4`` macro processor to
generate ``Dockerfile.gen`` which was then used in docker build command
line. While ``m4`` is powerful tool, there were IMO too much carefullness
and syntax writing to handle to be remembered every time...
Second iteration used shell scripts like these, and ``Makefile`` to
track dependencies — the build time of docker images was stamped to
marker files with perl(1) utime() function when make(1) began its
work. That was moderately simple scheme to get things done, but now
extra carefullness was needed to keep Makefile coherent...

For more information about the ``mkdi-test-mattermost`` container image
(created with mkdi-02-test-mattermost.sh), read
`test-mattermost/README.md <test-mattermost/README.md>`_.


Hands-on
--------

Perhaps the easiest way to get started with *mkdi* is to execute::

  sudo ./mkdi-01-test.sh

(Remove ``sudo`` if you can do without; if you can do without there is
chance you could also use docker run ``-v`` option to see and touch
directories you'd normally would not!)

(Note that there is script called ``helper.sh``. It makes some of these
command lines more convenient to use. It is self-documenting (e.g. when
run without args). Since using it here have added extra layer (of non-
transparency) on top of these commands its usage is not presented here.)

The script ``./mkdi-01-test.sh`` builds image named ``mkdi-quick-test``.
It is based on *debian:8.6* docker image. If that is not already pulled
from registry, docker will call mothership to download it. After the base
image (*docker:8.6*) is available, this test image creation completes
quickly.

``mkdi-quick-test`` will have one image layer added on top of the image
layers from *docker:8.6*. The number of resulting layers can be deduced
from the naming convention for these example files, which is:
Scripts named ``./mkdi-01-*.sh`` will use pullable base images.
Scripts named ``./mkdi-0[2-9]-*.sh`` will use any image created by
``./mkdi-0[1-8]-*.sh`` as a base and thus have one or more layers on top of
the initial base layer, and so on.

To test whether this particular container works as expected, execute::

  sudo docker run --rm -it mkdi-quick-test

You will get shell prompt looking like ``root@d0c2efc047a1:~#``.
The command ``pwd`` will print ``/root`` and ``ls`` outputs ``README.md``.
The file ``README.md`` and contents of ``/root/.docker-setup/`` were
added to the container image while ``./mkdi-01-test.sh`` executed.

After you've played enough with the container, ``exit`` it. If it was
started using the above command line, the container will be removed
from the system. Note that with ``--rm`` it is not quaranteed that the
container will vanish — if docker daemon exits abruptly, these
containers may stay in the system.

To list all existing containers, execute ``sudo docker ps -a``.


List of mkdi files
------------------

The filelist with brief description of each file is now available in
`More <More.rst>`_ document.


Script skeleton
---------------

The ``mkdi-01-test.sh``, along with all other similarly named files
except ``mkdi-00-lib.sh`` have the following structure::

  #!/bin/sh  # /bin/sh for portability, use /bin/bash when bash features needed

  . ./mkdi-00-lib.sh || exit 1

  : # any command line argument handling, if any (executed on host and in cntr)

  # the following mkdi_* functions are no-ops when executed in container
  mkdi_name image-name [tags]  # exactly once
  mkdi_base base-image (parent-script.sh|'pull')  # exactly once
  mkdi_author author/maintainer  # at most once
  mkdi_add_dest perm directory  # zero or more, intermixed with mkdi_add_file's
  mkdi_add_file perm file  # ditto, with mkdi_add_dest's
  mkdi_add_change (ENV|EXPOSE|WORKDIR|CMD|...) change-data  # zero or more
  mkdi_comment comment  # at most once
  mkdi_create [args]  # finalizes mkdi_calls, exits when completed on host

  ### the rest of this script is executed in the container ###

  : # any shell code to be executed in container to configure it

  #eof

The functions called above are described in the next section.


mkdi-00-lib.sh
--------------

``mkdi-00-lib.sh`` is the real force in this mkdi system. It provides the
``mkdi_*`` shell functions to be used in mkdi scripts to configure the
image. When the script runs on host, these mkdi_* functions are active;
when the script is copied in container and executed there, these functions
are no-ops. This makes it pretty convenient to create more mkdi scripts.

After the shell script library part, the file contains embedded perl(1)
program which will check, initiate and commit docker container to a
new image when it is to be (re)built. This part consumes ¾ of the lines
in the file. The code of perl part is explained in more detail in
the `More <More.rst>`_ document.

The shell functions provided by ``mkdi-00-lib.sh`` are:

● ``mkdi_name {image-name} [tags]``

  Defines the name of the to-be committed docker image. If ``tags`` is
  missing, commits as ``:latest``. Otherwise tags with all given tags
  appended to ``image-name``. Note that ``latest`` is not tagged if it is
  not explicitly given to non-empty list of tags. Special tag ``:day:``
  is converted to *yyyymmdd*. This call must be done exactly once.

● ``mkdi_base {base-image} (parent-script.sh|'pull')``

  The image what to be used when creating container as a base for new
  image. This is a bit like ``FROM`` in Dockerfile(5). The second argument
  is either a script name which is used to check/create previous layer for
  this image — or ``pull`` to use image created elsewhere as a base.
  Like mkdi_name, this call must be done exactly once.

● ``mkdi_author {author}``

  Set the author/maintainer field for the generated image.

● ``mkdi_add_dest {perm} {directory}``

  Used in combination with ``mkdi_add_file`` to create directories in the
  build container after it is created but before it is started.

● ``mkdi_add_file {perm} {file}``

  Add files from local filesystem to the container. The destination
  directory is determined by last ``mkdi_add_dest`` executed before this
  call. Initially the target directory is ``/root/.docker-setup/``.

● ``mkdi_add_change (ENV|EXPOSE|WORKDIR|CMD|...) {change-data}``

  Add Dockerfile(5) instructions to be applied when the image is finally
  committed. See docker-commit(1) and Dockerfile(5) for more information.

● ``mkdi_comment {comment}``

  Add comment/commit message to the image. Visible in *docker history*
  and *docker inspect* output.

● ``mkdi_create [args]``

  This function will do the following:
    * check than ``mkdi_name`` and ``mkdi_base`` information is given
    * collect current list of docker images available (for hash checks)
    * run parent script is given (basically in recursion)
    * execute embedded perl program to build the image using the data
      gathered by other ``mkdi`` functions.

  These ``mkdi-`` scripts available in this directory shows quite a few
  ``mkdi_create [args]`` usages. Often at least some of the script args are
  passed to the container execution as the same argument checks are done.

With this information and exploration of the ``mkdi-`` scripts it should
be fairly easy to create new powerful scripts for docker image creation.


Environment variables
---------------------

Some environment variables are used while docker images are build:

``MKDI_FORCE_BUILDS``
  The calculation of hashes to determine whether image needs to be built
  cannot take account changes in remote systems (e.g. package changes);
  it does not know about these. ``MKDI_FORCE_BUILDS`` with integer value
  greater than zero will ensure that at least that many layers of
  mkdi-built images are rebuilt. It it possible that after building the
  hashes are exactly the same as those used to be, even there are changes
  in the created images.

``MKDI_DIFFFILE``
  Before the temporary container used to build the image is removed, it
  is possible to log the filesystem "diffs" in the container compared
  to its base image (using *docker diff*) command. If this variable is set,
  these diffs will be appended to the file of that name.

``MKDI_IMAGES``
  Is used internally by mkdi build process. Better not set this…


Discussions and Contributing
----------------------------

Interested to contribute? Creat! Use the feedback options (be it bug
report, feature request, commit to be considered or general discussion)
provided by these repository frontends. When narrower audience is preferred,
send email to the address resolved from the top of this page.
Any kind of public discussion is welcome — there are no stupid questions,
just stupid people…


More notes
----------

The ``ONBUILD`` instructions (if any) in the base image(s) are not
processed when starting container. Theoretically those could be read
using docker inspect and applied… if docker create could support
applying ONBUILDs that would make things simpler.

Mkdi build attempts to ensure dangling wip-containers are removed after
build, but this may fail due to e.g. abrupt system shutdown (or sigkill).
If rebuild fails due to this happening, just ``docker rm`` the related
container and retry.

One may also encounter "dangling" docker images after builds; i.e. images
that have lost their tags when those are given to other images. Such
containers may be removed with powerful footg^H^H^H^H^H^H command line
``sudo docker images --filter dangling=true -q | xargs sudo docker rmi``

Sometimes there is need to generate files to the image during the build
process. If possible those should be created during execution in container;
that makes the process more robust and easier to reproduce. Some special
cases it might be more feasible to e.g. build executable from c source
on host (instead of creating build environment in container), but that
makes (re)creation depend on host features -- evaluate case-by-case
whether such thing can be used. Possible cases include: throwup demo,
hand-tailored image for legacy system support and so on…
