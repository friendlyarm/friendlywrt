#!/bin/sh

append DRIVERS "mac80211"

check_mac80211_device() {
	local device="$1"
	local path="$2"
	local macaddr="$3"

	[ -n "$found" ] && return 0

	phy_path=
	config_get phy "$device" phy
	json_select wlan
	[ -n "$phy" ] && case "$phy" in
		phy*)
			[ -d /sys/class/ieee80211/$phy ] && \
				phy_path="$(iwinfo nl80211 path "$dev")"
		;;
		*)
			if json_is_a "$phy" object; then
				json_select "$phy"
				json_get_var phy_path path
				json_select ..
			elif json_is_a "${phy%.*}" object; then
				json_select "${phy%.*}"
				json_get_var phy_path path
				json_select ..
				phy_path="$phy_path+${phy##*.}"
			fi
		;;
	esac
	json_select ..
	[ -n "$phy_path" ] || config_get phy_path "$device" path
	[ -n "$path" -a "$phy_path" = "$path" ] && {
		found=1
		return 0
	}

	config_get dev_macaddr "$device" macaddr

	[ -n "$macaddr" -a "$dev_macaddr" = "$macaddr" ] && found=1

	return 0
}


__get_band_defaults() {
	local phy="$1"

	( iw phy "$phy" info; echo ) | awk '
BEGIN {
        bands = ""
}

($1 == "Band" || $1 == "") && band {
        if (channel) {
		mode="NOHT"
		if (ht) mode="HT20"
		if (vht && band != "1:") mode="VHT80"
		if (he) mode="HE80"
		if (he && band == "1:") mode="HE20"
                sub("\\[", "", channel)
                sub("\\]", "", channel)
                bands = bands band channel ":" mode " "
        }
        band=""
}

$1 == "Band" {
        band = $2
        channel = ""
	vht = ""
	ht = ""
	he = ""
}

$0 ~ "Capabilities:" {
	ht=1
}

$0 ~ "VHT Capabilities" {
	vht=1
}

$0 ~ "HE Iftypes" {
	he=1
}

$1 == "*" && $3 == "MHz" && $0 !~ /disabled/ && band && !channel {
        channel = $4
}

END {
        print bands
}'
}

get_band_defaults() {
	local phy="$1"

	for c in $(__get_band_defaults "$phy"); do
		local band="${c%%:*}"
		c="${c#*:}"
		local chan="${c%%:*}"
		c="${c#*:}"
		local mode="${c%%:*}"

		case "$band" in
			1) band=2g;;
			2) band=5g;;
			3) band=60g;;
			4) band=6g;;
			*) band="";;
		esac

		[ -n "$band" ] || continue
		[ -n "$mode_band" -a "$band" = "6g" ] && return

		mode_band="$band"
		channel="$chan"
		htmode="$mode"
	done
}

check_devidx() {
	case "$1" in
	radio[0-9]*)
		local idx="${1#radio}"
		[ "$devidx" -ge "${1#radio}" ] && devidx=$((idx + 1))
		;;
	esac
}

check_board_phy() {
	local name="$2"

	json_select "$name"
	json_get_var phy_path path
	json_select ..

	if [ "$path" = "$phy_path" ]; then
		board_dev="$name"
	elif [ "${path%+*}" = "$phy_path" ]; then
		fallback_board_dev="$name.${path#*+}"
	fi
}

