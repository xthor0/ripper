#!/bin/bash

startDate=$(date)

# output dir for encoded files
encode_dir=/storage/videos/encoded

log=$(mktemp -t makemkvcon.log.XXXX)
find . -maxdepth 1 -type f -iname "*.mkv" | while read inputfile; do
	newfile=$(basename "$inputfile" .mkv)
    output_file="${encode_dir}/${newfile}.mkv"
	if [ -f "${output_file}" ]; then
		echo "Target already exists: ${output_file} -- skipping."
		continue
	fi

	# remove the title
	mkvpropedit "${inputfile}" -d title
	
	# use mediainfo to determine resolution, and change encoder accordingly. 
	# 1080 / 720: qsv_h264 (it's way faster)
	# 3840 (4k): qsv_h265 (takes longer, but saves some disk space)
	widthdigit=$(mediainfo "${newfile_name}" | grep ^Width | awk '{ print $3 }')
	case ${widthdigit} in
		3) encoder="qsv_h265";preset='Roku 2160p60 4K HEVC Surround';;
		*) encoder="qsv_h264";preset='Roku 1080p30 Surround';;
	esac

	# encode the file with HandBrakeCLI
	echo "Source: ${inputfile}"
	echo "Target: ${output_file}"
	echo "Encoder: ${encoder}"
	echo "Preset: ${preset}"
	log=$(mktemp -t handbrake.log.XXXX)
	echo | flatpak run --command=HandBrakeCLI fr.handbrake.ghb -m -Z "${preset}" -e ${encoder} --encoder-preset speed -s scan --subtitle-burned --subtitle-forced -i "${inputfile}" -o "${output_file}" 2> ${log}
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

# pushover message
test -f ${HOME}/.pushover-api-keys
if [ $? -eq 0 ]; then
    . ${HOME}/.pushover-api-keys
    curl -s --form-string "token=${apitoken}" --form-string "user=${usertoken}" --form-string "message=Notification: Batch HandBrake job completed. :: Start: ${startDate} -- End: ${endDate}" https://api.pushover.net/1/messages.json
fi

echo "All done!"

exit 0
