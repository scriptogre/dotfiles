#!/bin/sh
chmod +x /srv/cgi-bin/*.sh
exec httpd -f -p 8080 -h /srv