detect_mac80211() {
	devidx=0
	config_load wireless
	config_foreach check_devidx wifi-device

	json_load_file /etc/board.json

	for _dev in /sys/class/ieee80211/*; do
		[ -e "$_dev" ] || continue

		dev="${_dev##*/}"

		mode_band=""
		channel=""
		htmode=""
		ht_capab=""
		cell_density=""
		rx_stbc=""

		get_band_defaults "$dev"

		path="$(iwinfo nl80211 path "$dev")"
		if [ -x /usr/bin/readlink -a -h /sys/class/ieee80211/${dev} ]; then
			product=`cat $(readlink -f /sys/class/ieee80211/${dev}/device)/uevent | grep PRODUCT= | cut -d= -f 2`
			if [ -z "$product" ]; then
				driver=`cat $(readlink -f /sys/class/ieee80211/${dev}/device)/uevent | grep DRIVER= | cut -d= -f 2`
				# {{ added by friendlyelec
				# hack for ax200/mt7921/rtl8822ce
				case "${driver}" in
				"iwlwifi" | \
				"mt7921e" | \
				"rtw_8822ce" | "rtl88x2ce")
					pci_id=`cat $(readlink -f /sys/class/ieee80211/${dev}/device)/uevent | grep PCI_ID= | cut -d= -f 2`
					product="pcie-${driver}-${pci_id}"
					;;
				"rtl88x2cs")
					sd_id=`cat $(readlink -f /sys/class/ieee80211/${dev}/device)/uevent | grep SDIO_ID= | cut -d= -f 2`
					product="sdio-${driver}-${sd_id}"
					;;
				esac
				# }}
			fi
		else
			product=""
		fi
		macaddr="$(cat /sys/class/ieee80211/${dev}/macaddress)"

		# work around phy rename related race condition
		[ -n "$path" -o -n "$macaddr" ] || continue

		board_dev=
		fallback_board_dev=
		json_for_each_item check_board_phy wlan
		[ -n "$board_dev" ] || board_dev="$fallback_board_dev"
		[ -n "$board_dev" ] && dev="$board_dev"

		found=
		config_foreach check_mac80211_device wifi-device "$path" "$macaddr"
		[ -n "$found" ] && continue

		name="radio${devidx}"
		devidx=$(($devidx + 1))
		case "$dev" in
			phy*)
				if [ -n "$path" ]; then
					dev_id="set wireless.${name}.path='$path'"
				else
					dev_id="set wireless.${name}.macaddr='$macaddr'"
				fi
				;;
			*)
				dev_id="set wireless.${name}.phy='$dev'"
				;;
		esac
		
		# {{ added by friendlyelec
		[ -n "$htmode" ] && ht_capab="set wireless.${name}.htmode=$htmode"
		case "${product}" in
		"bda/b812/210" | \
		"bda/c820/200")
			mode_band='2g'
			ht_capab="set wireless.${name}.htmode=HT20"
			channel=7
			country="set wireless.${name}.country='00'"
			;;

		# rtl88x2bu / rtl88x2cs / rtl88x2ce
		"bda/b82c/210" | \
		"sdio-rtl88x2cs-024C:C822" | \
		"pcie-rtl88x2ce-10EC:C822")
			mode_band='5g'
			ht_capab="set wireless.${name}.htmode=VHT80"
			rx_stbc="set wireless.${name}.rx_stbc='0'"
			channel=157
			country="set wireless.${name}.country='CN'"
			cell_density="set wireless.${name}.cell_density='0'"
			;;

		# ax200
		"pcie-iwlwifi-8086:2723")
			mode_band='2g'
			ht_capab="set wireless.${name}.htmode=HT40"
			channel=7
			country=""
			cell_density="set wireless.${name}.cell_density='0'"
			;;

		# mt7921 (pcie & usb)
		"pcie-mt7921e-14C3:7961" | \
		"pcie-mt7921e-14C3:0608" | \
		"e8d/7961/100")
			mode_band='5g'
			ht_capab="set wireless.${name}.htmode=HE80"
			channel=157
			country="set wireless.${name}.country='CN'"
			cell_density="set wireless.${name}.cell_density='0'"
			;;

		# rtl8822ce
		"pcie-rtw_8822ce-10EC:C822")
			mode_band='5g'
			ht_capab="set wireless.${name}.htmode=VHT80"
			channel=157
			country="set wireless.${name}.country='CN'"
			;;

		"bda/8812/0")
			country=""
			;;

		"bda/c811/200" | \
		"e8d/7612/100")
			country="set wireless.${name}.country='CN'"
			;;

		*)
			country=""
			;;

		esac

		ssid_suffix=$(cat /sys/class/ieee80211/${dev}/macaddress | cut -d':' -f1,2,6)
		if [ -z ${ssid_suffix} -o ${ssid_suffix} = "00:00:00" ]; then
			if [ -f /sys/class/net/eth0/address ]; then
				ssid_suffix=$(cat /sys/class/net/eth0/address | cut -d':' -f1,2,6)
			else
				ssid_suffix="1234"
			fi
		fi
		# }}

		uci -q batch <<-EOF
			set wireless.${name}=wifi-device
			set wireless.${name}.type=mac80211
			${dev_id}
			set wireless.${name}.channel=${channel}
			set wireless.${name}.band=${mode_band}
			set wireless.${name}.htmode=$htmode
			${ht_capab}
			${rx_stbc}
			${country}
			${cell_density}
			set wireless.${name}.disabled=1

			set wireless.default_${name}=wifi-iface
			set wireless.default_${name}.device=${name}
			set wireless.default_${name}.network=lan
			set wireless.default_${name}.mode=ap
			set wireless.default_${name}.ssid=FriendlyWrt-${ssid_suffix}
			set wireless.default_${name}.encryption=psk2
			set wireless.default_${name}.key=password
EOF
		uci -q commit wireless
	done
}
