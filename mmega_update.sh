#!/bin/bash

# Script to update tables data

# Variables #####################################################################################
# Source
  scripts_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  source $scripts_dir/mmega_functions.sh

# Subject and usage
  subject=mmega_update_pg
  usage="USAGE = mmega_update_pg.sh <account_name|all>"

# Title with database
  echo "${txtbld}_mmega update__________________________________ ${txtrst}[$db_name]"

# Checks ########################################################################################
# Check if database exists
  [[ -n $($PSQL -lt | cut -d '|' -f1 | grep -w "$db_name") ]] || { echo "$fail database $db_name does not exists"; exit 1; } 


# Lock file and tmp directory ####################################################################
  [ ! -f /tmp/$subject.lock ] || { echo -e "$fail Script is already running" ; exit 1; }
  touch /tmp/$subject.lock
  tmp_dir=$(mktemp -d) # Make a tmp directory
  trap "rm -rf $tmp_dir /tmp/$subject.lock" EXIT  # Delete lock file at exit
  #trap "rm -rf /tmp/$subject.lock" EXIT

# Start #########################################################################################
# Get input
get_input_account "$1"

if [ "$input_account" == "all" ];then
   list_accounts="$list_accounts_raw"

   # Check tables
     for account in $list_accounts; do
         is_account_updated "$account"
         if [ "$updated" == "no" ];then
               changes="yes"
               update_tables "$account"
               updated=""
               first_run=""
         fi
     done
     update_global_stats

   # Show updated status if changes
     if [ "$changes" == "yes" ];then
        echo
        show_state_all
        changes=""
     else
        echo "$ok No changes in database"
     fi

# One account
else
   list_accounts=$(echo "$list_accounts_raw" | grep "$input_account")

   # Check tables
     for account in $list_accounts; do
         is_account_updated "$account"
         if [ "$updated" == "no" ] ;then
            changes="yes"
            update_tables "$account"
            updated=""
            first_run=""
         fi
     done

   # Show updated status if changes
     if [ "$changes" == "yes" ];then
        echo
        show_state_one "$list_accounts"
        changes=""
     else
        echo "$ok No changes in database"
     fi
fi

exit
