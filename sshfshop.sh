#!/bin/sh

DB_DIR=/tmp/tunnel_sshfs


sub_mount() {

    # default variables
    PORT1=22
    PORT2=22
    FOLDER='~'  # default remote folder to mount

    while [[ $# -gt 0 ]]
    do
        key="$1"

        case $key in

            -h1 | --host1)
                HOST1=$2
                USER1=`echo $HOST1 | cut -f1 -d@`
                shift 2
                ;;
            -h2 | --host2)
                USER2=`echo $2 | cut -f1 -d@`
                HOST2=`echo $2 | cut -f2 -d@ | cut -f1 -d:`
                FOLDER=`echo $2: | cut -f2 -d@ | cut -f2 -d:`
                shift 2
                ;;
            -p1 | --port1)
                PORT1=$2
                shift 2
                ;;
            -p2 | --port2)
                PORT2=$2
                shift 2
                ;;
            *)
                if [ $# -eq 1 ]; then
                    MOUNT_DIR=$1
                    break
                fi
                ;;

        esac

    done

    # check if host1, host2, user2 variables are setted
    if [ ! $HOST1 -o ! $HOST2 -o ! $USER2 ]; then
        echo -e "Error: please set host1 and host2\n"
        help
        exit 1
    fi

    if [ ! -d $DB_DIR ]; then
        mkdir -p $DB_DIR
    fi

    # find first free slot
    slot=1
    for k in `ls $DB_DIR`; do
        if [ $slot -ne $k ]; then
            break
        fi
        slot=$(($slot + 1))
    done


    # mount on host2 folder on host1 temp folder
    out_host1=$(ssh -o "StrictHostKeyChecking=no" -p $PORT1 $HOST1 "tmp_dir=\$(mktemp -d) && sshfs -p $PORT2 $USER2@$HOST2:$FOLDER \$tmp_dir && echo \$tmp_dir && hostname")
    
    if [ $? -ne 0 ]
    then
        echo "Could not mount $USER2@$HOST2:$FOLDER in $HOST1" >&2
        exit 1
    fi

    mount_dir_host1=$(echo $out_host1 | awk '{print $1}')
    name_host1=$(echo $out_host1 | awk '{print $2}')

    echo $mount_dir_host1
    echo $name_host1

    # mount host1 temp folder in local user folder
    sshfs -o "StrictHostKeyChecking=no" -p $PORT1 $USER1@$name_host1:$mount_dir_host1 $MOUNT_DIR

    if [ $? -ne 0 ]
    then
        echo "Could not mount $USER2@$HOST2:$FOLDER in $MOUNT_DIR" >&2
        exit 1
    fi

    echo $USER1@$name_host1 > $DB_DIR/$slot
    echo $mount_dir_host1 >> $DB_DIR/$slot
    echo "$USER2@$HOST2:$FOLDER" >> $DB_DIR/$slot
    echo `readlink -f $MOUNT_DIR` >> $DB_DIR/$slot

}

# get n line from the file
_get_line() {
    head -$1 $2 | tail -1
}

sub_list() {

    if [ ! -d $DB_DIR ]; then
        mkdir -p $DB_DIR
    fi

    for entry in `ls $DB_DIR`; do
        REMOTE_DIR=`_get_line 3 $DB_DIR/$entry`
        MOUNT_DIR=`_get_line 4 $DB_DIR/$entry`
        
        echo "[$entry] $REMOTE_DIR -> $MOUNT_DIR"
    done
}

# _umount_and_rm <mount_number>
_umount_and_rm() {
    mount_number=$1

    # umount local dir
    local_folder=$(_get_line 4 $DB_DIR/$mount_number)
    umount $local_folder

    # try to umount on host1
    host1=$(_get_line 1 $DB_DIR/$mount_number)
    folder_host1=$(_get_line 2 $DB_DIR/$mount_number)
    ssh -o "StrictHostKeyChecking=no" $host1 "umount $folder_host1" 2> /dev/null

    # clean in db
    rm -f $DB_DIR/$mount_number

}

sub_umount() {

    if [ $# = 0 ]; then
        echo "Error: specify a number or a directory"
        exit 1
    fi

    if [[ $1 =~ ^[0-9]+$ ]]; then

        # argument is the number of mounting

        MOUNT_NUMBER=$1

        # check if the number selected exists
        if [ ! -f $DB_DIR/$MOUNT_NUMBER ]; then
            exit 0
        fi
    
        _umount_and_rm $MOUNT_NUMBER        

    elif [[ $1 = all ]]; then

        # remove all
        for entry in `ls $DB_DIR`; do
            sub_umount $entry
        done

    else

        # argument is the path

        UMOUNT_PATH=`readlink -f $1`

        # find local port used for port forwarding
        for entry in `ls $DB_DIR`; do
            mount_path=`_get_line 4 $DB_DIR/$entry`
            if [ $UMOUNT_PATH = $mount_path ]; then
                MOUNT_NUMBER=$entry
                break
            fi
        done

        if [ $MOUNT_NUMBER ]; then
            # a mount exists
            _umount_and_rm $MOUNT_NUMBER
        fi

    fi
    
}

help() {
    echo "Usage: sshfshop [subcommand] [parameters] local_dir
Mount a remote directory using ssh of a node not reachable directly from the current node, but through an intermediate node.

    sshfshop mount (-n1 | --node1 <user1@node1>) (-n2 | --node2 <user2@node2:remote_dir>) [-p1 <ssh port node 1>] [-p2 <ssh port node 2>] <local_directory>
    sshfshop umount (all | <mount_id> | <mount_path>)
    sshfshop list
    sshfshop (-h | --help)"
}

subcommand=$1
case $subcommand in
    "" | "-h" | "--help")
        help
        ;;
    *)
        shift
        sub_$subcommand $@
        if [ $? = 127 ]; then
            echo -e "Error: $subcommand is not a subcommand.\n"
            help
            exit 1
        fi
        ;;

esac
