#!/bin/bash

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
SMPPLOAD=$(which smppload 2>/dev/null || echo $SCRIPT_DIR/smppload)

HOST=localhost
PORT=2775
SYSTEM_TYPE=smpp
SYSTEM_ID=test
PASSWORD=test
SRC_ADDR=375296660002
DST_ADDR=375296543210

EXIT=0

function check() {
    local command="$1"
    local encoding="$2"
    local delivery="$3"
    local invert="$4"
    local pattern="$5"
    local count=${6-1}

    case "$delivery" in
        !dlr) dlr_flag=0;;
        dlr) dlr_flag=1
    esac

    case "$encoding" in
        gsm0338) encoding=0;;
        ascii) encoding=1;;
        latin1) encoding=3;;
        ucs2) encoding=8
    esac

    echo -en "$command\t$encoding\t$delivery\t"

    $SMPPLOAD --host=$HOST --port=$PORT \
        --system_type=$SYSTEM_TYPE --system_id=$SYSTEM_ID --password=$PASSWORD \
        --source=$SRC_ADDR --destination=$DST_ADDR --body="$command" --data_coding="$encoding" \
        --delivery=$dlr_flag --submit_timeout=5000 --delivery_timeout=5000 --count=$count \
        -vv | grep "$pattern" > /dev/null

    ret=$?
    if [[ $ret == 0 && "$invert" == "with" ]]; then
        echo -e "\e[32mOK\e[0m"
    elif [[ $ret == 1 && "$invert" == "w/o" ]]; then
        echo -e "\e[32mOK\e[0m"
    else
        echo -e "\e[31mFAIL\e[0m"
        EXIT=1
    fi
}

function check_count() {
    local command="$1"
    local encoding="$2"
    local delivery="$3"
    local invert="$4"
    local pattern="$5"
    local send_count="$6"
    local expected_count="$7"

    case "$delivery" in
        !dlr) dlr_flag=0;;
        dlr) dlr_flag=1
    esac

    case "$encoding" in
        gsm0338) encoding=0;;
        ascii) encoding=1;;
        latin1) encoding=3;;
        ucs2) encoding=8
    esac

    echo -en "$command\t$encoding\t$delivery\t"

    $SMPPLOAD --host=$HOST --port=$PORT \
        --system_type=$SYSTEM_TYPE --system_id=$SYSTEM_ID --password=$PASSWORD \
        --source=$SRC_ADDR --destination=$DST_ADDR --body="$command" --data_coding="$encoding" \
        --delivery=$dlr_flag --submit_timeout=5000 --delivery_timeout=5000 --count=$send_count \
        -vv | grep "$pattern" | wc -l | grep $expected_count > /dev/null

    ret=$?
    if [[ $ret == 0 ]]; then
        echo -e "\e[32mOK\e[0m"
    else
        echo -e "\e[31mFAIL\e[0m"
        EXIT=1
    fi
}

# try to start
$SCRIPT_DIR/../_build/default/rel/smppsink/bin/smppsink start > /dev/null
start_ret=$?
if [[ $start_ret == 0 ]]; then
    # give time to init
    sleep 5
fi

check "submit: 0"   latin1 !dlr w/o "ERROR"
check "submit: 0x0" latin1 !dlr w/o "ERROR"
check "submit: 1"   latin1 !dlr with "ERROR: Failed with: (0x00000001)"
check "submit: 0x1" latin1 !dlr with "ERROR: Failed with: (0x00000001)"


check "submit: {status: 1}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"
check "submit: {status: 1, delay: 0}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"

check "{submit: 1}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"
check "{submit: {status: 1}}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"
check "{submit: {status: 1, delay: 0}}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"


check "receipt: enroute" latin1 !dlr w/o "stat:ENROUTE"
check "receipt: enroute" latin1 dlr with "stat:ENROUTE"

check "receipt: {status: enroute}" latin1 dlr with "stat:ENROUTE"
check "receipt: {status: enroute, delay: 0}" latin1 dlr with "stat:ENROUTE"

check "{receipt: enroute}" latin1 dlr with "stat:ENROUTE"
check "receipt: {status: enroute}" latin1 dlr with "stat:ENROUTE"
check "receipt: {status: enroute, delay: 0}" latin1 dlr with "stat:ENROUTE"


check "{submit: 0, receipt: enroute}" latin1 dlr with "stat:ENROUTE"
check "{submit: {status: 0, delay: 0}, receipt: {status: enroute, delay: 0}}" latin1 dlr with "stat:ENROUTE"

check "{submit: 1, receipt: unknown}" latin1 dlr with "ERROR: Failed with: (0x00000001)"

# w/o spaces
check "{submit:{status:0,delay:0},receipt:{status:enroute,delay:0}}" latin1 dlr with "stat:ENROUTE"

# diff encoding
check "submit:{status:1}" gsm0338 !dlr with "ERROR: Failed with: (0x00000001)"
check "submit:{status:1}" ascii !dlr with "ERROR: Failed with: (0x00000001)"
check "submit:{status:1}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"
#check "submit:{status:1}" ucs2 !dlr with "ERROR: Failed with: (0x00000001)"

check "submit:{delay:-1}" latin1 !dlr w/o "ERROR"
check "submit:{delay:1}"  latin1 !dlr w/o "ERROR"
check "submit:{delay:inf}" latin1 !dlr with "ERROR: Timeout"
check "receipt:{delay:inf}" latin1 dlr with "ERROR: Delivery timeout"
check "submit:{delay:xyz}"  latin1 !dlr w/o "ERROR"

# allow receipt status to be any string and integer
check "receipt:abc" latin1 dlr with "stat:abc"
check "receipt:{status:abc}" latin1 dlr with "stat:abc"
check "receipt:123" latin1 dlr with "stat:123"
check "receipt:{status:123}" latin1 dlr with "stat:123"

#
check "submit:{status:[]}" latin1 !dlr w/o "ERROR"
check "submit:{status:[]}" latin1 dlr with "stat:DELIVRD"

check "submit:{status:{value:1,freq:1.0}}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"
check "submit:{status:[{value:1,freq:1.0}]}" latin1 !dlr with "ERROR: Failed with: (0x00000001)"

# NB! Random algorithm (exsplus) and seed dependent results

check "{submit:{status:{value:1,freq:0.3}},seed:1}" latin1 !dlr with "Send success:     77" 100
check "{submit:{status:{value:1,freq:0.3}},seed:3}" latin1 !dlr with "Send success:     63" 100
check "{submit:{status:[{value:0,freq:0.7},{value:1,freq:0.3}]},seed:5}" latin1 !dlr with "Send success:     71" 100
check "{submit:{status:[{value:0,freq:0.7},{value:1,freq:0.3}]},seed:7}" latin1 !dlr with "Send success:     69" 100

check_count "{receipt:{status:{value:enroute,freq:0.3}},seed:1}" latin1 dlr with "stat:ENROUTE" 100 46
check_count "{receipt:{status:[{value:enroute,freq:0.3}]},seed:2}" latin1 dlr with "stat:ENROUTE" 100 68
check_count "{receipt:{status:[{value:enroute,freq:0.3},{value:accepted,freq:0.2}]},seed:3}" latin1 dlr with "stat:ACCEPTD" 100 40

# stop if wasn't running
if [[ $start_ret == 0 ]]; then
    $SCRIPT_DIR/../_build/default/rel/smppsink/bin/smppsink stop > /dev/null
fi

exit $EXIT
