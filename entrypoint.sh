#!/bin/bash

set -e -u

trap 'kill_sshd' INT
trap 'kill_sshd' TERM

# we'll set this later to the PID of the sshd process
sshd=''

kill_sshd() {
	if [[ -n "$sshd" ]]; then
		echo "Killing SSHD..."
		kill -TERM "$sshd"
	fi
}

create_key() {
	local file="$1"
	shift

	printf '\n### %s\n' "$file"
	if [[ -f $file ]]; then
		echo 'Already exists'
	else
		echo 'Generate new'
		ssh-keygen -q -f "$file" -N '' "$@"
	fi
	if [[ ! -f ${file}.pub ]]; then
		ssh-keygen -y -f "${file}" > "${file}.pub"
	fi
	if which restorecon >/dev/null 2>&1; then
		restorecon "$file" "${file}.pub"
	fi

	# Print fingerprints out to log:
	ssh-keygen -E sha256 -l -f "${file}.pub"
	ssh-keygen -v -E md5 -l -f "${file}.pub"
}

create_keys() {
	echo 'Generating SSH Host Keys...'
	mkdir -p /etc/ssh/hostkeys
	create_key /etc/ssh/hostkeys/rsa_key -t rsa
	create_key /etc/ssh/hostkeys/ed25519_key -t ed25519
	echo
	echo
}

create_user() {
	local user="$1"

	echo "Adding user: ${user}"

    if [ -z "$(id -u ${user})" ]; then
		useradd \
			--gid ssh-users \
			--no-user-group \
            --create-home \
			--shell /bin/bash \
			"${user}"
        chmod 0700 "/home/${user}/"
		mkdir -p "/home/${user}/.ssh/"
		touch "/home/${user}/.ssh/authorized_keys"
		chown -R ${user}:ssh-users "/home/${user}/.ssh/"
		chmod 0700 "/home/${user}/.ssh"
		chmod 0400 "/home/${user}/.ssh/authorized_keys"
	else
		echo "${user} already exists"
	fi
}

main() {
	create_keys

	if (( $# < 1 )); then
		echo 'Must supply a list of  usernames to create'
		exit 1
	fi

	for user in $@; do
		create_user "$user"
	done

	echo
	echo '===== Starting SSHD ====='
	# n.b. Not using exec here as sshd doesn't die on SIGINT which is annoying when using docker run (see the trap at the top of the file)
	/usr/sbin/sshd -D -e &
	sshd=$!
	wait $sshd
}

main "$@"
