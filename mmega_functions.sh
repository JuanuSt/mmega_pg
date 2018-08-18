#!/bin/bash

# Functions for mmega scripts
# Set password

# Common variables ###############################################################################
# Colors and symbols
  txtred=$(tput setaf 1)  # red
  txtgrn=$(tput setaf 2)  # green
  txtylw=$(tput setaf 3)  # yellow
  txtbld=$(tput bold)     # text bold
  txtrst=$(tput sgr0)     # text reset

  ok="[ ${txtgrn}OK${txtrst} ]"
  fail="[${txtred}FAIL${txtrst}]"
  wait="[ ${txtylw}--${txtrst} ]"

  yes_grn="${txtgrn}yes${txtrst}"
  no_red="${txtred}no${txtrst}"

# Binaries
  PSQL="$(which psql) -w -P pager=off -P footer=off -q" # quiet
  #PSQL="$(which psql) -P pager=off" # debug

  MEGACOPY=$(which megacopy)
  MEGARM=$(which megarm)
  MEGADF=$(which megadf)
  MEGALS=$(which megals)

# PostgreSQL user credentials
  user="$USER"
  user_passwd="" # Only used if no local connection. Don't forget delete it after creation.

# Database
  db_name="test1"

# Scripts
  scripts_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

  declare -a scripts_list=(
  "$scripts_dir/mmega_update.sh"
  "$scripts_dir/mmega_sync.sh"
  "$scripts_dir/mmega_query.sh")

# Completion
  declare -a completion_list=(
  "$scripts_dir/bash_completion/mmega_update_completion"
  "$scripts_dir/bash_completion/mmega_sync_completion"
  "$scripts_dir/bash_completion/mmega_query_completion"
  "$scripts_dir/bash_completion/mmega_rc_completion")

# Alias
  declare -a bash_aliases_path=(
  "alias mmega_create=\"$scripts_dir/mmega_create.sh\""
  "alias mmega_update=\"$scripts_dir/mmega_update.sh\""
  "alias mmega_query=\"$scripts_dir/mmega_query.sh\""
  "alias mmega_rc=\"$scripts_dir/mmega_query.sh set_rc\""
  "alias mmega_sync=\"$scripts_dir/mmega_sync.sh\"")

# Common checks #################################################################################
# Check binaries
  [ -n "$MEGACOPY" ] && [ -n "$MEGARM" ] && [ -n "$MEGADF" ] && [ -n "$MEGALS" ] || { echo "$fail binary not found"; exit 1; }

# Check postgres server
  [ -n $(pgrep postgres | head -n1) ] || { echo "$fail postgresql is not running"; exit 1; }

# Check user
  [ -n $user ] || { echo "$fail no user set"; exit 1; }

# Check scripts
  for script in "${scripts_list[@]}";do
     [ -f $script ] || { echo -e "$fail script $script not found"; exit 1; }
  done

# Check completion files
  for completion_file in "${completion_list[@]}";do
     [ -f $completion_file ] || { echo -e "$fail completion file $completion_file not found"; exit 1; }
  done

# Common functions ##############################################################################
test_cmd(){ [ $? = 0 ] && printf "%-6s %-50s\n" "$ok" "$1" || { printf "%-6s %-50s\n" "$fail" "$1"; exit 1; } }

get_list_accounts() {
  list_accounts=$($PSQL -d $db_name -t -c "SELECT name FROM config")
  [ -n "$list_accounts" ] || { printf "%-6s %-50s\n" "$fail no accounts found in table config using database $db_name"; exit 1; }
}

# mmega_create functions ########################################################################
# Create role if not exist
create_role(){
  if [ -n "$user_passwd" ];then
     sudo -u postgres $PSQL -c "DO \$\$ \
                                    BEGIN \
                                      CREATE ROLE $1 LOGIN \
                                      ENCRYPTED PASSWORD $2 \
                                      CREATEDB \
                                      NOSUPERUSER NOCREATEROLE NOINHERIT; \
                                      EXCEPTION WHEN OTHERS THEN \
                                      NULL; \
                                    END \
                                    \$\$;"
     test_cmd "Creating user ${txtbld}$1${txtrst} with password"
  else
     sudo -u postgres $PSQL -c "DO \$\$ \
                                    BEGIN \
                                      CREATE ROLE $1 LOGIN \
                                      CREATEDB \
                                      NOSUPERUSER NOCREATEROLE NOINHERIT; \
                                      EXCEPTION WHEN OTHERS THEN \
                                      NULL; \
                                    END \
                                    \$\$;"
    test_cmd "Creating user ${txtbld}$1 ${txtrst}"
  fi
}

# Create db with pgcrypto extension
create_db(){
  createdb -E UTF8 $1
  sudo -u postgres $PSQL -d "$1" -c "CREATE EXTENSION pgcrypto;"
  test_cmd "Creating database ${txtbld}$1 ${txtrst}"
}

# Create tables
create_tbl_config(){
  $PSQL -d $db_name -c "CREATE TABLE config (id SERIAL NOT NULL, \
                                 name VARCHAR(255), \
                                 email VARCHAR(255), \
                                 passwd VARCHAR(255), \
                                 local_dir VARCHAR(4096), \
                                 remote_dir VARCHAR(4096), \
                                 created TIMESTAMPTZ, \
                                 PRIMARY KEY (id));"
  test_cmd "Creating table config"
}

create_tbl_disk_stats(){
  $PSQL -d $db_name -c "CREATE TABLE disk_stats (id SERIAL NOT NULL, \
                                     name VARCHAR(255), \
                                     total_bytes BIGINT, \
                                     free_bytes BIGINT, \
                                     used_bytes BIGINT, \
                                     total VARCHAR(255), \
                                     free VARCHAR(255), \
                                     used VARCHAR(255), \
                                     last_update TIMESTAMPTZ, \
                                     PRIMARY KEY (id));"
  test_cmd "Creating table disk stats"
}

create_tbl_file_stats(){
  $PSQL -d $db_name -c "CREATE TABLE file_stats (id SERIAL NOT NULL, \
                                     name VARCHAR(255), \
                                     local INT, \
                                     remote INT, \
                                     to_down INT, \
                                     to_up INT, \
                                     sync INT, \
                                     last_update TIMESTAMPTZ, \
                                     PRIMARY KEY (id));"
  test_cmd "Creating table file stats"
}

create_tbl_global_stats(){
  $PSQL -d $db_name -c "CREATE TABLE global_stats (id SERIAL NOT NULL, \
                                       sum_acc INT, \
                                       sum_total VARCHAR(255), \
                                       sum_free VARCHAR(255), \
                                       sum_used VARCHAR(255), \
                                       sum_local INT, \
                                       sum_remote INT, \
                                       sum_to_down INT, \
                                       sum_to_up INT, \
                                       sum_sync INT, \
                                       last_update TIMESTAMPTZ, \
                                       PRIMARY KEY (id));"
  test_cmd "Creating table global stats"
}

create_tbls_of_files(){
  $PSQL -d $db_name -c "CREATE TABLE remote_files_$1 (id BIGSERIAL NOT NULL, \
                                          link VARCHAR(255), \
                                          size_bytes BIGINT, \
                                          mod_date TIMESTAMPTZ, \
                                          path VARCHAR(4096), \
                                          PRIMARY KEY (id)); \
            CREATE TABLE local_files_$1 (id BIGSERIAL NOT NULL, \
                                         size_bytes BIGINT, \
                                         mod_date TIMESTAMPTZ, \
                                         path VARCHAR(4096), \
                                         PRIMARY KEY (id)); \
            CREATE TABLE remote_directories_$1 (id BIGSERIAL NOT NULL, \
                                                mod_date TIMESTAMPTZ, \
                                                path VARCHAR(4096), \
                                                PRIMARY KEY (id)); \
            CREATE TABLE local_directories_$1 (id BIGSERIAL NOT NULL, \
                                               mod_date TIMESTAMPTZ, \
                                               path VARCHAR(4096), \
                                               PRIMARY KEY (id) );"
}

create_tbl_hashes(){
  $PSQL -d $db_name -c "CREATE TABLE hashes (id SERIAL NOT NULL, \
                                 table_name VARCHAR(255), \
                                 md5_hash CHAR(32), \
                                 last_update TIMESTAMPTZ, \
                                 PRIMARY KEY (id) );"
  test_cmd "Creating table hashes"
}

# Insert config data to database (deleting empty lines, trailing spaces and last comma from config file)
insert_config_data(){
  cat $config_file | grep ^[[:alnum:]] | sed 's/,[[:blank:]]*$//g' | \
  $PSQL -d $db_name -c "\copy config (name, email, passwd, local_dir, remote_dir) FROM stdin with delimiter as ','"
  test_cmd "Inserting accounts config data"
}

insert_created(){
  $PSQL -d $db_name -c "UPDATE config SET created=NOW() WHERE name='$1';"
}

insert_disk_stats(){
  $PSQL -d $db_name -c "INSERT INTO disk_stats (name, \
                                    total_bytes, \
                                    free_bytes, \
                                    used_bytes, \
                                    total, \
                                    free, \
                                    used, \
                                    last_update) \
                 VALUES ('$1', 0, 0, 0, '0 bytes', '0 bytes', '0 bytes', NOW());"
}

