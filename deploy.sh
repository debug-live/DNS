#!/usr/bin/env bash
set -o errexit

# @Deprecated
openssl_url="https://github.com/openssl/openssl/archive/OpenSSL_1_0_2o.tar.gz"
openssl_filename=`basename $openssl_url`
openssl_dirname=`echo ${openssl_filename%.*}`
openssl_dirname=`echo ${openssl_dirname%.*}`

bind_url="ftp://ftp.isc.org/isc/bind9/cur/9.11/bind-9.11.3.tar.gz"
bind_filename=`basename $bind_url`
bind_dirname=`echo ${bind_filename%.*}`
bind_dirname=`echo ${bind_dirname%.*}`

bind_sysconfdir="/etc/named"
# bind_sysconfdir="."

base_dir=`cd /tmp;pwd`
install_dir="/usr/local"

main() {
	# ensure current is root
	user=`whoami`
	if [ "$user" != "root" ]; then
		error "You need to be root to perform this command."
		exit 1
	fi

	install_dependence

	# install_openssl

	install_bind9

}

# install dependence gcc && wget
install_dependence() {
	echo "Starting install the dependence of Bind9"
	source /etc/os-release
	case $ID in
	debian|ubuntu)
		sudo apt-get install -y gcc wget libssl-dev
		;;
	centos|fedora)
		yum install -y gcc wget openssl-devel
		;;
	*)
		error "Your system is not supported"
		exit 1
		;;
	esac
}

# @Deprecated
# download && build && install openssl
install_openssl() {
	cd $base_dir;pwd
	if [ ! -f "$install_dir/$openssl_dirname/ok.flag" ]; then 
		echo "openssl command is not existed."
		echo "Try to install openssl..."
		if [ ! -f "$openssl_filename" ]; then
			echo "Downloading the openssl source tar file."
			if wget -O $openssl_filename -T 10 -t 3 $openssl_url; then
				extract_tar_gz $openssl_filename
			else
				error "Fail to download openssl tar file."
				exit 1
			fi
		else
			extract_tar_gz $openssl_filename
		fi

		cd $base_dir/$openssl_dirname;pwd
		if [ ! -d "$install_dir/$openssl_dirname" ]; then
			mkdir "$install_dir/$openssl_dirname"
		fi
		./config shared --prefix="$install_dir/$openssl_dirname" -fPIC
		make && make install
		touch "$install_dir/$openssl_dirname/ok.flag"
	else
		echo "openssl has allready installed."
	fi
}

install_bind9() {
	cd $base_dir;pwd
	echo "Starting install bind9 from source."
	if [ ! -f "$bind_filename" ]; then
		echo "Downloading the bind9 source tar file."
		if wget -O $bind_filename -T 10 -t 3 $bind_url; then
			extract_tar_gz $bind_filename
		else
			error "Fail to download bind9 tar file."
			exit 1
		fi
	else
		extract_tar_gz $bind_filename
	fi

	cd $base_dir/$bind_dirname;pwd

	if [ ! -d "$install_dir/$bind_dirname" ]; then
		mkdir "$install_dir/$bind_dirname"
	fi
	if [ ! -d "$bind_sysconfdir" ]; then
		mkdir $bind_sysconfdir
	fi

	./configure --prefix="$install_dir/$bind_dirname" --sysconfdir=$bind_sysconfdir --with-libtool --enable-threads
	make && make install
}

extract_tar_gz() {
	file=`echo ${1%.*}`
	file=`echo ${file%.*}`
	if tar xvzf $1; then 
		for f in $(ls | grep $file)  
	    do  
	        if [ -d $f ] && [ $f != $file ]; then
	        	mv $f $file
	        fi  
	    done;
		echo "Extract $1 success."
	else
		error "Extract $1 fialed."
		exit 1
	fi
}

error() {
	echo -e "\033[31m$1\033[0m"
}

main
