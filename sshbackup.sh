#!/bin/bash

#
# Mikrotik SSH backup script rev. 1.2
#
# Copyright (C) 2015 Petr Domorazek <petr@domorazek.cz>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#


LOCAL_DIR=`dirname $0`
HOST=`hostname`
BACKUP_PATH=$LOCAL_DIR/mikrotik
CONF=$LOCAL_DIR/sshbackup.conf
LOG=$LOCAL_DIR/logs/sshbackup`date +%Y%m%d-%T`.log
source sshbackup.credentials

echo -e "\033[1mMikrotik SSH backup utility\033[0m"
echo ""

if [ ! -f "$CONF" ] 2>/dev/null ; then
    echo -e "\e[31m!!!ERROR\e[0m, Configuration file not found!"
    exit 1
fi

if  [ ! -d "$BACKUP_PATH" ] ; then
    echo -e "\e[31m!!!ERROR\e[0m, Backup path not found!"
    exit 1
fi

LAST_CHAR=`tail -c 1 $CONF`
if [ "$LAST_CHAR" != "" ] ; then
    echo -e "" >> $CONF
fi

INDEX=0
SCP_ERROR=no


gethosts="/ip ipsec peer print brief"
HOSTS=$(sshpass -p $SSH_PASS ssh -o StrictHostKeyChecking=no $SSH_USER@$CORE_ROUTER $gethosts)
for HOST in $HOSTS
do
    if [[ $HOST == 'main' ]]
    then
        INDEX=$INDEX+1
        PARSE=false
    fi
    if [[ $PARSE == 'true' ]]
    then
        if [[ "${DESC[$INDEX]}a" == "a" ]]
        then
            DESC[$INDEX]=Total/${HOST/\/}
        else
            IP[$INDEX]=${HOST/\/32/}
        fi
    fi
    if [[ $HOST == ';;;' ]]
    then
        PARSE=true
    fi
done


while read -r line
do 
    line=`echo $line | grep :`
    if [ -n "$line" ] ; then
        if [ "${line:0:1}" != "#" ] ; then
            IP[$INDEX]=`echo $line | cut -d: -f1 | tr -d " "`
            DESC[$INDEX]=`echo $line | cut -d: -f2 | tr -d " "`
            if  [ ! -d "${BACKUP_PATH}/${DESC[$INDEX]}" ] ; then
                mkdir -p ${BACKUP_PATH}/${DESC[$INDEX]}
            fi
            INDEX=$INDEX+1
        fi
    fi
done < $CONF

echo "Taking backup of:"
for (( a=0 ; $a-INDEX ; a=$a+1 ))
    do
    echo ${IP[$a]} -  ${DESC[$a]}
done


echo "--------------------------------------------------------------------------------" >> $LOG
for (( a=0 ; $a-INDEX ; a=$a+1 ))
do
    basefilename=${DESC[$a]//\//-}-${IP[$a]}
    cmd="/export file=${basefilename}.rsc; /system backup save name=${basefilename}.backup;"
    echo $cmd > $LOG
    echo ${IP[$a]} -  ${DESC[$a]}
    echo ${IP[$a]} -  ${DESC[$a]} >> $LOG
    #sshpass -p $SSH_PASS ssh -o StrictHostKeyChecking=no $SSH_USER@${IP[$a]} $cmd >> $LOG
    sshpass -p $SSH_PASS ssh -o StrictHostKeyChecking=no $SSH_USER@${IP[$a]} $cmd >/dev/null 2>&1

    if [[ $? != 0 ]]; then
	echo -e " \e[31mErr\e[0m SSH failed!"
	echo "!!! SSH failed!"  >> $LOG
	SCP_ERROR=yes
    else
    sleep 2
	for SCPFILE in ${basefilename}.backup ${basefilename}.rsc
	do
            mkdir -p ${BACKUP_PATH}/${DESC[$a]}/
	    sshpass -p $SSH_PASS scp -o StrictHostKeyChecking=no $SSH_USER@${IP[$a]}:/${SCPFILE} ${BACKUP_PATH}/${DESC[$a]}/ >/dev/null 2>&1
	    if [[ $? != 0 ]]; then
	        echo -e " \e[31mErr\e[0m Transfer ${SCPFILE} failed!"
	        echo "!!! Transfer ${SCPFILE} failed!"  >> $LOG
	        SCP_ERROR=yes
	    else
		echo -e " \e[32mOK\e[0m  Transfer ${SCPFILE} complete."
		#echo "Transfer ${SCPFILE} complete."  >> $LOG
		mv ${BACKUP_PATH}/${DESC[$a]}/${SCPFILE} ${BACKUP_PATH}/${DESC[$a]}/`date +%Y%m%d`_${SCPFILE}
		if [ "$DELETE_FILE" == "yes" ] ; then
		    cmd2="/file remove ${SCPFILE};"
		    sshpass -p $SSH_PASS ssh -o StrictHostKeyChecking=no $SSH_USER@${IP[$a]} $cmd2
		    if [[ $? != 0 ]]; then
			echo -e " \e[31mErr\e[0m Remove file ${SCPFILE} from Mikrotik failed!"
			echo "!!! Remove file ${SCPFILE} from Mikrotik failed!"  >> $LOG
		    else
			echo -e " \e[32mOK\e[0m  Remove file ${SCPFILE} from Mikrotik."
		    fi
		fi
	    fi
	done
    fi
    echo ""
    echo "--------------------------------------------------------------------------------" >> $LOG
done

if [ "$SCP_ERROR" == "yes" ] ; then
    echo -e ""
    echo -e "\e[31m Err\e[0m \033[1m When backing up the\033[0m \e[31mERROR\e[0m \033[1moccurred.\033[0m"
    echo -e "`date "+%Y-%m-%d %T"` \t  !!!ERROR - When backing up the ERROR occurred." >> $LOG
    echo ""
    echo -e "\033[1mCheck the log file: $LOG \033[0m"
    echo -e "!!!ERROR - When backing up the ERROR occurred.\nCheck the $HOST server log file: $LOG" | mail -s "Server: $HOST - Backup Mikrotiks ended with ERRORS!" -r $MAIL_FROM $MAIL_TO
else
    echo -e ""
    echo -e " \e[32mOK\e[0m  \033[1mThe backup is complete.\033[0m"
    echo -e "`date "+%Y-%m-%d %T"` \t  OK - The backup is complete." >> $LOG
fi
sleep 5
echo ""
