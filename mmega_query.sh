#!/bin/bash

# Interact with database

# Source
  scripts_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  source $scripts_dir/mmega_functions.sh

# Variables #####################################################################################

# Subject and usage
  subject=mmega_query_pg
  usage="
  USAGE = mmega_query.sh config|account|files|change|add|del|search|set_rc|set_db|summary [options by query]

            config  <account_name|all> [optional password] [defautl all]
            state  <account_name|all> [defautl all]
            files   <account_name> local|remote|sync|to_down|to_up|link [optional path]
            change  <account_name> name|email|passwd|local_dir|remote_dir <new_parameter>
            add     <new_account_name|new_file_config>
            del     <account_name>
            search  <file_to_search>   [optional account, defautl all]
            set_rc  <account_name>
            set_db  <database_name>
            summary
        "

# Title with database
  echo "${txtbld}_mmega query___________________________________ ${txtrst}[$db_name]"

# Checks ########################################################################################
# Check if database exists 
  [[ -n $($PSQL -lt | cut -d '|' -f1 | grep -w "$db_name") ]] || { echo "$fail database $db_name does not exists"; exit 1; } 

# Test if update was run the first time
  test_global_sum=$($PSQL -d $db_name -t -c "SELECT sum_total FROM global_stats" | sed -e s'/ //1')
  if [ "$test_global_sum" == "0 bytes" ];then
     echo "$fail The database $db_name has never been updated. Make the first run with mmega_update.sh"
     exit 1
  fi


# Lock file and tmp directory #################################################################
  [ ! -f /tmp/$subject.lock ] || { echo -e "$fail Script is already running" ; exit 1; }
  touch /tmp/$subject.lock
  tmp_dir=$(mktemp -d) # Make a tmp directory
  trap "rm -rf $tmp_dir /tmp/$subject.lock" EXIT  # Delete lock file at exit
  #trap "rm -rf /tmp/$subject.lock" EXIT

# Start #######################################################################################

# Get query type
get_query_type "$1"

# FILE QUERY
if [ "$query_type" == "files" ];then
   input_account="$2"
   get_input_account_query "$input_account"

   input_file_type="$3"
   get_input_file_type "$input_file_type" "$4"
   show_file_type "$input_file_type"

   echo
   exit
fi

# SEARCH QUERY
if [ "$query_type" == "search" ];then

   # Get input file and account
     file_to_search="$2"
     get_input_search_file "$file_to_search"

     input_account="$3"
     get_input_account_query "$input_account"

   # Create grep input to hihglight match
     grep_input=$(echo "$file_to_search")

   # Search
     if [ "$input_account" == "all" ];then
        list_accounts_to_search="$list_accounts_raw"
     else
        list_accounts_to_search=$(echo "$list_accounts_raw" | grep "$input_account")
     fi

     for account_s in $list_accounts_to_search; do
         test_match "$account_s"

         if [ "$test_match" == "yes" ];then
            echo
            get_acc_data "$account_s"
            echo "${txtbld} match found in ${txtgrn}$account_s ${txtrst}[$email]"
            show_match "$account_s"
            cat $tmp_dir/match_$account_s | grep -E --color --ignore-case  "$grep_input|$"
            match="done"
         fi
     done

     if [ "$match" != "done" ];then
        echo "$fail File not found in $input_account [use quotation marks \"file to search\"]"
     fi

     exit
fi


# SET_RC QUERY
if [ "$query_type" == "set_rc" ];then
   if [ -z $2 ];then
      echo "$fail You have to provide an account name to change to"
      echo "$usage"
      exit
   fi
   input_account="$2"
   get_input_account_query "$input_account"
   makefile_megarc "$input_account"
   echo "$ok megarc set to $input_account [$email]"
fi


# SET_DB QUERY
if [ "$query_type" == "set_db" ];then
   get_input_new_db_name "$2"

   # Test if database exists
   [[ -n $($PSQL -lt | cut -d '|' -f1 | grep -w "$new_db_name") ]] || { echo "$fail database $new_db_name does not exists"; exit 1; } 

  # Set up new name in mmega_functions
    sed -i 0,/db_name=.*/s//db_name=\"$new_db_name\"/ "$scripts_dir/mmega_functions.sh"
    test_cmd "Using database ${txtbld}$new_db_name${txtrst}"

    set_db_in_completion "$new_db_name"

    exit
fi

# STATE QUERY
if [ "$query_type" == "state" ];then
   input_account="$2"
   get_input_account_query "$input_account"

   if [ "$input_account" == "all" ];then
      echo
      show_state_all
   else
     echo
     show_state_one "$input_account"
   fi

fi

# CHANGE QUERY
if [ "$query_type" == "change" ];then
   input_account="$2"
   get_input_account_query "$input_account"

   type_change="$3"
   get_config_change "$type_change"

   new_parameter="$4"

   if [ -z "$new_parameter" ];then
      echo "$fail You must provide a new $type_change parameter"
      echo "$usage"
      exit 1
   fi

   if [ "$type_change" == "name" ];then
      set_parm='name'
      make_changes
   fi

   if [ "$type_change" == "email" ];then
      set_parm='email'
      make_changes
   fi

   if [ "$type_change" == "passwd" ];then
      set_parm='passwd'
      make_changes
   fi

   if [ "$type_change" == "local_dir" ];then
      set_parm='local_dir'
      make_changes
   fi

   if [ "$type_change" == "remote_dir" ];then
      set_parm='remote_dir'
      make_changes
   fi
