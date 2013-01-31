#!/bin/bash - 
#===============================================================================
#
#          FILE: lp4nm.sh
# 
#         USAGE: ./lp4nm.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: cloved (石头, Rock Chen -- chnl@163.com), cloved@gmail.com
#  ORGANIZATION: itnms.info
#       CREATED: 01/31/2013 06:04:58 PM CST
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
perl lp4nm.pl -p /opt/nginx/logs/error.log --with-csv-file=/var/tmp/lp4nm.csv --dbm-queue-file=/var/tmp/lp4nm.dbm --daemon-pid=/var/tmp/lp4nm.pid --daemon-log=/var/tmp/lp4nm.log   --daemon -v