insert_file_stats(){
  $PSQL -d $db_name -c "INSERT INTO file_stats (name, local, remote, to_down, to_up, sync, last_update) \
                 VALUES ('$1', 0, 0, 0, 0, 0, NOW());"
}

insert_global_stats(){
  $PSQL -d $db_name -c "INSERT INTO global_stats (sum_acc, \
                                      sum_total, \
                                      sum_free, \
                                      sum_used, \
                                      sum_local, \
                                      sum_remote, \
                                      sum_to_down, \
                                      sum_to_up, \
                                      sum_sync, \
                                      last_update)
                VALUES ("$sum_acc", '0 bytes', '0 bytes', '0 bytes', 0, 0, 0, 0, 0, NOW() );"
}

insert_tbl_hashes(){
  $PSQL -d $db_name -c "INSERT INTO hashes (table_name, md5_hash, last_update) VALUES ('local_files_$1', 'md5_hash', NOW());
            INSERT INTO hashes (table_name, md5_hash, last_update) VALUES ('remote_files_$1', 'md5_hash', NOW());
            INSERT INTO hashes (table_name, md5_hash, last_update) VALUES ('local_directories_$1', 'md5_hash', NOW());
            INSERT INTO hashes (table_name, md5_hash, last_update) VALUES ('remote_directories_$1', 'md5_hash', NOW());"
}

set_db_name_in_mmega_functions(){
  sed -i 0,/db_name=.*/s//db_name=\"$db_name\"/ "$scripts_dir/mmega_functions.sh"
  test_cmd "Set up db name $db_name in mmega_functions"
}

set_db_in_completion(){
  echo "$wait Setting up completion files for database $1"

  # Set db
  for completion_file in "${completion_list[@]}";do
     sed -i 0,/db_name=.*/s//db_name=\"$1\"/ "$completion_file"
     sed -i 0,/db_owner=.*/s//db_owner=\"$user\"/ "$completion_file"
  done

  # Create links in /etc/bash_completion.d
  for completion_file in "${completion_list[@]}";do
     sudo ln -sf $completion_file /etc/bash_completion.d/
  done

  echo -en "\033[1A\033[2K"
  echo "$ok Set up completion files"
}

copy_bash_aliases(){
  echo "$wait Copying bash aliases"

  if [ -f ~/.bash_aliases ];then

     alias_copied=0
     for alias in "${bash_aliases_path[@]}";do
        if [[ -z $(grep -w "$alias" ~/.bash_aliases) ]];then
           echo "$alias # managed by mmega_create script" >> ~/.bash_aliases
           alias_copied=$(( alias_copied + 1 ))
        fi
     done

     if [[ $alias_copied != 0 ]];then
        echo -en "\033[1A\033[2K"
        echo "$ok $alias_copied has been copied to bash aliases"
     else
        echo -en "\033[1A\033[2K"
        echo "$ok All alias are already in bash aliases"
     fi
  else
     for alias in "${bash_aliases_path[@]}";do
        echo "$alias # managed by mmega_create script" >> ~/.bash_aliases
     done

     echo -en "\033[1A\033[2K"
     echo "$ok File ~/.bash_aliases created and aliases copied bash"
  fi
}

# mmega_update functions ########################################################################
get_input_account(){
  if [ -z $1 ];then
     echo "$fail No account name"
     echo "       $usage"
     exit 1
  fi

  # Get list accounts
    list_accounts_raw=$($PSQL -d $db_name -t -c "SELECT name FROM config" | tr -d ' ' )

    declare -a list_accounts=()
    for line in $list_accounts_raw;do
       list_accounts+=("$line")
    done

  # Set account/all
    if [ "$1" == "all" ];then
       input_account="all"
    else
       # Test if account exists
         for account in "${list_accounts[@]}";do
            if [ "$account" == "$1" ];then
               input_account="$account"
               account_found="yes"
            fi
         done

         if [ "$account_found" != "yes" ];then
            echo "$fail Account not found"
            exit 1
         fi
    fi
}

get_credentials() {
  email=$($PSQL -d $db_name -t -c "SELECT email FROM config WHERE name = '$1'" | sed -e 's/ //1' )
  passwd=$($PSQL -d $db_name -t -c "SELECT passwd FROM config WHERE name = '$1'" | sed -e 's/ //1' )

  if [ -z "$email" ] || [ -z "$passwd" ];then
     no_credentials="yes"
  fi
}

get_directories(){
  local_dir=$($PSQL -d $db_name -t -c "SELECT local_dir FROM config WHERE name = '$1'" | sed -e 's/ //1' )
  remote_dir=$($PSQL -d $db_name -t -c "SELECT remote_dir FROM config WHERE name = '$1'" | sed -e 's/ //1' )

  if [ ! -d "$local_dir" ];then
     no_local="yes"
  fi
}

# Get disk stats
get_disk_stats() {
  data_num=$($MEGADF -u "$email" -p "$passwd" 2>&1 | grep 'Total\|Free\|Used') #in bytes
  if [ -z "$data_num" ];then
     no_data="yes"
  else
     total=$(echo "$data_num" | grep  Total | cut -d ' ' -f 2)
     free=$(echo "$data_num" | grep  Free | cut -d ' ' -f 3)
     used=$(echo "$data_num" | grep  Used | cut -d ' ' -f 3)
  fi
}

get_remote_files(){
  $MEGALS -u "$email" -p "$passwd" -R --long --export > $tmp_dir/remote_files_raw_$1
  if [ $? = 1 ];then
      no_remote_files="yes"
  else
     cat $tmp_dir/remote_files_raw_$1 | sed -e 's/ \{1,\}/ /1' -e 's/ \{1,\}/ /3' -e 's/ \{1,\}/ /5' | grep ^" https" | \
                                        cut -d ' ' -f2,6,7,8,9- | sed -e 's/ /,/1' \
                                                                      -e 's/ /,/1' \
                                                                      -e 's/ /,/2' \
                                                                      -e 's/^/"/' \
                                                                      -e 's/,/","/1'\
                                                                      -e 's/,/","/2' \
                                                                      -e 's/,/","/3' \
                                                                      -e 's/"-"/"0"/1' \
                                                                      -e 's/$/"/' > $tmp_dir/remote_files_$1

     cat $tmp_dir/remote_files_raw_$1 | sed -e 's/ \{1,\}/ /1' -e 's/ \{1,\}/ /3' -e 's/ \{1,\}/ /5' | grep -v ^" https" | \
                                        cut -d ' ' -f7- | grep ^1 | cut -d ' ' -f15-  | \
                                        sed -e 's/ /,/2' \
                                            -e 's/^/"/' \
                                            -e 's/,/","/1'\
                                            -e 's/$/"/' > $tmp_dir/remote_directories_$1
  fi
}

# Insert remote files into database (from file created)
insert_remote_files(){
  # Delete table
    $PSQL -d $db_name -c "TRUNCATE remote_files_$1;" 

  # Insert file
    cat $tmp_dir/remote_files_$1 | $PSQL -d $db_name -c "\copy remote_files_$1 (link, size_bytes, mod_date, path) FROM stdin WITH NULL AS ' ' csv;" 
}


insert_remote_directories(){
  # Delete table
    $PSQL -d $db_name -c "TRUNCATE remote_directories_$1;" 

  # Insert file
    cat $tmp_dir/remote_directories_$1 | $PSQL -d $db_name -c "\copy remote_directories_$1 (mod_date, path) FROM stdin WITH NULL AS ' ' csv;"
}

complete_remote_files_tbl(){
 # Add column filename and size (test empty hash [first run] before to do it)
   # Get hash from database
     hash_db=$($PSQL -d $db_name -t -c "SELECT md5_hash FROM hashes WHERE table_name = 'remote_files_$1';" | tr -d ' ' )

     if [[ $(echo $hash_db | wc -c) -lt 33 ]];then
        $PSQL -d $db_name -c "ALTER TABLE remote_files_$1 ADD COLUMN filename VARCHAR(255);" 
        $PSQL -d $db_name -c "ALTER TABLE remote_files_$1 ADD COLUMN size VARCHAR(255);" 
     fi

 # Insert filename and size
   $PSQL -d $db_name -c "UPDATE remote_files_$1 \
                             SET filename=(regexp_replace(path, '.*/', '')), \
                                     size=pg_size_pretty(size_bytes) \
                          	 WHERE path=path;" 
 # Order by filename
   #$PSQL -d $db_name -c "ALTER TABLE local_files_$1 ORDER BY filename;"

 # Insert md5 hashes
   hash=$(md5sum $tmp_dir/remote_files_$1 | cut -d ' ' -f1)

   $PSQL -d $db_name -c "UPDATE hashes \
                             SET md5_hash='$hash', \
                                 last_update=NOW()
                           WHERE table_name='remote_files_$1';
                          UPDATE hashes \
                             SET md5_hash='$hash', \
                                 last_update=NOW()
                           WHERE table_name='remote_directories_$1';" 
}

