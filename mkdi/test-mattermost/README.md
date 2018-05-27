
One-container network-isolated Mattermost team edition server setup
-------------------------------------------------------------------

Run Mattermost in one-container setup where connections to outside
networks are disabled (so e.g. mattermost cannot phone home).
Note that the presense of the created mattermost instance is not
fully hidden; e.g. pasting https://www.youtube.com/watch?v=PivpCKEiQOQ
to mattermost channel makes all connected browsers (evaluating javascript?)
to fetch preview (picture/player) from youtube...

In the container postgresql database, nginx web server and mattermost
team messaging platform are installed. The init system used to run
these is moderarely quickly written perl program (now with embedded
smtp server!) -- and current daily "cron" script does nothing.

To build the docker image, (cd to the parent directory and) enter
`sudo ./mkdi-02-test-mattermost.sh`. This will build docker image named
`mkdi-test-mattermost`.

To create and run container from this image execute `./start-mattermost.sh`.
it will complain that server ssl/tls certificates needs to be set up. The
dummy server certs located in this directory can be used for initial testing.
The script `./create-certs.sh` makes custom root CA and server certs, which
may (also) be sufficient to one's needs...

Currently using use e.g. let's encrypt certs does not work out of the box,
as connections to outside network is prohibited. The alternative to opening
network access is to fetch the certs on the host and `docker cp` those to
the container -- and after `sudo docker exec mattermost pkill nginx` those
certs are in use.

The shell script './start-mattermost.sh' creates 'isolated-nw'
network and starts 'mattermost' container with suitable
parameters.

Whenever there is need to explore inside the running container,
`sudo docker exec -it mattermost env TERM=$TERM bash` will start interactive
root shell there.

Now try to access the mattermost server. https://127.0.0.1:5443/ might
be the address.
The first user created will be the system admin.

By default console logging is set to DEBUG. Change this to something else
in admin console after verified that things work.

Note that all the emails mattermost server sends are just stored in
*/etc/mail/incoming/* on the container (as no network connections to
outside world can be initiated).

To get more users to the system, use **Get Team Invite Link** on the top
left corner menu (3 vertical dots), and distribute that link to the users.
That link can be shared with multiple users (i.e. it does not invalidate
until team admin regenerates it).

While iterating initial experiments, `sudo docker stop mattermost` stops
the container. Re-running `sudo ./start-mattermost.sh` will re-start it.
To re-create the container, do `sudo docker rm mattermost` first.
Recreating container (from 'mkdi-test-mattermost' image) will start
everything from "scratch".

Read https://docs.mattermost.com/install/prod-debian.html
for information how to configure mattermost further. That page
was used as a reference when building this up (It provided
more accurate ubuntu 16.04-based setup that the ubuntu variant
was available Mon 2016-04-22).

The file *prod-debian.txt* is `lynx -dump` output of the above page
taken Wed 2016-08-24, just in case the original gets moved and
is therefore harder to find.
