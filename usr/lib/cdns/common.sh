#!/bin/bash

declare -A PROFILE
declare -A PROFILE_IN_HTB
declare -A PROFILE_IN_NETEM
declare -A PROFILE_OUT_HTB
declare -A PROFILE_OUT_NETEM

CDNS_CFG=/tmp/cdns.cfg

# IP functions
inet_aton() {
    local IFS=. ipaddr ip32 i
    ipaddr=($1)
    for i in 3 2 1 0
    do
        (( ip32 += ipaddr[3-i] * (256 ** i) ))
    done

    echo $ip32
}

check_if_within() {
	testip=`inet_aton $1`
	shift
	for i in $*
	do
		local IFS=/
		range=($i)
		ip=`inet_aton ${range[0]}`
		netmask=${range[1]}
		[ -z "$netmask" ] && netmask=32
		div=$((2**(32-$netmask)))
		[ $(($testip/$div)) -eq $(($ip/$div)) ] && return 0
	done
	return 1
}

is_slave_address() {
	check_if_within $1 ${OUT_SUBNETS[@]}
}

# MASTER config functions
get_master_config() {
	echo $STORAGE/master-$REMOTE_ADDR.cfg
}
get_event_path() {
	EVENT_PATH=$STORAGE/events-$REMOTE_ADDR.cfg
	touch $EVENT_PATH
}

generate_random_number() {
	number=$RANDOM
	while [ "$number" -lt 1000 ] || [ "$number" -ge 10000 ]
	do
 		number=$RANDOM
	done
	echo $number
}

read_master_config() {
	local CONFIG=$(get_master_config)
	local CODE=""
	[ -e $CONFIG ] && CODE=$(cat $(get_master_config))

	if [ "$CODE" == "" ]
	then
		CODE=$(generate_random_number)$(generate_random_number)
		echo $CODE > $CONFIG
	fi

	echo $CODE
}

# SLAVE config functions
read_slave_config() {
	# <ipaddr>
	local CONFIG=$(get_slave_config $1)
	if [ -e $CONFIG ]
	then
		cat $CONFIG
	else
		echo "0 $DEFAULT_PROFILE"
	fi
}

get_slave_config() {
	# <ipaddr>
	echo $STORAGE/slave-$1.cfg
}

update_slave_config() {
	# <ipaddr> <activate_code> <profile>
	local CONFIG=$(get_slave_config $1)
	flock $CONFIG -c "echo $2 $3 > $CONFIG"
}

normalize_ip_addr() {
	# <ipaddr>
	local IFS="."
	local OCTETS=($1)
	local NUM=$(( (${OCTETS[2]}*256+${OCTETS[3]}) ))
	echo ${NUM}
}

update_iptables() {
	iptables -D $*
	iptables -A $*
}

configure_iptables() {
	# <ipaddr>
	update_iptables forwarding_rule -s $1/32 -j RETURN
	update_iptables forwarding_rule -d $1/32 -j RETURN
}

tcc() {
	if ! tc $*
	then
		echo "tc failed: $*" 1>&2
	fi
}

configure_qos() {
	# <ipaddr> <profile>
	[ "${PROFILE[$2]}" == "" ] && return 1

	NUM=$(normalize_ip_addr $1)
	NUM=$((($NUM%9990)+8))
	HANDLE=`printf "%x\n" $((($(normalize_ip_addr $1)%4000)+90))`

	if [ -n "$IN_IFNAME" ]
	then
		tcc class replace dev $IN_IFNAME parent 1:1 classid 1:$NUM htb ${PROFILE_IN_HTB[$2]}
		tcc qdisc replace dev $IN_IFNAME parent 1:$NUM handle 2$NUM: netem ${PROFILE_IN_NETEM[$2]}
		tcc filter replace dev $IN_IFNAME protocol ip parent 1:0 prio 3 u32 match ip src $1 flowid 1:$NUM
	fi

	for i in "${OUT_IFNAME[@]}"
	do
		tcc class replace dev $i parent 1:1 classid 1:$NUM htb ${PROFILE_OUT_HTB[$2]}
		tcc qdisc replace dev $i parent 1:$NUM handle 2$NUM: netem ${PROFILE_OUT_NETEM[$2]}
		tcc filter replace dev $i protocol ip parent 1:0 prio 3 u32 match ip dst $1 flowid 1:$NUM
	done
	return 0
}

valid_ip() {
	# <ip>
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

valid_profile() {
	# <profile>
	for i in "${!PROFILE[@]}"
	do
		[ "$i" == $1 ] && return 0
	done
	return 1
}

push_event() {
	# <event_id> <type> <message> <json>
	EVENT_PATH=
	get_event_path
	EVENT_ID=$1
	EVENT_TYPE=$2
	EVENT_MESSAGE=$3
	EVENT_RANDOM=$(generate_random_number)
	grep -v "^$EVENT_ID " $EVENT_PATH | tail -n 5 > $EVENT_PATH.$EVENT_RANDOM
	echo $EVENT_ID `date +'%Y-%m-%d %H:%M:%S'` $EVENT_TYPE $EVENT_MESSAGE >> $EVENT_PATH.$EVENT_RANDOM
	mv $EVENT_PATH.$EVENT_RANDOM $EVENT_PATH
}

PATHS=
explode_path() {
	# <path_info>
	local IFS=/
	PATHS=($1)
}

if [ "$REMOTE_ADDR" != "" ]
then
	if [ ! -e $CDNS_CFG ]
	then
		cat <<EOF
Content-Type: application/json

{"status": 0, "error": "not initialized"}
EOF
		exit
	fi

	. $CDNS_CFG

	if [ "$CONFIG_DONE" != "1" ]
	then
		cat <<EOF
Content-Type: application/json

{"status": 0, "error": "not initialized"}
EOF
		exit
	fi
fi