# Get local files
get_local_files(){
 # Get files
   find "$local_dir" -type f -exec stat -c "%s %.19z %n" {} \; 2>/dev/null | sed -e 's/ /,/1' \
                                                                                 -e 's/ /,/2' \
                                                                                 -e 's/^/"/' \
                                                                                 -e 's/,/","/1'\
                                                                                 -e 's/,/","/2' \
                                                                                 -e 's/$/"/' > $tmp_dir/local_files_$1
   if [ $? = 1 ];then
      no_local_files="yes"
   fi

 # Get directories
   find "$local_dir" -type d -exec stat -c "%.19z %n" {} \; 2>/dev/null | sed -e 's/ /,/2' \
                                                                              -e 's/^/"/' \
                                                                              -e 's/,/","/1'\
                                                                              -e 's/$/"/' > $tmp_dir/local_directories_$1
}

# Insert local files into database (from file created)
insert_local_files(){
  # Delete table
    $PSQL -d $db_name -c "TRUNCATE local_files_$1;"

  # Insert file
    cat $tmp_dir/local_files_$1 | $PSQL -d $db_name -c "\copy local_files_$1 (size_bytes, mod_date, path) FROM stdin WITH NULL AS ' ' csv;"
}

insert_local_directories(){
  # Delete table
    $PSQL -d $db_name -c "TRUNCATE local_directories_$1;"

  # Insert file
    cat $tmp_dir/local_directories_$1 | $PSQL -d $db_name -c "\copy local_directories_$1 (mod_date, path) FROM stdin WITH NULL AS ' ' csv;"
}

complete_local_files_tbl(){
 # Add column filename and size (test empty hash [first run] before to do it)
   # Get hash from database
     hash_db=$($PSQL -d $db_name -t -c "SELECT md5_hash FROM hashes WHERE table_name = 'local_files_$1';" | tr -d ' ' )

     if [[ $(echo $hash_db | wc -c) -lt 33 ]];then
        $PSQL -d $db_name -c "ALTER TABLE local_files_$1 ADD COLUMN filename VARCHAR(255);" 
        $PSQL -d $db_name -c "ALTER TABLE local_files_$1 ADD COLUMN size VARCHAR(255);" 
     fi

 # Insert filename and size
   $PSQL -d $db_name -c "UPDATE local_files_$1 \
                SET filename=(regexp_replace(path, '.*/', '')), \
                    size=pg_size_pretty(size_bytes) \
              WHERE path=path;" 

 # Order by filename
   #$PSQL -d $db_name -t -c "ALTER TABLE local_files_$1 ORDER BY filename;"

 # Insert md5 hash
   hash=$(md5sum $tmp_dir/local_files_$1 | cut -d ' ' -f1)

   $PSQL -d $db_name -c "UPDATE hashes \
                SET md5_hash='$hash', \
                    last_update=NOW()
              WHERE table_name='local_files_$1';
             UPDATE hashes \
                SET md5_hash='$hash', \
                    last_update=NOW()
              WHERE table_name='local_directories_$1';" 
}

get_file_stats(){
 # Number of files local and remote
   remote=$($PSQL -d $db_name -t -c "SELECT COUNT(filename) FROM remote_files_$1;" | tr -d ' ' )
   local=$($PSQL -d $db_name -t -c "SELECT COUNT(filename) FROM local_files_$1;" | tr -d ' ')

 # Number of files to download
   to_down=$($PSQL -d $db_name -t -c "SELECT COUNT(filename) \
                            FROM remote_files_$1 \
                WHERE NOT EXISTS (SELECT filename \
                                    FROM local_files_$1 \
                                   WHERE remote_files_$1.filename=local_files_$1.filename);" | tr -d ' ')
 # Number of files to upload
   to_up=$($PSQL -d $db_name -t -c "SELECT COUNT(filename) \
                          FROM local_files_$1 \
              WHERE NOT EXISTS (SELECT filename \
                                  FROM remote_files_$1 \
                                 WHERE local_files_$1.filename=remote_files_$1.filename);" | tr -d ' ')
 # Number of synchronized files
   sync=$($PSQL -d $db_name -t -c "SELECT COUNT(filename) \
                         FROM local_files_$1 \
                 WHERE EXISTS (SELECT filename \
                                 FROM remote_files_$1 \
                                WHERE local_files_$1.filename=remote_files_$1.filename);" | tr -d ' ')
}

# Update disk stats
update_disk_stats(){
  $PSQL -d $db_name -c "UPDATE disk_stats \
               SET total_bytes='$total', \
                   free_bytes='$free', \
                   used_bytes='$used'
             WHERE name='$1'; \
            UPDATE disk_stats\
               SET total=(SELECT pg_size_pretty(total_bytes) FROM disk_stats WHERE name='$1'), \
                   free=(SELECT pg_size_pretty(free_bytes) FROM disk_stats WHERE name='$1'), \
                   used=(SELECT pg_size_pretty(used_bytes) FROM disk_stats WHERE name='$1'), \
                   last_update=NOW() \
             WHERE name='$1';" 
}

# Update files stats
update_file_stats(){
  $PSQL -d $db_name -c "UPDATE file_stats \
               SET local='$local', \
                   remote='$remote', \
                   to_down='$to_down', \
                   to_up='$to_up', \
                   sync='$sync', \
                   last_update=NOW() \
             WHERE name='$1';" 
}

# Update global stats
update_global_stats(){
  $PSQL -d $db_name -c "UPDATE global_stats \
               SET sum_acc=(SELECT COUNT(config.name) FROM config), \
                   sum_total=(SELECT pg_size_pretty(SUM(disk_stats.total_bytes)) FROM disk_stats), \
                   sum_free=(SELECT pg_size_pretty(SUM(disk_stats.free_bytes)) FROM disk_stats), \
                   sum_used=(SELECT pg_size_pretty(SUM(disk_stats.used_bytes)) FROM disk_stats), \
                   sum_local=(SELECT SUM(file_stats.local) AS local FROM file_stats), \
                   sum_remote=(SELECT SUM(file_stats.remote) AS remote FROM file_stats), \
                   sum_to_down=(SELECT SUM(file_stats.to_down) AS download FROM file_stats), \
                   sum_to_up=(SELECT SUM(file_stats.to_up) AS upload FROM file_stats), \
                   sum_sync=(SELECT SUM(file_stats.sync) AS synced FROM file_stats), \
                   last_update=NOW();" 
}

# Full checks (local files, free space and remote files)
is_account_updated(){
  echo -n "$wait Checking ${txtbld}$1${txtrst}"

  # Get credentials from database
    get_credentials "$1"
    if [ "$no_credentials" = "yes" ];then
        echo -e "\r$fail Checking ${txtred}$1${txtrst} [no credentials found]"
        no_credentials=""
        continue
    fi

  # Get directories from database
    get_directories "$1"
    if [ "$no_local" = "yes" ];then
       echo -e "\r$fail Checking ${txtred}$1${txtrst} [no local directory found]"
       no_local=""
       continue
    fi

  # Test connection with credentials and remote dir 
    connection=$($MEGALS -u "$email" -p "$passwd" "$remote_dir" 2>/dev/null | tr -d ' ')
    if [[ -z "$connection" ]]; then
       echo -e "\r$fail Checking ${txtred}$1${txtrst} [connection error]"
       connection=""
       continue
    fi

  # Test first run
    local_hash_db=$($PSQL -d $db_name -t -c "SELECT md5_hash FROM hashes WHERE table_name='local_files_$1'" | tr -d ' ' )
    remote_hash_db=$($PSQL -d $db_name -t -c "SELECT md5_hash FROM hashes WHERE table_name='remote_files_$1'" | tr -d ' ' )

    if [ "$local_hash_db" == "md5_hash" ] && [ "$remote_hash_db" == "md5_hash" ];then
       echo -e "\r$ok Checking ${txtbld}$1${txtrst} [${txtgrn}first run${txtrst}]"
       updated="no"
       first_run="yes"
    else
       # Test changes in local files (no connection)
        local_hash_db=$($PSQL -d $db_name -t -c "SELECT md5_hash FROM hashes WHERE table_name='local_files_$1'" | tr -d ' ' )
        get_local_files "$1"
        if [ "$no_local_files" = "yes" ];then
           echo -e "\r$fail Checking ${txtred}$1${txtrst} [no local files found]"
           no_local_files=""
           continue
        fi
        local_hash_updated=$(md5sum $tmp_dir/local_files_$1 | cut -d ' ' -f1)

        if [ "$local_hash_updated" != "$local_hash_db" ];then
           echo -e "\r$ok Checking ${txtbld}$1${txtrst} [${txtylw}outdated${txtrst}]"
           updated="no"
        else
           # Test changes in free espace (one connection, fast)
             get_disk_stats
             if [ "$no_data" == "yes" ];then
                echo -e "\r$fail Checking ${txtred}$1${txtrst} [no connection]"
                continue
             fi

             free_bytes_db=$($PSQL -d $db_name -t -c "SELECT free_bytes FROM disk_stats WHERE name = '$1'" | tr -d ' ' )

             if [ "$free" != "$free_bytes_db" ];then
                echo -e "\r$ok Checking ${txtbld}$1${txtrst} [${txtylw}outdated${txtrst}]"
                updated="no"
             else
                # Test changes in remote files (one connection, slow)
                  remote_hash_db=$($PSQL -d $db_name -t -c "SELECT md5_hash FROM hashes WHERE table_name='remote_files_$1'" | tr -d ' ' )
                  get_remote_files "$1"

                  if [ "$no_remote_files" = "yes" ];then
                     echo -e "\r$fail Checking ${txtred}$1${txtrst} [no remote files found]"
                     no_remote_files=""
                     continue
                  fi

                  remote_hash_updated=$(md5sum $tmp_dir/remote_files_$1 | cut -d ' ' -f1)

                  if [ "$remote_hash_updated" != "$remote_hash_db" ];then
                     echo -e "\r$ok Checked ${txtbld}$1${txtrst} [${txtylw}outdated${txtrst}]"
                     updated="no"
                  else
                     # Test sync
                       to_up=$($PSQL -d $db_name -t -c "SELECT to_up FROM file_stats WHERE name = '$1';" | tr -d ' ')
                       to_down=$($PSQL -d $db_name -t -c "SELECT to_down FROM file_stats WHERE name = '$1';" | tr -d ' ')

                       if [ "$to_up" = 0 ] && [ "$to_down" = 0 ];then
                          is_sync="and ${txtgrn}sync${txtrst}"
                       else
                          is_sync="but ${txtylw}not sync${txtrst}"
                       fi

                       echo -e "\r$ok Checked ${txtbld}${txtgrn}$1${txtrst} [${txtgrn}updated${txtrst} $is_sync]"
                       updated="yes"
                  fi
             fi
        fi
    fi

}

