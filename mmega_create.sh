#!/bin/bash

# Script to create PostgreSQL db for mega accounts
# Set password

# Variables ###############################################################################
# Source
  scripts_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  source $scripts_dir/mmega_functions.sh

# Subject and usage
  subject=mmega_create
  usage="USAGE = mmega_create.sh <db_name> <config_file>"

# Database and config file
  db_name="$1"
  config_file="$2"

# Title
  echo "${txtbld}_mmega create__________________________________ ${txtrst}"

# Checks #######################################################################################
# Check database
  [ -n $db_name ] || { echo "$fail no database name set"; exit 1; }
  db_name_tmp=${db_name//[^a-zA-Z0-9_]/}  # Only alphanumeric or an underscore characters
  [ $(echo "$db_name_tmp" | wc -m ) -le 255 ] && db_name="$db_name_tmp" || { echo "$fail Database name is too big (255 chars max)"; exit 1; } # Limit to 255 characters

# Test if database already exists
  [[ -z $(sudo -u postgres $PSQL -lt | cut -d '|' -f 1 | grep "$db_name_tmp") ]] || { echo "$fail database $db_name already exists"; exit 1; }

# Check config file
  [ -f "$config_file" ] || { echo -e "$fail no config file set"; exit 1; }

# Lock file and tmp directory #################################################################
  [ ! -f /tmp/$subject.lock ] || { echo -e "$fail Script is already running" ; exit 1; }
  touch /tmp/$subject.lock
  trap "rm -rf /tmp/$subject.lock" EXIT  # Delete lock file at exit

# Title with database
  echo -en "\033[1A\033[2K"
  echo "${txtbld}_mmega create__________________________________ ${txtrst}[$db_name]"

# Start #######################################################################################
# Create role
  create_role "$user" "'$user_passwd'"

# Create database and tables (for tables of files and links see below)
  create_db "$db_name"
  create_tbl_config
  create_tbl_disk_stats
  create_tbl_file_stats
  create_tbl_global_stats
  create_tbl_hashes

# Insert
  # Insert config data from file
    insert_config_data "config"

  # Get list of accounts
    get_list_accounts

  # Create tables of files for each account (no default values)
    for account in $list_accounts;do
        echo "[ -- ] Creating file tables ${txtbld}$account${txtrst}"
        create_tbls_of_files "$account"
        echo -en "\033[1A\033[2K"
        test_cmd "Creating file tables ${txtbld}$account${txtrst}"
        echo -en "\033[1A\033[2K"
    done
    echo "$ok Creating file tables"

  # Insert disk and files stats default values
    for account in $list_accounts;do
       echo "[ -- ] Inserting default values ${txtbld}$account${txtrst}"
       insert_created "$account"
       insert_disk_stats "$account"
       insert_file_stats "$account"
       insert_tbl_hashes "$account"
       echo -en "\033[1A\033[2K"
       test_cmd "Inserting default values ${txtbld}$account${txtrst}"
       echo -en "\033[1A\033[2K"
    done
    echo "$ok Insering default values"

  # Insert global stats
    sum_acc=$($PSQL -d $db_name -t -c "SELECT COUNT(config.name) FROM config;" | tr -d ' ' )
    insert_global_stats

# Set database in scripts and completion files
  set_db_name_in_mmega_functions
  set_db_in_completion "$db_name"

# Copy bash aliases if not present
  copy_bash_aliases

# Show tables and default values
  echo
  # With hashed password
    #$PSQL -d $db_name -c " SELECT id,name,email,ENCODE(DIGEST('passwd', 'sha1'), 'hex') AS hashed_passwd,local_dir,remote_dir FROM config;"

  # Without password
    $PSQL -d $db_name -c " SELECT id,name,email,local_dir,remote_dir FROM config;"

exit