fi

# SUMMARY QUERY
if [ "$query_type" == "summary" ];then
   echo
   show_summary
   show_global_state
fi

# CONFIG QUERY
if [ "$query_type" == "config" ];then
   input_account="$2"
   get_input_account_query "$input_account"

   show_passwd="$3"
   if [ "$show_passwd" == "password" ];then
      if [ "$input_account" == "all" ];then
         echo
         $PSQL -d $db_name -c "SELECT name,email, passwd, local_dir, remote_dir FROM config;"
         echo
      else
         echo
         $PSQL -d $db_name -P expanded -t -c "SELECT name, email, passwd, local_dir, remote_dir FROM config WHERE name = '$input_account';"
      fi
   elif [ "$show_passwd" == "hashed_password" ];then
      if [ "$input_account" == "all" ];then
         echo
         $PSQL -d $db_name -c "SELECT name, email, ENCODE(DIGEST('passwd', 'sha1'), 'hex') AS "'"hashed passwd"'", local_dir, remote_dir FROM config;"
         echo
      else
         echo
         $PSQL -d $db_name -P expanded -t -c "SELECT name, email, ENCODE(DIGEST('passwd', 'sha1'), 'hex') AS "'"hashed passwd"'", local_dir, remote_dir FROM config WHERE name = '$input_account';"
      fi
   else
      if [ "$input_account" == "all" ];then
         echo
         $PSQL -d $db_name -c "SELECT name,email,local_dir,remote_dir FROM config;"
         echo
      else
         echo
         $PSQL -d $db_name -P expanded -t -c "SELECT name, email, local_dir, remote_dir FROM config WHERE name = '$input_account';"
      fi
   fi
fi

# ADD QUERY
if [ "$query_type" == "add" ];then
  # Check config file
  if [ -z $2 ];then
     echo "$fail You have to provide a config file or an account name"
     exit 1
  fi

  if [ -f $2 ];then
     config_file=$2
     echo "$ok Adding accounts from config file $config_file"

     # Check empty lines
     IFS_old="$IFS"
     IFS=$'\n'
     for line in $conf_file;do
        if [[ -n "$( echo $line | grep -qxF '')" ]] || [[ -n "$( echo $line | grep -Ex '[[:space:]]+' )" ]];then
           conf_file=$( echo "$conf_file" | sed '/^\s*$/d' )
        fi
     done
     IFS="$IFS_old"

  else
     # Read args
       name="$2"
       echo "$ok Adding account $name from command line"

       if [ -n "$3" ];then
          email="$3"
       fi

       if [ -n "$4" ];then
          passwd="$4"
       fi

       if [ -n "$5" ];then
          local_dir="$5"
       fi

       if [ -n "$6" ];then
          remote_dir="$6"
       fi
   fi

   if [[ -n "$name" ]];then
      new_account="$name"
      $PSQL -d $db_name -c "INSERT INTO config (name, email, passwd, local_dir, remote_dir, created) \
                     VALUES ('$new_account', '$email', '$passwd', '$local_dir', '$remote_dir', NOW());"
      test_cmd "Creating new account $new_account"

      create_tbls_of_files "$new_account"
      insert_disk_stats "$new_account"
      insert_file_stats "$new_account"
      insert_tbl_hashes "$new_account"

      # Show new account with hashed password
      echo
      $PSQL -d $db_name -P expanded -t -c "SELECT name, email, ENCODE(DIGEST('passwd', 'sha1'), 'hex') AS "'"hashed passwd"'", local_dir, remote_dir \
                                FROM config \
                               WHERE name = '$new_account';"
   else
      # config file (one or several accounts)
      $PSQL -d $db_name -t -c "SELECT name FROM config;" | sort > $tmp_dir/old_accs
      test_cmd "Inserting new config data from file"
      insert_config_data "config"
      $PSQL -d $db_name -t -c "SELECT name FROM config;" | sort > $tmp_dir/all_accs
      new_accounts=$(comm -23 $tmp_dir/all_accs $tmp_dir/old_accs | sort)
      echo

      for new_account in $new_accounts;do
         insert_created "$new_account"
         create_tbls_of_files "$new_account"
         insert_disk_stats "$new_account"
         insert_file_stats "$new_account"
         insert_tbl_hashes "$new_account"

         # Show new account with hashed password
         echo "${txtbld}New account $new_account added ${txtrst}"
         $PSQL -d $db_name -P expanded -t -c "SELECT name, email, ENCODE(DIGEST('passwd', 'sha1'), 'hex') AS "'"hashed passwd"'", local_dir, remote_dir \
                                    FROM config \
                                   WHERE name = '$new_account';"
      done
   fi

  test_cmd "Updating global stats"
  update_global_stats

fi

# DELETE QUERY
if [ "$query_type" == "del" ];then
   input_account="$2"
   get_input_account_query "$input_account"
   delete_account "$input_account"
fi

exit