# Update tables (only one account). No checks errors!
update_tables(){
  echo "$wait Updating..." 

  # Update local files and disk stats
    if [ ! -f $tmp_dir/local_files_$1 ];then
       echo -en "\033[1A\033[2K"
       echo "$wait Updating disk stats..."
       get_disk_stats
       update_disk_stats "$1"

       echo -en "\033[1A\033[2K"
       echo "$wait Updating local files..."
       get_local_files "$1"
       insert_local_files "$1"
       insert_local_directories "$1"
       complete_local_files_tbl "$1"
    else
       echo -en "\033[1A\033[2K"
       echo "$wait Updating disk stats..."
       get_disk_stats
       update_disk_stats "$1"

       echo -en "\033[1A\033[2K"
       echo "$wait Updating local files..."
       insert_local_files "$1"
       insert_local_directories "$1"
       complete_local_files_tbl "$1"
    fi

  # Update remote files
    echo -en "\033[1A\033[2K"
    echo "$wait Updating remote files..."
    if [ ! -f $tmp_dir/remote_files_$1 ];then
       get_remote_files "$1"
       insert_remote_files "$1"
       insert_remote_directories "$1"
       complete_remote_files_tbl "$1"
    else
       insert_remote_files "$1"
       insert_remote_directories "$1"
       complete_remote_files_tbl "$1"
    fi

  # File stats
    get_file_stats "$1"
    update_file_stats "$1"

  # Test sync
    to_up=$($PSQL -d $db_name -t -c "SELECT to_up FROM file_stats WHERE name = '$1';" | tr -d ' ')
    to_down=$($PSQL -d $db_name -t -c "SELECT to_down FROM file_stats WHERE name = '$1';" | tr -d ' ')
    if [ "$to_up" = 0 ] && [ "$to_down" = 0 ];then
       is_sync="and ${txtgrn}sync${txtrst}"
    else
       is_sync="but ${txtylw}not sync${txtrst}"
    fi

    echo -en "\033[1A\033[2K"
    echo -en "\033[1A\033[2K" 
    echo -e "\r$ok ${txtbld}Updated ${txtgrn}$1${txtrst} [${txtgrn}updated${txtrst} $is_sync]"

}

# mmega_query functions #########################################################################
get_input_account_query(){
 # Get list accounts
   list_accounts_raw=$($PSQL -d $db_name -t -c "SELECT name FROM config" | tr -d ' ' )

   declare -a list_accounts=()
   for line in $list_accounts_raw;do
      list_accounts+=("$line")
   done

   if [ -z "$1" ] && [ "$query_type" == "files" ] ;then
      echo "$fail No account name"
      echo "$usage"
      exit 1
   fi

   if [ -z "$1" ] && [ "$query_type" == "change" ];then
      echo "$fail No account name"
      echo "$usage"
      exit 1
   fi

   if [ -z "$1" ] && [ "$query_type" == "search" ] || [ "$1" == "all" ];then
      input_account="all"
   fi

   if [ -z "$1" ] && [ "$query_type" == "state" ] || [ "$1" == "all" ];then
      input_account="all"
   fi

   if [ -z "$1" ] && [ "$query_type" == "config" ] || [ "$1" == "all" ];then
      input_account="all"
   fi

   if [ -n "$1" ] && [ "$input_account" != "all" ];then
      # Test if account exists
        for account in "${list_accounts[@]}";do
           if [ "$account" == "$1" ];then
              input_account="$account"
              account_found="yes"
           fi
        done

        if [ "$account_found" != "yes" ];then
           echo "$fail Account not found"
           exit 1
        fi
   fi
}


# Get query type
get_query_type(){
  case "$1" in
     files)
     query_type="files"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     search)
     query_type="search"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     set_rc)
     query_type="set_rc"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     set_db)
     query_type="set_db"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     state)
     query_type="state"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     change)
     query_type="change"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     config)
     query_type="config"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     summary)
     query_type="summary"
     echo "$ok Query ${txtbld}$query_type ${txtrst}"
     ;;
     add)
     query_type="add"
     echo "$ok Query ${txtbld}add account ${txtrst}"
     ;;
     del)
     query_type="del"
     echo "$ok Query ${txtbld}delete account ${txtrst}"
     ;;
     *)
     echo "$fail Unknown query type"
     echo "$usage"
     exit 1
     ;;
  esac
}

# Functions only used by FILES QUERY
get_input_file_type(){
  if [ -z $input_file_type ];then
     echo "$fail No file type"
     echo "$usage "
     exit 1
  fi

  if [ "$input_file_type" == "local" ] || [ "$input_file_type" == "remote" ] || [ "$input_file_type" == "sync" ] || \
     [ "$input_file_type" == "to_down" ] || [ "$input_file_type" == "to_up" ] || [ "$input_file_type" == "link" ];then
     input_file_type="$input_file_type"
     type_found="yes"

     # Filename or path
     if [ "$2" == "path" ];then
        show_path="yes"
     fi
  else
     echo "$fail Only local|remote|sync|to_down|to_up|link type are accepted"
     echo "$usage"
     exit 1
  fi
}

