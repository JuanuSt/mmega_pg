#!/bin/bash

# Download, upload or synchronize files
# up               = upload all diferent files from local to remote
# down             = download all diferent files from remote to local
# sync with_local  = upload all differents files and delete all remote differents files
#      with_remote = download all differents files and delete all local different files

# Variables #####################################################################################
# Source
  scripts_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  source $scripts_dir/mmega_functions.sh

# Subject and usage
  subject=mmega_sync
  usage="USAGE = mmega_sync <account_name|all> up|down|sync [with_local|with_remote] [optional no-confirm]"

# Title with database
  echo "${txtbld}_mmega sync____________________________________ ${txtrst}[$db_name]"

# Checks ########################################################################################
# Test if update was run the first time 
  test_global_sum=$($PSQL -d "$db_name" -t -c "SELECT sum_total FROM global_stats" | sed -e s'/ //1')
  if [ "$test_global_sum" == "0 bytes" ];then
     echo "$fail The database $db_name has never been updated. Make the first run with mmega_update.sh"
     exit 1
  fi

# Lock file and tmp directory ###################################################################
  [ ! -f /tmp/$subject.lock ] || { echo -e "$fail Script is already running" ; exit 1; }
  touch /tmp/$subject.lock
  tmp_dir=$(mktemp -d) # Make a tmp directory
  trap "rm -rf $tmp_dir /tmp/$subject.lock" EXIT  # Delete lock file at exit
  #trap "rm -rf /tmp/$subject.lock" EXIT

# Start #########################################################################################
# Get inputs
  get_input_account "$1"
  get_sync_action "$2" "$3" "$4"

  if [ "$input_account" == "all" ];then
     list_accounts="$list_accounts_raw"
  else
     list_accounts=$(echo "$list_accounts_raw" | grep "$input_account")
  fi

  for account in $list_accounts; do
       sync_action "$account" "$action_type" "$direction"
  done

exit

