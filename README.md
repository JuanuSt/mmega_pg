# MEGAtools multi-account [ powered by PostgreSQL ] 
Check and administrate several registered accounts in mega.nz cloud using the nice code [megatools](https://github.com/megous/megatools) written by [megaus](https://github.com/megous).

This version uses PostgreSQL to store accounts and files info (check out [MySQL flavor](https://bitbucket.org/juanust/mmega_my/overview)). Storing the files info into a database allows to consult all accounts all at once, search for files or get remote links very quickly.

### Dependencies
* megatools 1.9.97 
* PostgreSQL 9.5.13  (it might work in higher versions)
* Some bash specific commands 

### Install
* Install megatools `apt install megatools`.
* Install PostgreSQL `apt install postgresql`. Encoding is set to UTF-8 during database creation.
* Clone this repository `git clone git@bitbucket.org:juanust/mmega_pg.git`.
* If access to the database is done through the network, it is necessary to set PostgreSQL **user's password** at the beginning of `mmega_functions.sh`: `user_passwd="Your P@assW0rd"`

> User and password are needed only during database creation and for granting privileges. User is already set to `$USER`, so if you are running this script as normal user it will be set to this user. The password is only used if no local connection, if you set it don't forget delete it after database has been created.
> When creating database the script uses `sudo -u postgres` to created it, so you will be asked for your sudo password, but never run this script as root.

### How it works
The suite is composed by five scripts:

|Script|Function|
|--|--|
| mmega_functions | It contains all suite's functions (it is not executed directly) |
| mmega_create | To create the database from a config file |
| mmega_update | To get data and store them in database |
| mmega_query | To interact with the database and retrieve info |
| mmega_sync | To interact with the accounts (**risky!**) |

As in [first version](https://bitbucket.org/juanust/mmega), we start with a config file with account's parameters (login and directories) for each account (see below). This file is just parsed slightly to check common mistakes in format (five fields comma separated), so make sure that it haven't any trailing spaces or empty lines. Using this file `mmega_create.sh` will create the database based on the accounts found there.

### Config file
It contains the account's parameters per line. The structure is comma separated with 5 fields:

    name1,email1,passwd1,local_dir1,remote_dir1,
    name2,email2,passwd2,local_dir2,remote_dir2,
    name3,email3,passwd3,local_dir3,remote_dir3,
    ...

| Field | Description |
|--|--|
| name | The name to describe the account |
| email | The registered email in mega.nz | 
| passwd | The registered account password (in plaintext) |
| local_dir | The account's local directory |
| remote_dir | The account's remote directory (often /Root) | 

# Scripts
### mmega_create
See intall before running this script.
```
USAGE = mmega_create <db_name> <config_file>
```

> Alternatively the arguments **db_name** and **config_file** path can be established directly in the`mmega_create.sh`.

Execute `./mmega_create.sh <db_name> <config_file>`. If there were no errors the script:

 * will create the database
 * will insert the config info for each account
 * will create file's tables accordingly to config file
 * will insert the database's name in other scripts (mmega_update, mmega_query and mmega_sync)
 * will set this database in the four completion files and create links to them
 * will copy bash aliases (see bellow)

>It will also insert default values (all of them zero) and will show the config table without password.

These aliases will be added to your *~/.bash_aliases* file:
 
    alias mmega_create="~/scripts_dir/mmega_create.sh
    alias mmega_update="~/scripts_dir/mmega_update.sh"
    alias mmega_sync="~/scripts_dir/mmega_sync.sh"
    alias mmega_query="~/scripts_dir/mega/mmega_query.sh"
    alias mmega_rc="~/scripts_dir/mmega_query.sh set_rc" (see below for this alias)

Source with `source ~/.bashrc` to reload completion files and aliases. From this moment all accounts and options in the scripts will be available with TAB.

>If you only use one database this script only runs once.

### mmega_update
```
USAGE = mmega_update <account_name|all>
```
After database creation this script will check local directory, will contact mega.nz to check remote one and will insert all file's info into the database. First, it makes a check for each account to detect changes in local or remote directories. The check consists in three steps:

1. It get local files info, creates a file with path, size and modification date of each file and hashs this file (md5). The hash is compared with that stored in database, if they are different the database is considerated outdated.

2. If the hashes are identical (no changes in local directory) then it proceeds to check the free space in remote directory and compares it against that stored in the database. If they are different the database is considerated outdated.
   >  This connection is fast.
3. Even if free space is identical the script makes a second connection to retrieve remote files info (some modifications as 0 bytes files are not detected). It creates a file (path, size, modification date and link) and hashs it. This hash is compared with that stored in database, if they are different the database is considerated outdated.
   >This connection is slowed down by the mega servers when creating the links. All links are created without password (see note about links).
   
If any check declares the database outdated it proceeds to update the database. In order to increase performance only the operations strictly needed are done.

1. If there were changes in the local files, the script inserts into the database the file created in the previous step, connects to mega.nz twice to get the disk usage (`megadf`) and remote files info (`megals --long --export /Root`), and inserts these data into the database.
2. If there were changes in disk usage, the script inserts into the database the local files and the disk usage info created both in the previous step, it connects to mega.nz once to retrieve the files remote info and inserts these data into the database.
3. If there were changes in the remote files the script inserts into the database the local files, remote files and disk usage info created all in the previous step.

> When it runs by the first time it alters file's tables adding filename column (extracted from path) and size column (in humand readable form).

### mmega_query
```
USAGE = mmega_query config|account|files|change|add|del|search|set_rc|set_db|summary [options by query]

        config  <account_name|all> [defautl all] [optional hashed_password|password] 
        state   <account_name|all> [defautl all]
        files   <account_name> local|remote|sync|to_down|to_up|link [optional path]
        change  <account_name> name|email|passwd|local_dir|remote_dir <new_parameter>
        add     <new_account_name|new_file_config>
        del     <account_name>
        search  <file_to_search> [defautl all] [optional account] 
        set_rc  <account_name>
        set_db  <database_name>
        summary
```
Once the database has been created and populated with the file's info we can interact and retrive information. It has many options and you can add as many as you want, because most of them are just normal queries to the database.

| Option | Description |
|--|--|
| `config` | This option is used to view account's config. By default is set to all, if you want just to check one account pass it as argument. By default the password is not shown, if you want to see the password you can either pass `hashed_password` or `password` (plaintext) arguments. To show all accounts you will have to pass as first argument `all`: `mmega_query config all hashed_password`).|
| `state` | This option checks the account/s state. It shows all revelant information about the account's state.
| `files` | This is one of more useful options when managing accounts. It shows account's files by type. So `local` argument will show the files in local_dir, `remote` will do the same with remote_dir, then you can check if there are files to upload (`to_up`) or download (`to_down`). Finally, the `link` option gives the remote files with links (see note about links). You can pass the argument `path` and it will show the path to file instead of the filename.|
| `change` | This option is used to change the accounts config. This option is useful if you do not write a complete config file or you added an incomplete account through add (see below).|
| `add` | This option allows to add one account by command line or serveral accounts through a new config file. If first argument is a file it will be read and all accounts will be added to the database. If the first argument is a string it will be considerated as the account's name. The minimal config for this option is name but you can pass all other arguments like in the config file (in the same order): `mmega_query.sh add $name $email $password $local_dir $remote_dir` |
| `del` | This option deletes all tables and info from the account passed as argument. Only one account can be deleted at time. No confirmation, be careful. |
| `search` | This option is used to search files in the database. When used, if you do not pass any argument it will ask for the filename. If you find many files, you can narrow the search to only one account. Observe that the account argument is given in last position. |
| `set_rc` | Megatools allows a file with account login parameters to avoid to write them each time (see megatools manual). With this option you can set up a megarc file to any account in the database. It is really useful when you are using megatools for several accounts and you need to 'jump' from one account to another. This option is used often, so a alias is created for it: `alias mmega_rc='~/scripts_dir/mmega_query.sh set_rc` |
| `set_db` | This option is useful when you use several databases. This option set the database (only if it exists) in `mmega_functions.sh` updating the entire suite to this database. It also set this database in completion files, but you will have to source you console after execution to make them availaibles. |
| `summary` | This option shows the accounts summary. It resumes config and state of all accounts. |

>**About links**. I have not completely understood the creation of links in mega.nz, but it seems that when a link has been created and then used (only if it is used), the creation of new links deletes the old link, that is, if this link was shared it has to be shared again.

### mmega_sync
```
USAGE = mmega_sync <account_name|all> up|down|sync [with_local|with_remote] [optional no-confirm]

        up               = upload all diferent files from local to remote
        down             = download all diferent files from remote to local
        sync with_local  = upload all differents files and delete all remote differents files
             with_remote = download all differents files and delete all local different files    
```
The others scripts never modify files but this script can delete local and remote files. **Be careful when using it, I decline all responsibility**. As security method, before to make any change the script will show the files (with path) to upload, download or delete (check everything) and will ask for confirmation before proceeding. This confirmation can be omitted using the `no-confirm` argument. 
> Observe that **is not a proper synchronization process**, it only detects the files that are different between the local and remote directories (it does not detect the modification's date or the different size). Perhaps it is more appropriate to call it mmega_copy (as megaus does).
> When using `megacopy` megatools provides a secutity method to never overwrite files. If there are discrepancies the files are marked with a number (that desings the node) and the word "conflict". You will have to check 'by hand' these discrepancies.

Before starting the synchronization process the script will check that the database is updated (this slows down the process considerably). This is very important since the files are taken from the database to determine which files upload, download or delete, so the state of the database should reflect the actual accounts state.

| Option | Description |
|--|--|
|`up`| Upload all diferent files from local to remote. Using `megacopy --reload` command (safe). Although the displayed files come from the database, all responsibility for synchronization falls on `megacopy` command (there may be differences).|
|`down`| Download all diferent files from remote to local. Using `megacopy --reload --download` command (safe). Although the displayed files come from the database, again the responsibility falls on `megacopy`. |
|`sync with_local  ` | It will upload local files (using `megacopy --reload` command (safe)) and will **delete the remote files that are not in local** (using `megarm --reload $path_to_file` command (**danger!**)). The remote directory becomes a copy of the local directory. |
|`sync with_remote  ` | It will download remote files (`megacopy --reload --download` command (safe)) and will **delete the local files that are not in remote** (using `rm $path_to_file` command (**danger!**)). The local directory becomes a copy of the remote directory.|

The confirmation options are:

| Option | Confirmation options |
|--|--|
|`up`| y / n (upload or not) |
|`down`| y / n (download or not) |
|`sync with_local` | **S**ync **C**ancel [**U**pload_only D**e**lete_only]. Use bold letters to choose the option|
|| - Sync will do the two actions, it will upload local files and will delete remote differents files (in this order)|
|| - Cancel will cancel the synchronization process |
|| - Upload_only will upload only the local files to remote directory (safe)|
|| - Delete_only will delete only remote files (danger!) |
|`sync with_remote` | **S**ync **C**ancel [**D**ownload_only D**e**lete_only]. Use bold letters to choose the option |
|| - Sync will do the two actions, it will download remote files and will delete local differents files (in this order)|
|| - Cancel will cancel the synchronization process |
|| - Donwload_only will download only the remote files to local directory (safe)|
|| - Delete_only will delete only local files (danger!) |

The biggest problem with dealing with files is filename. I have tried to take into account all types errors (spaces, special characters, etc.) but in complex directories with long filenames (usually with special characters) there are almost always problems. In addition, megatools and this suite treat filenames differently, so discrepancies may occur. Even with this handicap the possibility of working with several accounts is worth it.

Do not hesitate to commit changes, suggest features or improve the documentation.
