#!/usr/bin/env ucode
import { readfile } from "fs";
import * as uci from 'uci';

const bands_order = [ "6G", "5G", "2G" ];
const htmode_order = [ "EHT", "HE", "VHT", "HT" ];

let board = json(readfile("/etc/board.json"));
if (!board.wlan)
	exit(0);

let idx = 0;
let commit;

let config = uci.cursor().get_all("wireless") ?? {};

function radio_exists(path, macaddr, phy, radio) {
	for (let name, s in config) {
		if (s[".type"] != "wifi-device")
			continue;
		if (radio != null && int(s.radio) != radio)
			continue;
		if (s.macaddr && lc(s.macaddr) == lc(macaddr))
			return true;
		if (s.phy == phy)
			return true;
		if (!s.path || !path)
			continue;
		if (substr(s.path, -length(path)) == path)
			return true;
	}
}

function get_field_value(phy, field) {
	let path = '/sys/class/ieee80211/' + phy + '/device/uevent';
	try {
		let file = readfile(path);
		let lines = split(file, '\n');
		for (let line in lines) {
			if (match(line,field)) {
				return split(line,'=')[1];
			}
		}
	} catch (e) {
		return null;
	}
	return null;
}

for (let phy_name, phy in board.wlan) {
	let product = get_field_value(phy_name, /^PRODUCT=/);
	if (!product) {
		let driver = get_field_value(phy_name, /^DRIVER=/);
		if (driver == "iwlwifi" || driver == "mt7921e" || driver == "rtw_8822ce" || driver == "rtl88x2ce") {
			product="pcie-" + driver + "-" + get_field_value(phy_name, /^PCI_ID=/);
		} else if (driver == "rtl88x2cs") {
			product="sdio-" + driver + "-" + get_field_value(phy_name, /^SDIO_ID=/);
		}
	}

	let info = phy.info;
	if (!info || !length(info.bands))
		continue;

	let radios = length(info.radios) > 0 ? info.radios : [{ bands: info.bands }];
	for (let radio in radios) {
		while (config[`radio${idx}`])
			idx++;
		let name = "radio" + idx;

		let s = "wireless." + name;
		let si = "wireless.default_" + name;

		let band_name = filter(bands_order, (b) => radio.bands[b])[0];
		if (!band_name)
			continue;

		let band = info.bands[band_name];
		let rband = radio.bands[band_name];
		let channel = rband.default_channel ?? "auto";

		let width = band.max_width;
		if (band_name == "2G")
			width = 20;
		else if (width > 80)
			width = 80;

		let htmode = filter(htmode_order, (m) => band[lc(m)])[0];
		if (htmode)
			htmode += width;
		else
			htmode = "NOHT";

		if (!phy.path)
			continue;

		let macaddr = trim(readfile(`/sys/class/ieee80211/${phy_name}/macaddress`));
		if (radio_exists(phy.path, macaddr, phy_name, radio.index))
			continue;

		let id = `phy='${phy_name}'`;
		if (match(phy_name, /^phy[0-9]/))
			id = `path='${phy.path}'`;

		band_name = lc(band_name);

		let country, encryption, defaults, num_global_macaddr;
		if (band_name == '6g') {
			country = '00';
			encryption = 'owe';
		} else {
			encryption = 'none';
		}
		if (board.wlan.defaults) {
			defaults = board.wlan.defaults.ssids?.[band_name]?.ssid ? board.wlan.defaults.ssids?.[band_name] : board.wlan.defaults.ssids?.all;
			country = board.wlan.defaults.country;
			if (!country && band_name != '2g')
				defaults = null;
			num_global_macaddr = board.wlan.defaults.ssids?.[band_name]?.mac_count;
		}

		if (length(info.radios) > 0)
			id += `\nset ${s}.radio='${radio.index}'`;

		if (product == "bda/b812/210" || product == "bda/c820/200") {
			band_name = '2g';
			htmode = 'HT20';
			channel = 7;
			country = '00';
		// rtl88x2bu / rtl8851bu / rtl88x2cs / rtl88x2ce
		} else if (product == "bda/b82c/210"
			|| product == "bda/b851/0"
			|| product == "sdio-rtl88x2cs-024C:C822"
			|| product == "pcie-rtl88x2ce-10EC:C822") {
			band_name = '5g';
			htmode = 'VHT80';
			channel=157;
			country = 'CN';
			cell_density='0';
		// ax200
		} else if (product == "pcie-iwlwifi-8086:2723") {
			band_name='2g';
			htmode='HT40';
			channel=7;
			country='';
			cell_density='0';
		// mt7921 (pcie & usb)
		} else if (product == "pcie-mt7921e-14C3:7961"
			|| product == "pcie-mt7921e-14C3:0608"
			|| product == "e8d/7961/100") {
			band_name='5g';
			htmode='HE80';
			channel=157;
			country='CN';
			cell_density='0';
		// rtl8822ce
		} else if (product == "pcie-rtw_8822ce-10EC:C822") {
			band_name='5g';
			htmode='VHT80';
			channel=157;
			country='CN';
		} else if (product == "bda/8812/0") {
			country='';
		} else if (product == "bda/c811/200" || product == "e8d/7612/100") {
			country='CN';
		}

		print(`set ${s}=wifi-device
set ${s}.type='mac80211'
set ${s}.${id}
set ${s}.band='${band_name}'
set ${s}.channel='${channel}'
set ${s}.htmode='${htmode}'
set ${s}.country='${country || ''}'
set ${s}.num_global_macaddr='${num_global_macaddr || ''}'
set ${si}.disabled='${defaults ? 0 : 1}'
`);

		if (cell_density) {
			print(`set ${s}.cell_density='${cell_density}'
`);
		}

		print(`set ${si}=wifi-iface
set ${si}.device='${name}'
set ${si}.network='lan'
set ${si}.mode='ap'
set ${si}.encryption='${defaults?.encryption || encryption}'
set ${si}.key='${defaults?.key || "password"}'
`);

		if (defaults?.ssid) {
			print(`set ${si}.ssid='${defaults?.ssid}

`)
		} else {
			let maclen=length('11:22:33:44:55:66');
			let ssid_suffix='';
			if (length(macaddr) != maclen
					|| macaddr == '00:00:00:00:00:00') {
				macaddr=trim(readfile("/sys/class/net/eth0/address"));
			}
			if (length(macaddr) == maclen) {
				let hex = split(macaddr, ':');
				if (hex[0] && hex[1] && hex[5]) {
					ssid_suffix=hex[0]+":"+hex[1]+":"+hex[5];
				}
			}
			if (!length(ssid_suffix)) {
				ssid_suffix = '1234';
			}
			let friendlywrt_ssid = "FriendlyWrt-" + ssid_suffix;
			print(`set ${si}.ssid='${friendlywrt_ssid}'

`)
		}

		config[name] = {};
		commit = true;
	}
}

if (commit)
	print("commit wireless\n");
