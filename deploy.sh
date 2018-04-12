#!/usr/bin/env bash
set -o errexit
ip_list=""

named_conf=""
cfg_dir=""
readonly cfg_filename="named.conf.local"
zones_dir=""

while getopts "f:" opt; do  
	case $opt in  
		f)
		ip_list=$OPTARG
		;;  
	esac
done

main() {
	
	# ensure current is root
	user=`whoami`
	if [ "$user" != "root" ]; then
		error "You need to be root to perform this command."
		exit 1
	fi

	install_bind9

}

install_bind9() {
	echo "Starting install the bind9"
	source /etc/os-release
	case $ID in
	debian|ubuntu)
		sudo apt-get install -y libssl-dev bind9 bind9-host dnsutils
		if [ $ip_list ]; then
			ubuntu_bind_cfg
		fi
		;;
	centos|fedora)
		yum install -y openssl-devel bind bind-utils
		if [ $ip_list ]; then
			centos_bind_cfg
		fi
		;;
	*)
		error "Your system is not supported"
		exit 1
		;;
	esac
}

centos_bind_cfg() {
	named_conf="/etc/named.conf"
	cfg_dir="/etc/named"
	zones_dir="/var/named"
	config_ips
	systemctl reload named
}

ubuntu_bind_cfg() {
	named_conf="/etc/bind/named.conf"
	cfg_dir="/etc/bind"
	zones_dir="/etc/bind"
	config_ips
	sudo systemctl start bind9
}

config_ips() {
	if [ ! $ip_list ] || [ ! -f $ip_list ]; then
		error "File ip list file not found."
	fi

	# create local named config file
	local_file="$cfg_dir/$cfg_filename"
	if [ ! -f $local_file ]; then
		if touch $local_file; then
			echo "$local_file created."
		else
			error "Error to create $local_file"
		fi
	fi

	if [ `grep -c "include \"$local_file\"" $named_conf` == '0' ]; then
		echo "include \"$local_file\";" >> $named_conf
	fi

	if [ ! -d "$zones_dir/zones" ]; then
		if mkdir "$zones_dir/zones"; then
			echo "mkdir $zones_dir/zones"
		else
			error "Can't create $zones_dir/zones"
		fi
	fi

	while read line
	do
		domain=`echo "$line" | grep -Eo "[\.a-zA-Z0-9-]*[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+" | head -1`
		sub_domain=`echo ${domain%%.*}`
		parent_domain=`echo ${domain#*.}`
		tmp1=`echo $domain | rev | cut -d "." -f1`
		tmp2=`echo $domain | rev | cut -d "." -f2`
		root_domain=`echo "$tmp1.$tmp2" | rev`

		ip=`echo "$line" | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"`
		# ip: 192.168.1.2
		# ip_sub1: 192
		# ip_sub2: 168
		# ip_sub3: 1
		# ip_sub4: 2
		ip_sub1=`echo $ip | cut -d "." -f1`
		ip_sub2=`echo $ip | cut -d "." -f2`
		ip_sub3=`echo $ip | cut -d "." -f3`
		ip_sub4=`echo $ip | cut -d "." -f4`

		if [ ! $domain ] || [ ! $ip ];then
			continue
		fi

		addr_zone="$zones_dir/zones/$parent_domain.zone"

		# address -> ip
		if [ `grep -c "\"$parent_domain\"" $local_file` == '0' ]; then
			# create zone
			printf "\nzone \"$parent_domain\" IN {\n" >> $local_file
			printf "\ttype master;\n" >> $local_file
			printf "\tfile \"$addr_zone\";\n" >> $local_file
			printf "\tallow-update { none; };\n" >> $local_file
			printf "};\n" >> $local_file
		fi

		if [ ! -f "$addr_zone" ]; then
			create_zonefile "$addr_zone" $parent_domain
		fi
		
		domain2ip "$addr_zone" "$sub_domain" "$ip" "$domain"

		# ip -> address
		arpa_name="$ip_sub2.$ip_sub1.in-addr.arpa"
		ip_zone="$zones_dir/zones/$ip_sub1.$ip_sub2.zone"

		if [ `grep -c "\"$arpa_name\"" $local_file` == '0' ]; then
			# create zone
			printf "\nzone \"$arpa_name\" IN {\n" >> $local_file
			printf "\ttype master;\n" >> $local_file
			printf "\tfile \"$ip_zone\";\n" >> $local_file
			printf "\tallow-update { none; };\n" >> $local_file
			printf "};\n" >> $local_file
		fi
		
		if [ ! -f "$ip_zone" ]; then
			create_zonefile "$ip_zone" "$root_domain"
		fi

		ip2domain "$ip_zone" "$domain" "$ip_sub4.$ip_sub3" "$ip"

	done < $ip_list
}

create_zonefile() {
	file=$1

	ttl="86400"
	serial="1"
	refresh="1H"
	retry="5M"
	expire="1W"
	cache="10M"
	ns="127.0.0.1"

	printf "\$TTL\t$ttl\n" > $file
	printf "@\tIN\tSOA\tns.$2.  admin.$2. (\n" >> $file
	printf "\t\t$serial\t; Serial\n" >> $file
	printf "\t\t$refresh\t; Refresh\n" >> $file
	printf "\t\t$retry\t; Retry\n" >> $file
	printf "\t\t$expire\t; Expire\n" >> $file
	printf "\t\t$cache)\t; Negative Cache TTL\n" >> $file

	printf "; name servers - NS records\n" >> $file
	printf "\tIN\tNS\tns\n" >> $file
	printf "ns\tIN\tA\t$ns\n" >> $file

	echo "$file is created."

}

# $1 file; $2: sub_domain; $3 ip; $4 domain
domain2ip() {
	printf "$2\tIN\tA\t$3\n" >> $1
	echo "Added domain: $4->$3"
}

# $1 file; $2: domain; $3 sub_ip; $4 ip
ip2domain() {
	printf "$3\tIN\tPTR\t$2.\n" >> $1
	echo "Added ip parse: $4->$2"
}

error() {
	echo -e "\033[31m$1\033[0m"
	exit 1
}

main
