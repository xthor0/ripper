#!/bin/bash

startDate=$(date)

# output dir for encoded files
encode_dir=/storage/videos/encoded

# set handbrake profile info
handbrake_preset_file="$(pwd)/../handbrake-presets/MKV-HQ.json"
handbrake_preset=$(cat "${handbrake_preset_file}" | jq -r '.PresetList[0].PresetName')

log=$(mktemp -t makemkvcon.log.XXXX)
find . -maxdepth 1 -type f -iname "*.mkv" | while read inputfile; do
	newfile=$(basename "$inputfile" .mkv)
    output_file="${encode_dir}/${newfile}.mkv"
	if [ -f "${output_file}" ]; then
		echo "Target already exists: ${output_file} -- skipping."
		continue
	fi
	
	echo "Processing ${inputfile} to ${output_file}..."
	start=$(date +%s)
	echo | HandBrakeCLI --preset-import-file "${handbrake_preset_file}" -Z "${handbrake_preset}" -i "${inputfile}" -o "${output_file}" 2> ${log}
    if [ $? -eq 0 ]; then
        rm -f ${log}
    else
        echo "Error - check ${log} for details."
    fi
	end=$(date +%s)
	diff=$(($start-$end))
	echo "$(($diff / 60)) minutes and $(($diff % 60)) seconds elapsed."
done

endDate=$(date)

exit 0