show_file_type(){
  # filname or path
  if [ "$show_path" == "yes" ];then
     filename_or_path="path"
     show_path=""
  else
     filename_or_path="filename"
  fi

  if [ "$input_file_type" == "local" ];then
     echo
     $PSQL -d $db_name -c "SELECT $filename_or_path AS \"local files $input_account\", \
                         LPAD(size, 11) AS size \
                         FROM local_files_$input_account;"

     sum=$($PSQL -d $db_name -t -c "SELECT local FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     total_size_local=$($PSQL -d $db_name -t -c "SELECT pg_size_pretty(SUM(size_bytes)) AS total_size_local \
                                       FROM local_files_$input_account;" | sed -e 's/ //1' )
     echo " $sum local files in $input_account [size $total_size_local]"
  fi

  if [ "$input_file_type" == "remote" ];then
     echo
     $PSQL -d $db_name -c "SELECT $filename_or_path AS \"remote files $input_account\", \
                         LPAD(size, 11) AS size \
                    FROM remote_files_$input_account;"

     sum=$($PSQL -d $db_name -t -c "SELECT remote FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     total_size_remote=$($PSQL -d $db_name -t -c "SELECT pg_size_pretty(SUM(size_bytes)) AS total_size_remote \
                                        FROM remote_files_$input_account;" | sed -e 's/ //1' )
     echo " $sum remote files in $input_account [size $total_size_remote]"
  fi

  if [ "$input_file_type" == "link" ];then
     echo
     $PSQL -d $db_name -c "SELECT $filename_or_path AS \"links $input_account\", \
                         link, \
                         LPAD(size, 11) AS size \
                    FROM remote_files_$input_account;"

     sum=$($PSQL -d $db_name -t -c "SELECT COUNT(remote_files_$input_account.link) FROM remote_files_$input_account;" | tr -d ' ' | tr -d '\n')
     echo " $sum links in $input_account"
  fi

  if [ "$input_file_type" == "sync" ];then
     echo
     $PSQL -d $db_name -c "SELECT $filename_or_path AS \"syncronized files $input_account\", \
                         LPAD(size, 11) AS size \
                    FROM local_files_$input_account \
            WHERE EXISTS (SELECT filename \
                            FROM remote_files_$input_account \
                           WHERE local_files_$input_account.filename=remote_files_$input_account.filename);"

     remote_sum=$($PSQL -d $db_name -t -c "SELECT remote FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     local_sum=$($PSQL -d $db_name -t -c "SELECT local FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     sync_sum=$($PSQL -d $db_name -t -c "SELECT sync FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     total_size_sync=$($PSQL -d $db_name -t -c "SELECT pg_size_pretty(SUM(size_bytes)) AS total_size_sync \
                                      FROM local_files_$input_account \
                              WHERE EXISTS (SELECT filename \
                                              FROM remote_files_$input_account \
                                             WHERE local_files_$input_account.filename=remote_files_$input_account.filename);" | sed -e 's/ //1' )
     echo " $sync_sum syncronized files in $input_account [$local_sum local $remote_sum remote] [size $total_size_sync]"
  fi

  if [ "$input_file_type" == "to_down" ];then
     echo
     $PSQL -d $db_name -c "SELECT $filename_or_path AS \"files to download from $input_account\", \
                          LPAD(size, 11) AS size \
                     FROM remote_files_$input_account \
         WHERE NOT EXISTS (SELECT filename \
                             FROM local_files_$input_account \
                            WHERE remote_files_$input_account.filename=local_files_$input_account.filename);"

      remote_sum=$($PSQL -d $db_name -t -c "SELECT remote FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
      local_sum=$($PSQL -d $db_name -t -c "SELECT local FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
      sum_to_down=$($PSQL -d $db_name -t -c "SELECT to_down FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
      total_size_to_down=$($PSQL -d $db_name -t -c "SELECT pg_size_pretty(SUM(size_bytes)) AS total_size_to_down \
                                          FROM remote_files_$input_account \
                              WHERE NOT EXISTS (SELECT filename \
                                                  FROM local_files_$input_account \
                                                 WHERE remote_files_$input_account.filename=local_files_$input_account.filename);" | sed -e 's/ //1' )
      echo " $sum_to_down files to download from $input_account [$local_sum local $remote_sum remote] [size $total_size_to_down]"
  fi

  if [ "$input_file_type" == "to_up" ];then
     echo
     $PSQL -d $db_name -c "SELECT $filename_or_path AS \"files to upload to $input_account\", \
                         LPAD(size, 11) AS size \
                    FROM local_files_$input_account \
        WHERE NOT EXISTS (SELECT filename \
                            FROM remote_files_$input_account \
                           WHERE local_files_$input_account.filename=remote_files_$input_account.filename);"

     remote_sum=$($PSQL -d $db_name -t -c "SELECT remote FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     local_sum=$($PSQL -d $db_name -t -c "SELECT local FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     sum_to_up=$($PSQL -d $db_name -t -c "SELECT to_up FROM file_stats WHERE name = '$input_account';" | tr -d ' ' | tr -d '\n')
     total_size_to_up=$($PSQL -d $db_name -t -c "SELECT pg_size_pretty(SUM(size_bytes)) AS total_size_to_up \
                                      FROM local_files_$input_account \
                          WHERE NOT EXISTS (SELECT filename \
                                              FROM remote_files_$input_account \
                                             WHERE local_files_$input_account.filename=remote_files_$input_account.filename);" | sed -e 's/ //1' )
     echo " $sum_to_up files to upload to $input_account [$local_sum local $remote_sum remote] [size $total_size_to_up]"
  fi
}

# Functions used only by SEARCH QUERY
get_input_search_file(){
   if [ -z "$file_to_search" ];then
      read -r -p "$wait Enter file to search: " file_to_search_raw
   else
      echo "$wait Processing file to search"
      file_to_search_raw="$file_to_search"
   fi

  # Delete ';'
    file_to_search_tmp=$( echo "$file_to_search_raw" | tr -d ';')

  # Limit to 255 characters
    num_char=$(echo "$file_to_search_raw" | wc -m )

    if [ $num_char -gt 255 ];then
       echo "$fail input too big (255 chars max)"
       exit 1
    else
       file_to_search="$file_to_search_tmp"

       echo -en "\033[1A\033[2K" # Delete previus line
       echo "$ok Searching: $file_to_search"

    fi
}

get_acc_data(){
  email=$($PSQL -d $db_name -t -c "SELECT email FROM config WHERE name = '$1'" | tr -d ' ' | tr -d '\n')
  local_dir=$($PSQL -d $db_name -t -c "SELECT local_dir FROM config WHERE name = '$1'" | tr -d ' ' | tr -d '\n')
  remote_dir=$($PSQL -d $db_name -t -c "SELECT remote_dir FROM config WHERE name = '$1'" | tr -d ' ' | tr -d '\n')
}

test_match(){
# Reset test variables
  test_match=""
  local_match=""
  remote_match=""

# Search $file_to_search
  local_match=$($PSQL -d $db_name -t -c "SELECT filename FROM local_files_$1 WHERE filename ILIKE '%$file_to_search%';")
  local_match_num=$($PSQL -d $db_name -t -c "SELECT COUNT (filename) FROM local_files_$1 WHERE filename ILIKE '%$file_to_search%';" | tr -d ' ' | tr -d '\n')

  remote_match=$($PSQL -d $db_name -t -c "SELECT filename FROM remote_files_$1 WHERE filename ILIKE '%$file_to_search%';")
  remote_match_num=$($PSQL -d $db_name -t -c "SELECT COUNT (filename) FROM remote_files_$1 WHERE filename ILIKE '%$file_to_search%';" | tr -d ' ' | tr -d '\n')

# Results
  total_match=$(( $local_match_num + $remote_match_num ))

  if [ -n "$local_match" ] || [ -n "$remote_match" ] ;then
     test_match="yes"
  fi

  if [ -n "$local_match" ];then
     local_match="yes"
  fi

  if [ -n "$remote_match" ];then
     remote_match="yes"
  fi
}

show_match(){
  touch $tmp_dir/match_$1

  # grep color
  if [ "$local_match_num" = 1 ] && [ "$remote_match_num" = 1 ];then
     export GREP_COLORS='ms=01;32'
  else
     export GREP_COLORS='ms=01;33'
  fi

  if [ "$local_match" == "yes" ];then
     echo " [local $yes_grn] -> $local_dir" >> $tmp_dir/match_$1
  else
     echo " [local $no_red]" >> $tmp_dir/match_$1
  fi

  if [ "$remote_match" == "yes" ];then
     echo " [remote $yes_grn] -> $remote_dir" >> $tmp_dir/match_$1
  else
     echo " [remote $no_red]" >> $tmp_dir/match_$1
  fi

  if [ "$local_match" == "yes" ] && [ "$remote_match" == "yes" ];then
     echo " [synchronized $yes_grn]" >> $tmp_dir/match_$1
  else
     echo " [synchronized $no_red]" >> $tmp_dir/match_$1
  fi

  echo "" >>$tmp_dir/match_$1

  if [ "$local_match" == "yes" ];then
     $PSQL -d $db_name -c "SELECT filename AS local_files_$1_match, \
                      LPAD(size, 11) AS size \
                 FROM local_files_$1 \
                WHERE filename ILIKE '%$file_to_search%'" >> $tmp_dir/match_$1
  fi

  if [ "$remote_match" == "yes" ];then
     $PSQL -d $db_name -c "SELECT filename AS remote_files_$1_match, \
                      LPAD(size, 11) AS size, \
                      link
                 FROM remote_files_$1 \
                WHERE filename ILIKE '%$file_to_search%'" >> $tmp_dir/match_$1
  fi

  if [ "$local_match_num" = 1 ] && [ "$remote_match_num" = 1 ];then
     echo " [full match ${txtgrn}$total_match${txtrst}] [local ${txtgrn}$local_match_num${txtrst}] [remote ${txtgrn}$remote_match_num${txtrst}]" \
          >> $tmp_dir/match_$1
  elif [ "$total_match" -lt 2 ];then
     echo " [partial match ${txtylw}$total_match${txtrst}] [local ${txtylw}$local_match_num${txtrst}] [remote ${txtylw}$remote_match_num${txtrst}]" \
          >> $tmp_dir/match_$1
  else
     echo " [multi match ${txtylw}$total_match${txtrst}] [local ${txtylw}$local_match_num${txtrst}] [remote ${txtylw}$remote_match_num${txtrst}]" \
         >> $tmp_dir/match_$1
  fi
}

# Functions used only by SET_RC QUERY
makefile_megarc(){
  # Get credentials
    email=$($PSQL -d $db_name -t -c "SELECT email FROM config WHERE name = '$input_account'" | tr -d ' ' | tr -d '\n')
    passwd=$($PSQL -d $db_name -t -c "SELECT passwd FROM config WHERE name = '$input_account'" | sed -e 's/ //1')

    if [ -z "$email" ] || [ -z "$passwd" ];then
       printf "%-6s %-50s\n" "$fail Error getting credentials for account $input_account [Using database $db_name ]"
       exit 1
    fi

  # Conctruct megarc file (the original one will be delete)
    echo "[Login]" > ~/.megarc
    echo "Username = $email" >> ~/.megarc
    echo "Password = $passwd" >> ~/.megarc
}

# Functions used only by SET_DB QUERY
get_input_new_db_name(){
   if [ -z $1 ];then
      read -r -p "Enter name for database: " new_db_name_raw
   else
      new_db_name_raw="$1"
   fi

  # Only alphanumeric or an underscore characters
    new_db_name_tmp=${new_db_name_raw//[^a-zA-Z0-9_]/}

  # Limit to 255 characters
    num_char=$(echo "$new_db_name_tmp" | wc -m )

    if [ $num_char -gt 255 ];then
       echo "$fail input too big (255 chars max)"
       exit 1
    else
       new_db_name="$new_db_name_tmp"
    fi
}

# Functions used only by STATE QUERY (or others scripts)
show_state_all(){
  $PSQL -d $db_name -c "SELECT name AS "'"disk stats"'", \
                   LPAD(total,11) AS total, \
                   LPAD(free,11) AS free, \
                   LPAD(used,11) AS used, \
                   TRUNC(((free_bytes::decimal / total_bytes::decimal) * 100),1) AS "'"% free"'", \
                   to_char(last_update, 'DD-MM-YYYY HH24:MI:SS') AS "'"last update"'" \
              FROM disk_stats;"

  $PSQL -d $db_name -c "SELECT name AS "'"file stats"'", \
                   local, \
                   remote, \
                   to_down AS "'"to down"'", \
                   to_up AS "'"to up"'", \
                   sync, \
                   CASE WHEN to_down=0 AND to_up=0 THEN 'yes' ELSE 'no' END AS synced, \
                   to_char(last_update, 'DD-MM-YYYY HH24:MI:SS') AS "'"last update"'" \
              FROM file_stats;"
}

show_state_one(){
  # Get name
    name=$($PSQL -d $db_name -t -c "SELECT name FROM disk_stats WHERE name = '$1';" | tr -d ' ' )

  # Get percentage free space
    per_free=$($PSQL -d $db_name -t -c "SELECT TRUNC(((free_bytes::decimal / total_bytes::decimal) * 100),1) FROM disk_stats WHERE name = '$1';" | tr -d ' ' )

  # Get synced
    synced=$($PSQL -d $db_name -t -c "SELECT CASE WHEN to_down=0 AND to_up=0 THEN 'yes' ELSE 'no' END FROM file_stats WHERE name = '$1';" | tr -d ' ' )

  echo "${txtbld}$name${txtrst} $per_free% free synced $synced"
  echo

  $PSQL -d $db_name -P expanded -t -c "SELECT LPAD(total,14) AS "'"total  "'", \
                                  LPAD(free,14) AS free, \
                                  LPAD(used,14) AS used \
                             FROM disk_stats \
                            WHERE name = '$1';"

  $PSQL -d $db_name -P expanded -t -c "SELECT LPAD(CONCAT(local, ' files'),14) AS local, \
                                  LPAD(CONCAT(remote, ' files'),14) AS remote, \
                                  LPAD(CONCAT(to_down, ' files'),14) AS "'"to down"'", \
                                  LPAD(CONCAT(to_up, ' files'),14) AS "'"to up"'", \
                                  LPAD(CONCAT(sync, ' files'),14) AS "'"synced"'"
                             FROM file_stats \
                            WHERE name = '$1';"
}

# Functions used by SUMMARY QUERY
show_summary(){
  $PSQL -d $db_name -c "SELECT config.name, \
                   config.email, \
                   LPAD(free,11) AS free, \
                   TRUNC(((free_bytes::decimal / total_bytes::decimal) * 100),1) AS "'"% free"'", \
                   file_stats.local, \
                   file_stats.remote, \
                   CASE WHEN to_down=0 AND to_up=0 THEN 'yes' ELSE 'no' END AS synced, \
                   to_char(disk_stats.last_update, 'DD-MM-YYYY HH24:MI:SS') AS "'"last update"'" \
              FROM config, disk_stats, file_stats \
             WHERE config.name = disk_stats.name \
               AND config.name = file_stats.name;"
}

show_global_state(){
  sum_acc=$($PSQL -d $db_name -t -c "SELECT CAST(sum_acc AS TEXT) FROM global_stats;" | sed -e s'/ //1' | cut -b 1-12 ) # Show only 12 chars
  sum_total=$($PSQL -d $db_name -t -c "SELECT sum_total FROM global_stats;" | sed -e s'/ //1' )
  sum_free=$($PSQL -d $db_name -t -c "SELECT sum_free FROM global_stats;" | sed -e s'/ //1' )
  sum_used=$($PSQL -d $db_name -t -c "SELECT sum_used FROM global_stats;" | sed -e s'/ //1' )

  sum_local=$($PSQL -d $db_name -t -c "SELECT sum_local FROM global_stats;" | tr -d ' ' )
  sum_remote=$($PSQL -d $db_name -t -c "SELECT sum_remote FROM global_stats;" | tr -d ' ' )
  sum_to_down=$($PSQL -d $db_name -t -c "SELECT sum_to_down FROM global_stats;" | tr -d ' ' )
  sum_to_up=$($PSQL -d $db_name -t -c "SELECT sum_to_up FROM global_stats;" | tr -d ' ' )
  sum_sync=$($PSQL -d $db_name -t -c "SELECT sum_sync FROM global_stats;" | tr -d ' ' )

  last_update=$($PSQL -d $db_name -t -c "SELECT to_char(last_update, 'DD-MM-YYYY HH24:MI:SS') FROM global_stats;" | sed -e s'/ //1' )

  printf "%1s %-8s %12s %10s %-7s %8s %-5s\n" "" "database" "$db_name"   "" "local"   "$sum_local"   "files"
  printf "%1s %-8s %12s %10s %-7s %8s %-5s\n" "" "accounts" "$sum_acc"   "" "remote"  "$sum_local"   "files"
  printf "%1s %-8s %12s %10s %-7s %8s %-5s\n" "" "space"    "$sum_total" "" "to down" "$sum_to_down" "files"
  printf "%1s %-8s %12s %10s %-7s %8s %-5s\n" "" "free"     "$sum_free"  "" "to up"   "$sum_to_up"   "files"
  printf "%1s %-8s %12s %10s %-7s %8s %-5s\n" "" "used"     "$sum_used"  "" "synced"  "$sum_sync"    "files"
  echo

}


# not used
show_global_state_old(){
  $PSQL -d $db_name -P expanded -t -c "SELECT LPAD(CAST(sum_acc AS TEXT),19) AS accounts \
                             FROM global_stats;"

  $PSQL -d $db_name -P expanded -t -c "SELECT LPAD(sum_total,19) AS "'"space"'", \
                                  LPAD(sum_free,19) AS "'"free"'", \
                                  LPAD(sum_used,19) AS "'"used"'"
                             FROM global_stats;"

  $PSQL -d $db_name -P expanded -t -c "SELECT LPAD(CONCAT(sum_local, ' files'),15) AS "'"local files"'", \
                                  LPAD(CONCAT(sum_remote, ' files'),15) AS "'"remote files"'", \
                                  LPAD(CONCAT(sum_to_down, ' files'),15) AS "'"to download"'", \
                                  LPAD(CONCAT(sum_to_up, ' files'),15) AS "'"to upload"'", \
                                  LPAD(CONCAT(sum_sync, ' files'),15) AS "'"synchronized"'" \
                             FROM global_stats;"

  $PSQL -d $db_name -P expanded -t -c "SELECT to_char(last_update, 'DD-MM-YYYY HH24:MI:SS') AS "'"last update"'" \
                             FROM global_stats;"

}

# Functions used by CHANGE QUERY
get_config_change(){
  if [ -n "$1" ] && [ "$1" == "name" ] || [ "$1" == "email" ] || [ "$1" == "passwd" ] || \
     [ "$1" == "local_dir" ] || [ "$1" == "remote_dir" ];then
     type_change="$1"
  else
    echo "$fail Only name, email, passwd, local_dir and remote_dir can be changed"
    echo "$usage"
    exit 1
  fi
}

make_changes(){
  # update config
    echo "$wait Changing config $set_parm"
    $PSQL -d $db_name -c "UPDATE config SET $set_parm='$new_parameter' WHERE name = '$input_account';"

    if [ "$set_parm" == "name" ];then # Change name in all others tables
       new_name="$new_parameter"

       $PSQL -d $db_name -t -c " \
         UPDATE disk_stats SET name='$new_name' WHERE name = '$input_account'; \
         UPDATE file_stats SET name='$new_name' WHERE name = '$input_account'; \
         UPDATE hashes SET table_name='local_files_$new_name' WHERE table_name = 'local_files_$input_account'; \
         UPDATE hashes SET table_name='remote_files_$new_name' WHERE table_name = 'remote_files_$input_account'; \
         UPDATE hashes SET table_name='local_directories_$new_name' WHERE table_name = 'local_directories_$input_account'; \
         UPDATE hashes SET table_name='remote_directories_$new_name' WHERE table_name = 'remote_directories_$input_account'; \
         ALTER TABLE local_files_$input_account RENAME TO local_files_$new_name; \
         ALTER TABLE local_files_$(echo -n $input_account)_id_seq RENAME TO local_files_$(echo -n $new_name)_id_seq; \
         ALTER TABLE remote_files_$input_account RENAME TO remote_files_$new_name; \
         ALTER TABLE remote_files_$(echo -n $input_account)_id_seq RENAME TO remote_files_$(echo -n $new_name)_id_seq; \
         ALTER TABLE local_directories_$input_account RENAME TO local_directories_$new_name; \
         ALTER TABLE local_directories_$(echo -n $input_account)_id_seq RENAME TO local_directories_$(echo -n $new_name)_id_seq; \
         ALTER TABLE remote_directories_$input_account RENAME TO remote_directories_$new_name; \
         ALTER TABLE remote_directories_$(echo -n $input_account)_id_seq RENAME TO remote_directories_$(echo -n $new_name)_id_seq;"
    fi

    echo -en "\033[1A\033[2K"
    echo "$ok $set_parm changed to $new_parameter"

  # show new config
    if [ "$set_parm" == "name" ];then
       input_account="$new_parameter"
    fi
    echo
    echo "${txtbld}New config ${txtrst}"

    if [ "$set_parm" == "passwd" ]; then
       $PSQL -d $db_name -P expanded -t -c " \
         SELECT name, email, passwd, local_dir, remote_dir \
           FROM config \
          WHERE name = '$input_account';"
    else
       $PSQL -d $db_name -P expanded -t -c " \
        SELECT name, email, ENCODE(DIGEST('passwd', 'sha1'), 'hex') AS "'"hashed passwd"'", local_dir, remote_dir \
          FROM config \
         WHERE name = '$input_account';"
    fi
}

# Functions used by ADD QUERY
  # create_tbls_of_files (mmega_create functions)
  # insert_config_data (mmega_create functions)
  # insert_created (mmega_create functions)
  # insert_disk_stats (mmega_create functions)
  # insert_file_stats (mmega_create functions)
  # insert_tbl_hashes (mmega_create functions)
  # update_global_stats (mmega_update functions)

# Functions used by DEL QUERY
delete_account(){
   if [ -z "$1" ];then
      echo "$fail You have to provide an account to delete"
      echo "$usage"
      exit 1
   fi

  # Delete rows from config, disk stats and file stats
  $PSQL -d $db_name -c "DELETE FROM config WHERE name =  '$input_account'; \
            DELETE FROM disk_stats WHERE name = '$input_account'; \
            DELETE FROM file_stats WHERE name = '$input_account';"
  test_cmd "Deleting rows from config, disk stats and file stats"

  # Delete tables of hashes
  $PSQL -d $db_name -c "DELETE FROM hashes WHERE table_name = 'local_files_$input_account'; \
            DELETE FROM hashes WHERE table_name = 'remote_files_$input_account'; \
            DELETE FROM hashes WHERE table_name = 'local_directories_$input_account'; \
            DELETE FROM hashes WHERE table_name = 'remote_directories_$input_account';"
  test_cmd "Deleting tables of hashes"

  # Delete tables of files
  $PSQL -d $db_name -c "DROP table local_files_$input_account; \
            DROP table remote_files_$input_account; \
            DROP table local_directories_$input_account; \
            DROP table remote_directories_$input_account;"
  test_cmd "Deleting tables of files"
  
  update_global_stats
  test_cmd "Updating global stats"
}

# mmega_sync functions ##########################################################################
get_sync_action(){
  if [ -z "$1" ];then
     echo "$fail No sync type seleted"
     echo "       $usage"
     exit 1
  fi

  if [ "$1" == "up" ] || [ "$1" == "down" ];then
     action_type="$1"

     if [ "$2" == "no-confirm" ];then
        confirm="no"
     else
        confirm="yes"
     fi

  elif [ "$1" == "sync" ];then
     action_type="$1"

     if [ -z "$2" ];then
        echo "$fail sync type need direction parameter [with_local or with_remote]"
        echo "       $usage"
        exit 1
     elif [ "$2" == "with_local" ] || [ "$2" == "with_remote" ];then
        direction="$2"

        if [ "$3" == "no-confirm" ];then
           confirm="no"
        else
           confirm="yes"
        fi

     else
        echo "$fail sync direction only accept <with_local|with_remote> options"
        echo "       $usage"
        exit 1
     fi
  else
     echo "$fail Only up|down|sync type are accepted"
     echo "       $usage"
     exit 1
  fi
}

upload(){
  # Show files to upload
    $PSQL -d $db_name -c "SELECT path AS \"files to upload to $1\", \
                        LPAD(size, 11) AS size \
                   FROM local_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                           FROM remote_files_$1 \
                          WHERE local_files_$1.filename=remote_files_$1.filename);"

    to_up=$($PSQL -d $db_name -t -c "SELECT to_up FROM file_stats WHERE name = '$1';" | tr -d ' ')
    echo " $to_up files to upload to $1"
    echo

  # Confirmation
    if [ "$confirm" == "no" ];then
       confirm=""
       confirmation="upload files"
       echo "$ok $confirmation"
      
       # Upload local files
         to_up=""
         echo "$wait Uploading files to $1"
         $MEGACOPY -u "$email" -p "$passwd" --reload --local "$local_dir" --remote "$remote_dir" 2>/dev/null
         echo; $scripts_dir/mmega_update.sh "$1" # Update database
    else
       confirm=""
       read -n 1 -s -r -e -p "$wait Upload? (y/n) " confirmation
 
       if [[ "$confirmation" =~ [Yy|YesYES]$ ]]; then
          echo -en "\033[1A\033[2K" # Delete previus line
          confirmation="upload files"
          echo "$ok $confirmation"
          # Upload local files
            to_up=""
            echo "$wait Uploading files to $1"
            $MEGACOPY -u "$email" -p "$passwd" --reload --local "$local_dir" --remote "$remote_dir" 2>/dev/null
            echo; $scripts_dir/mmega_update.sh "$1" # Update database
        else
           echo -en "\033[1A\033[2K"
           confirmation="upload canceled"
           echo "$ok $confirmation"
           exit
        fi

    fi
    
}

download(){
  # Show files to download
    $PSQL -d $db_name -c "SELECT path AS \"files to download from $1\", \
                        LPAD(size, 11) AS size \
                   FROM remote_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                           FROM local_files_$1 \
                          WHERE remote_files_$1.filename=local_files_$1.filename);"

    to_down=$($PSQL -d $db_name -t -c "SELECT to_down FROM file_stats WHERE name = '$1';" | tr -d ' ' )
    echo " $to_down files to download from $1"
    echo

  # Confirmation
    if [ "$confirm" == "no" ];then
       confirm=""
       confirmation="download files"
       echo "$ok $confirmation"

       # Download remote files
         echo "$wait Downloading files from $1"
         $MEGACOPY -u "$email" -p "$passwd" --reload --download --local "$local_dir" --remote "$remote_dir" 2>/dev/null
         echo; $scripts_dir/mmega_update.sh "$1" # Update database
    else
      confirm=""
      read -n 1 -s -r -e -p "$wait download? (y/n) " confirmation

      if [[ "$confirmation" =~ [Yy|YesYES]$ ]]; then
         echo -en "\033[1A\033[2K" # Delete previus line
         confirmation="download files"
         echo "$ok $confirmation"

         # Download remote files
           echo "$wait Downloading files from $1"
           $MEGACOPY -u "$email" -p "$passwd" --reload --download --local "$local_dir" --remote "$remote_dir" 2>/dev/null
           echo; $scripts_dir/mmega_update.sh "$1" # Update database
       else
         echo -en "\033[1A\033[2K"
         confirmation="download canceled"
         echo "$ok $confirmation"
         exit
       fi
    fi

}

download_remote_files(){
 if [ "$to_download" != 0 ];then
    to_download=0
    echo "$wait Downloading files from $1"
    echo
    $MEGACOPY -u "$email" -p "$passwd" --reload --download --local "$local_dir" --remote "$remote_dir" 2>/dev/null
 fi
}

delete_local_files(){
  # Delete files
  if [ "$to_delete" != 0 ];then
     to_delete=0
     echo "$wait" "Deleting local files"
     old_IFS="$IFS"
     IFS=$'\n'
     for file in $(cat $tmp_dir/local_files_to_delete_$1);do
         #file=$( echo "$file" | sed -e s'/ //1') # Delete leading space in path
         echo "Deleting local $file"
         rm -- "$file"
     done
     IFS="$old_IFS"

  fi

  # Delete empty directoires @TODO it does not delete if empty dir is more than 1 in depth
    old_IFS="$IFS"
    IFS=$'\n'
    for directory in $(cat $tmp_dir/local_directories_to_check_$1);do
        directory=$( echo $directory | sed -e s'/ //1') # Delete leading space in path
        if find "$directory" -mindepth 1 -type d | read; then
           echo "not empty directory $directory"
        else
          echo "Deleting local directory $directory"
          rm -r -- "$directory"
        fi
    done
    IFS="$old_IFS"
}

# Synchronize local directory with remote directory (it will download remote files and delete local files that are not in remote!)
sync_with_remote(){
  printf "%-s\n" "${txtbld} Synchronizing $1 with remote directory ${txtrst}"
  echo

  # Get (from database) local files (with path) to delete
    $PSQL -d $db_name -A -t -c "SELECT path AS local_files_to_delete_from_$1 \
                   FROM local_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                           FROM remote_files_$1 \
                          WHERE local_files_$1.filename=remote_files_$1.filename);" > $tmp_dir/local_files_to_delete_$1

  # Get local directories to check and delete if empty
    $PSQL -d $db_name -t -c "SELECT path AS directories_to_check_from_$1 FROM local_directories_$1;" > $tmp_dir/local_directories_to_check_$1

  # Show local files (from database) to delete
    $PSQL -d $db_name -c "SELECT path AS \"local files to delete from $1\", \
                        LPAD(size, 11) AS size \
                   FROM local_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                           FROM remote_files_$1 \
                          WHERE local_files_$1.filename=remote_files_$1.filename);"

  # Show files (from database) to download
    $PSQL -d $db_name -c "SELECT path AS \"files to download from $1\", \
                        LPAD(size, 11) AS size \
                   FROM remote_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                          FROM local_files_$1 \
                         WHERE remote_files_$1.filename=local_files_$1.filename);"

    to_delete=$($PSQL -d $db_name -t -c "SELECT to_up FROM file_stats WHERE name = '$1';" | tr -d ' ')
    echo " $to_delete local files to delete from $1"

    to_download=$($PSQL -d $db_name -t -c "SELECT to_down FROM file_stats WHERE name = '$1';" | tr -d ' ' )
    echo " $to_download remote files to download from $1"
    echo

 # Confirmation
   if [ "$confirm" == "no" ];then
      confirm=""
      confirmation="synchronize account"
      echo "$ok $confirmation"
      download_remote_files "$1"
      delete_local_files "$1"
      echo; $scripts_dir/mmega_update.sh "$1" # Update database
   else
      confirm=""
      read -n 1 -s -r -p "$wait ${txtbld}S${txtrst}ync  ${txtbld}C${txtrst}ancel  ${txtbld}D${txtrst}ownload_only  D${txtbld}e${txtrst}lete_only" confirmation
      echo

      if [[ "$confirmation" =~ [Ss]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="synchronize account"
         echo "$ok $confirmation"
         download_remote_files "$1"
         delete_local_files "$1"
         echo; $scripts_dir/mmega_update.sh "$1" # Update database

      elif [[ "$confirmation" =~ [Dd]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="download only"
         echo "$ok $confirmation"
         download_remote_files "$1"
         echo; $scripts_dir/mmega_update.sh "$1" # Update database

      elif [[ "$confirmation" =~ [Ee]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="delete only"
         echo "$ok $confirmation"
         delete_local_files "$1"
         echo; $scripts_dir/mmega_update.sh "$1" # Update database
      else
         echo -en "\033[1A\033[2K"
         confirmation="remote synchronization canceled"
         echo "$ok $confirmation"
      fi
   fi
}

# Changes in if conditions
upload_local_files(){
  if [ "$to_upload" != 0 ];then
     to_upload=""
     echo "$wait Uploading files to $1"
     $MEGACOPY -u "$email" -p "$passwd" --reload --local "$local_dir" --remote "$remote_dir" #2>/dev/null
  fi
}

delete_remote_files(){
  if [ "$to_delete" != 0 ];then
     to_detele=""
     printf "%-6s %-50s\n" "$wait" "Deleting remote files"

     old_IFS="$IFS"
     IFS=$'\n'
     for file in $(cat $tmp_dir/remote_files_to_delete_$1);do
         file=$( echo $file | sed -e s'/ //1') # Delete leading space in path
         echo "Deleting remote file $file"
         $MEGARM -u "$email" -p "$passwd" --reload "$file" 2>/dev/null
     done

     # Delete empty directoires
       for directory in $(cat $tmp_dir/remote_directories_to_check_$1);do
           directory=$( echo $directory | sed -e s'/ //1') # Delete leading space in path
           empty=$($MEGALS -u "$email" -p "$passwd" --reload -R "$directory" | grep -oP ^"$directory/\K.*")
           if [ -z "$empty" ];then
              echo "Deleting remote directory $directory"
              $MEGARM -u "$email" -p "$passwd" --reload "$directory" 2>/dev/null
           fi
       done
       IFS="$old_IFS"

  fi
}

# Synchronize remote directory with local directory (it will upload local files and delete the remote files that are not in local!)
sync_with_local(){
  printf "%-s\n" "${txtbld} Synchronizing $1 with local directory ${txtrst}"
  echo

  # Get (from database) remote files (with path) to delete
    $PSQL -d $db_name -t -c "SELECT path AS remote_files_to_delete_from_$1 \
                   FROM remote_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                           FROM local_files_$1 \
                          WHERE remote_files_$1.filename=local_files_$1.filename);" > $tmp_dir/remote_files_to_delete_$1

  # Get remote directories to check and delete if empty
    $PSQL -d $db_name -t -c "SELECT path AS directories_to_check_from_$1 FROM remote_directories_$1;" > $tmp_dir/remote_directories_to_check_$1

  # Show remote files (from database) to delete
    $PSQL -d $db_name -c "SELECT path AS \"remote files to delete from $1\", \
                        LPAD(size, 11) AS size \
                FROM remote_files_$1 \
    WHERE NOT EXISTS (SELECT filename \
                        FROM local_files_$1 \
                       WHERE remote_files_$1.filename=local_files_$1.filename);"

  # Show local files to upload
    $PSQL -d $db_name -c "SELECT path AS \"local files to upload to $1\", \
                        LPAD(size, 11) AS size \
                   FROM local_files_$1 \
       WHERE NOT EXISTS (SELECT filename \
                           FROM remote_files_$1 \
                          WHERE local_files_$1.filename=remote_files_$1.filename);"

  # Show numbers of files
    to_delete=$($PSQL -d $db_name -t -c "SELECT to_down FROM file_stats WHERE name = '$1';" | tr -d ' ' )
    echo " $to_delete remote files to delete from $1"

    to_upload=$($PSQL -d $db_name -t -c "SELECT to_up FROM file_stats WHERE name = '$1';" | tr -d ' ')
    echo " $to_upload local files to upload to $1"
    echo

  # Confirmation
  if [ "$confirm" == "no" ];then
      confirm=""
      confirmation="synchronize account"
      echo "$ok $confirmation"
      upload_local_files "$1"
      delete_remote_files "$1"
      echo; $scripts_dir/mmega_update.sh "$1" # Update database
   else
      confirm=""
      read -n 1 -s -r -p "$wait ${txtbld}S${txtrst}ync  ${txtbld}C${txtrst}ancel  ${txtbld}U${txtrst}pload_only  D${txtbld}e${txtrst}lete_only" confirmation
      echo

      if [[ "$confirmation" =~ [Ss]$ ]]; then
         echo -en "\033[1A\033[2K" # Delete previus line
         confirmation="synchronize account"
         echo "$ok $confirmation"
         upload_local_files "$1"
         delete_remote_files "$1"
         echo; $scripts_dir/mmega_update.sh "$1" # Update database

      elif [[ "$confirmation" =~ [Uu]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="upload only"
         echo "$ok $confirmation"
         upload_local_files "$1"
         echo; $scripts_dir/mmega_update.sh "$1" # Update database
      elif [[ "$confirmation" =~ [Ee]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="delete only"
         echo "$ok $confirmation"
         delete_remote_files "$1"
         echo; $scripts_dir/mmega_update.sh "$1" # Update database
      else
         echo -en "\033[1A\033[2K"
         confirmation="local synchronization canceled"
         echo "$ok $confirmation"
      fi
   fi
}

sync_action(){
 # Test if database is updated
   is_account_updated "$1"

   if [ "$updated" == "no" ];then
      update_tables "$1"
   fi

   if [ "$is_sync" == "yes" ];then
      echo "$ok Account is already synced"
      exit 1
   fi

 # Select action
   if [ "$2" == "up" ];then
      to_up=$($PSQL -d $db_name -t -c "SELECT to_up from file_stats where name = '$1';" | tr -d ' ')

      if [ "$to_up" = 0 ];then
         echo "$ok Remote directory has every file [nothing to upload]"
      else
         echo
         upload "$1"
      fi
   fi

   if [ "$2" == "down" ];then
      to_down=$($PSQL -d $db_name -t -c "SELECT to_down from file_stats where name = '$1';" | tr -d ' ')

      if [ $to_down = 0 ];then
         echo "$ok Local directory has every file [nothing to download]"
      else
         echo
         download "$1"
      fi
   fi

   if [ "$2" == "sync" ];then

      if [ "$3" == "with_local" ];then
         echo
         sync_with_local "$1"
      fi

      if [ "$3" == "with_remote" ];then
         echo
         sync_with_remote "$1"
      fi
   fi
}

show_sync_files(){
  # Show sync files
    echo "${txtbld} Syncronized files ${txtrst}"
    $PSQL -d $db_name -t -c "SELECT filename AS sync_files_of_$1 \
                         FROM local_files_$1 \
                 WHERE EXISTS (SELECT filename \
                                 FROM remote_files_$1 \
                                WHERE local_files_$1.filename=remote_files_$1.filename);"

  # Get number of sync files
    sync_files=$($PSQL -d $db_name -t -c "SELECT sync FROM file_stats WHERE name = '$1';")

  echo " $sum syncronized files in $1"
  echo
}


## END ##



