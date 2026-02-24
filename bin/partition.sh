#!/bin/bash

debug=

# sectors are calculated based on 4K sector size
LB_FORMAT=1

PART_COUNT=1
DEVICES=()

parted_script=$(mktemp)

usage() {
	echo "Usage: $0 [-n|--count <num>] [-d|--device <path>]... [--lbaf|--lba-format <num>] [-h|--help]"
	echo "  -n, --count            Number of data partitions per disk (>=1)"
	echo "  -d, --device           Target device path (repeatable), e.g. /dev/nvme0n1"
	echo "      --lbaf             NVMe LBA format index for format operation (default: ${LB_FORMAT})"
	echo "      --lba-format       Alias for --lbaf"
	echo "  -h, --help             Show this help"
}

cleanup() {
    rm -f $parted_script
}

trap cleanup SIGINT SIGTERM EXIT


function generate_parted_script() {
	local disk=$1
	local count=$2
	local total_sectors_512
	local total_sectors_4k
	local start_sector=5888
	local usable_sectors
	local part_size
	local i
	local p_start
	local p_end
	local p_idx

	# Get disk size in 512-byte sectors
	total_sectors_512=$($debug sudo blockdev --getsz $disk)
	# Convert to 4K sectors
	total_sectors_4k=$((total_sectors_512 / 8))

	cat << EOF > $parted_script
mklabel gpt
mkpart primary 2048s 5887s
name 1 part1
EOF

	if [[ $count -eq 1 ]]; then
		echo "mkpart primary ${start_sector}s 100%" >> $parted_script
		echo "name 2 part2" >> $parted_script
	else
		usable_sectors=$((total_sectors_4k - start_sector))
		part_size=$((usable_sectors / count))

		for ((i=0; i<count; i++)); do
			p_start=$((start_sector + i * part_size))

			if [[ $i -eq $((count - 1)) ]]; then
				p_end="100%"
			else
				p_end="$((start_sector + (i + 1) * part_size - 1))s"
			fi

			p_idx=$((i + 2))
			echo "mkpart primary ${p_start}s ${p_end}" >> $parted_script
			echo "name $p_idx part$p_idx" >> $parted_script
		done
	fi

	echo "print" >> $parted_script
	echo "quit" >> $parted_script
}

function partition_disk() {
	disk=$1

	$debug sudo nvme format --lbaf=$LB_FORMAT $disk
	if [[ $? -ne 0 ]]; then
		echo "Failed to format $disk"
		exit 1
	fi

	generate_parted_script $disk $PART_COUNT

	$debug sudo parted $disk < $parted_script
	if [[ $? -ne 0 ]]; then
		echo "Failed to partition $disk"
		exit 1
	fi
}

### main

while [[ "$#" -gt 0 ]]; do
	case "$1" in
		-n|--count)
			if [[ -z "$2" ]]; then
				echo "Missing value for $1"
				exit 1
			fi
			PART_COUNT="$2"
			shift 2
			;;
		-d|--device)
			if [[ -z "$2" ]]; then
				echo "Missing value for $1"
				exit 1
			fi
			DEVICES+=("$2")
			shift 2
			;;
		--lbaf|--lba-format)
			if [[ -z "$2" ]]; then
				echo "Missing value for $1"
				exit 1
			fi
			LB_FORMAT="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown parameter passed: $1"
			usage
			exit 1
			;;
	esac
done

if [[ $PART_COUNT -lt 1 ]]; then
	echo "Invalid partition count: $PART_COUNT"
	exit 1
fi

if [[ ${#DEVICES[@]} -eq 0 ]]; then
	DEVICES=(/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1)
fi

for d in "${DEVICES[@]}"; do
	if [[ ! -b $d ]]; then
		echo "Disk $d not found"
		exit 1
	fi
	partition_disk $d
done

kikimr_counter=1

# start from p2 since we always have a boot partition
part_counter=2
last_part=$((PART_COUNT + 1))

while [[ $part_counter -le $last_part ]]; do
	for disk in "${DEVICES[@]}"; do
		prefix=0
		if [[ $kikimr_counter -ge 10 ]]; then
			prefix=""
		fi

		$debug sudo ln -s ${disk}p${part_counter} /dev/disk/by-partlabel/kikimr_nvme_${prefix}$kikimr_counter
		kikimr_counter=$((kikimr_counter + 1))
	done
	part_counter=$((part_counter + 1))
done

exit 0
