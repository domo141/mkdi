#!/bin/sh
# mkdi-02-mattermost.sh

# Use
# ./test-mattermost/start-mattermost.sh
# to setup and start test mattermost container.

. ./mkdi-00-lib.sh || exit 1

mkdi_name mkdi-test-mattermost
mkdi_base debian-8.6-base-for-mm:latest mkdi-01-base-for-mm.sh

#mkdi_add_dest 755 /root/.docker-setup/ # already there
mkdi_add_file 644 test-mattermost/start-mattermost.sh
mkdi_add_file 644 test-mattermost/README.md
mkdi_add_file 644 test-mattermost/prod-debian.txt
mkdi_add_file 444 test-mattermost/dummy-server.crt
mkdi_add_file 444 test-mattermost/dummy-server.key
mkdi_add_file 755 test-mattermost/create-certs.sh

mkdi_add_dest 755 /usr/local/sbin/
mkdi_add_file 755 test-mattermost/initti.pl
mkdi_add_file 755 test-mattermost/daily.sh

mkdi_add_change CMD '["echo","Use start-mattermost.sh to run this container."]'

mkdi_create

### the rest of this script is executed in the container ###

set -x

mv dummy-server.crt /etc/ssl/private/nginx-server.crt
mv dummy-server.key /etc/ssl/private/nginx-server.key
#chown uu:gg /etc/ssl/private/nginx-server.*

# ref: https://docs.mattermost.com/install/prod-debian.html
# here just single machine used, all 3 components installed on same

#
# postgresql
#

PGV=9.4

# by trial & error
mkdir /var/run/postgresql/$PGV-main.pg_stat_tmp
chown postgres:postgres /var/run/postgresql/$PGV-main.pg_stat_tmp

# XXX w/ systemd'd version this would not work
if :; then
  /etc/init.d/postgresql start
else
  su postgres -c "cd / && exec /usr/lib/postgresql/$PGV/bin/postgres -D /var/lib/postgresql/$PGV/main --config-file=/etc/postgresql/$PGV/main/postgresql.conf" &
  sleep 5 # XXX check somehow
fi
su postgres -c ' cd / && exec psql' <<'EOF'
CREATE DATABASE mattermost;
CREATE USER mmuser WITH PASSWORD 'mmuser_password';
GRANT ALL PRIVILEGES ON DATABASE mattermost to mmuser;
EOF

if :; then
  /etc/init.d/postgresql stop
else
  sleep 0.5
  pkill postgres
fi
## no need to modify postgresql configuration -- using localhost for all

#
# mattermost
#

mkdir -p /opt/mattermost/data
useradd -r mattermost -U
chown -R mattermost:mattermost /opt/mattermost
chmod -R g+w /opt/mattermost

set_salts ()
{
	set x `head -c 96 /dev/urandom | base64 -w 32`
	publiclnksalt=$2 invitesalt=$3 passwdresetsalt=$4 atrestencryptkey=$5
}
set_salts

cp /opt/mattermost/config/config.json /opt/mattermost/config/config.json.orig
# note: sed -i (option) is gnu extension
sed -i	-e 's/mysql/postgres/' \
	-e '/MaxUsersPerTeam/ s/[0-9][0-9]*/500/' \
	-e '/dnl EnableSignInWithEmail/ s/true/false/' \
	-e '/PublicLinkSalt/ s!: .*"!: "'"$publiclnksalt"'"!' \
	-e '/InviteSalt/ s!: .*"!: "'"$invitesalt"'"!' \
	-e '/PasswordResetSalt/ s!: .*"!: "'"$passwdresetsalt"'"!' \
	-e '/AtRestEncryptKey/ s!: .*"!: "'"$atrestencryptkey"'"!' \
	-e '/FeedbackName/ s/""/"Mattermost notifications going nowhere"/' \
	-e '/FeedbackEmail/ s/""/"mattermost@example.com"/' \
	-e '/FeedbackOrganization/ s!""!"FYI: emails stored in /var/mail/incoming/ by initti smtpd"!' \
	-e '/SMTPServer/ s/""/"127.0.0.1"/' \
	-e '/SMTPPort/ s/""/"25"/' \
	-e '/SendEmailNotifications/ s/false/true/' \
	-e '/"DataSource":/ s!:.*"!: "postgres://mmuser:mmuser_password@127.0.0.1:5432/mattermost?sslmode=disable\&connect_timeout=10"!' \
	/opt/mattermost/config/config.json


#
# nginx
#

rm /etc/nginx/sites-enabled/default

## note: no port 80 used...

# Wanted to use location /mattermost/ below, but it currently does not work
# see http://forum.mattermost.org/t/solved-blank-page-when-installing-mattermost-with-nginx-proxy-pass-as-subdirectory/1604/5

cat > /etc/nginx/sites-available/mattermost <<'EOF'
server {
   listen 5443 ssl;
   server_name placeholder.example.com

   ssl on;
   ssl_certificate /etc/ssl/private/nginx-server.crt;
   ssl_certificate_key /etc/ssl/private/nginx-server.key;
   ssl_session_timeout 5m;
   ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
   ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
   ssl_prefer_server_ciphers on;
   ssl_session_cache shared:SSL:10m;

   #location /mattermost/ {  # does not work as of 2016-08-22
   location / {
      gzip off;
      proxy_set_header X-Forwarded-Ssl on;
      client_max_body_size 50M;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $http_host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Frame-Options SAMEORIGIN;
      proxy_pass http://127.0.0.1:8065/;
   }
}
EOF

ln -s ../sites-available/mattermost /etc/nginx/sites-enabled/mattermost
